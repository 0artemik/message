import "dotenv/config";
import express from "express";
import cors from "cors";
import http from "http";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { createSign, randomUUID } from "crypto";
import http2 from "http2";
import multer from "multer";
import { Server } from "socket.io";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { db } from "./db.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const voiceDir = path.join(__dirname, "uploads", "voice");
const videoDir = path.join(__dirname, "uploads", "video_note");
const fileDir = path.join(__dirname, "uploads", "files");
for (const d of [voiceDir, videoDir, fileDir]) {
  fs.mkdirSync(d, { recursive: true });
}

const PORT = Number(process.env.PORT) || 3001;
const JWT_SECRET = process.env.JWT_SECRET || "dev-secret-change-me";
const CLIENT_ORIGIN = process.env.CLIENT_ORIGIN || "http://localhost:5173";
const APNS_KEY_ID = process.env.APNS_KEY_ID || "";
const APNS_TEAM_ID = process.env.APNS_TEAM_ID || "";
const APNS_BUNDLE_ID = process.env.APNS_BUNDLE_ID || "";
const APNS_PRIVATE_KEY = (process.env.APNS_PRIVATE_KEY || "").replace(/\\n/g, "\n");
const APNS_USE_PRODUCTION = process.env.APNS_USE_PRODUCTION === "1";

const userSocketCount = new Map();
const httpPresenceUntil = new Map();
const HTTP_PRESENCE_TTL_MS = 75_000;

function normalizeClientType(raw) {
  const v = String(raw || "").trim().toLowerCase();
  if (v === "ios" || v === "android" || v === "web") return v;
  return "web";
}

function detectClientType(req) {
  const fromHeader = normalizeClientType(req.headers["x-client-type"]);
  if (fromHeader !== "web") return fromHeader;
  const ua = String(req.headers["user-agent"] || "").toLowerCase();
  if (ua.includes("iphone") || ua.includes("ipad") || ua.includes("ios")) return "ios";
  if (ua.includes("android")) return "android";
  return "web";
}

function safeDeviceName(req) {
  const ua = String(req.headers["user-agent"] || "").trim();
  if (!ua) return "Unknown device";
  return ua.slice(0, 220);
}

function createSessionAndToken(req, userId, username) {
  const sid = randomUUID();
  const token = jwt.sign({ sub: userId, username, sid }, JWT_SECRET, {
    expiresIn: "30d",
  });
  db.prepare(
    `INSERT INTO auth_sessions (sid, user_id, client_type, device, expires_at)
     VALUES (?, ?, ?, ?, datetime('now', '+30 days'))`
  ).run(sid, userId, detectClientType(req), safeDeviceName(req));
  return token;
}

function isUserOnline(userId) {
  if ((userSocketCount.get(userId) || 0) > 0) return true;
  return (httpPresenceUntil.get(userId) || 0) > Date.now();
}

function touchLastSeen(userId) {
  db.prepare("UPDATE users SET last_seen_at = datetime('now') WHERE id = ?").run(userId);
}

function getPartnerUserIds(userId) {
  const rows = db
    .prepare(
      `SELECT DISTINCT cm2.user_id AS uid
       FROM conversation_members cm1
       JOIN conversation_members cm2 ON cm2.conversation_id = cm1.conversation_id
       WHERE cm1.user_id = ? AND cm2.user_id != ?`
    )
    .all(userId, userId);
  return rows.map((r) => r.uid);
}

function broadcastPresence(userId, online) {
  const row = db.prepare("SELECT last_seen_at FROM users WHERE id = ?").get(userId);
  const lastSeenAt = row?.last_seen_at ?? null;
  const partners = getPartnerUserIds(userId);
  for (const pid of partners) {
    io.to(`uid:${pid}`).emit("presence", { userId, online, lastSeenAt });
  }
}

function onUserSocketConnect(userId) {
  const wasOnline = isUserOnline(userId);
  const n = (userSocketCount.get(userId) || 0) + 1;
  userSocketCount.set(userId, n);
  if (!wasOnline && isUserOnline(userId)) {
    touchLastSeen(userId);
    broadcastPresence(userId, true);
  }
}

function onUserSocketDisconnect(userId) {
  const wasOnline = isUserOnline(userId);
  const n = (userSocketCount.get(userId) || 0) - 1;
  if (n <= 0) {
    userSocketCount.delete(userId);
  } else {
    userSocketCount.set(userId, n);
  }
  if (wasOnline && !isUserOnline(userId)) {
    touchLastSeen(userId);
    broadcastPresence(userId, false);
  }
}

function touchHttpPresence(userId) {
  const wasOnline = isUserOnline(userId);
  httpPresenceUntil.set(userId, Date.now() + HTTP_PRESENCE_TTL_MS);
  if (!wasOnline && isUserOnline(userId)) {
    touchLastSeen(userId);
    broadcastPresence(userId, true);
  }
}

function sweepExpiredHttpPresence() {
  const now = Date.now();
  for (const [uid, until] of httpPresenceUntil.entries()) {
    if (until > now) continue;
    httpPresenceUntil.delete(uid);
    if (!isUserOnline(uid)) {
      touchLastSeen(uid);
      broadcastPresence(uid, false);
    }
  }
}

function sendPresenceSnapshot(socket, userId) {
  for (const pid of getPartnerUserIds(userId)) {
    const online = isUserOnline(pid);
    const row = db.prepare("SELECT last_seen_at FROM users WHERE id = ?").get(pid);
    socket.emit("presence", {
      userId: pid,
      online,
      lastSeenAt: row?.last_seen_at ?? null,
    });
  }
}

function messageToPayload(msg, conversationId) {
  return {
    id: msg.id,
    conversationId,
    senderId: msg.sender_id,
    body: msg.body ?? "",
    kind: msg.kind || "text",
    voiceDurationMs: msg.voice_duration_ms ?? null,
    fileName: msg.file_name ?? null,
    fileMime: msg.file_mime ?? null,
    fileSize: msg.file_size ?? null,
    videoDurationMs: msg.video_duration_ms ?? null,
    clientMsgId: msg.client_msg_id ?? null,
    createdAt: msg.created_at,
  };
}

function getPeerLastReadMessageId(conversationId, myUserId) {
  const row = db
    .prepare(
      `SELECT COALESCE(last_read_message_id, 0) AS last_read
       FROM conversation_members
       WHERE conversation_id = ? AND user_id != ?
       LIMIT 1`
    )
    .get(conversationId, myUserId);
  return Number(row?.last_read || 0);
}

function markConversationRead(conversationId, userId, uptoMessageId = null) {
  const current = db
    .prepare(
      "SELECT COALESCE(last_read_message_id, 0) AS v FROM conversation_members WHERE conversation_id = ? AND user_id = ?"
    )
    .get(conversationId, userId)?.v;
  const latestInConv = db
    .prepare("SELECT COALESCE(MAX(id), 0) AS v FROM messages WHERE conversation_id = ?")
    .get(conversationId)?.v;
  const target = Math.max(
    Number(current || 0),
    Math.min(Number(latestInConv || 0), Number(uptoMessageId || latestInConv || 0))
  );
  db.prepare("UPDATE conversation_members SET last_read_message_id = ? WHERE conversation_id = ? AND user_id = ?").run(
    target,
    conversationId,
    userId
  );
  return target;
}

function lastMessageFromRow(r) {
  if (r?.last_created_at == null) return null;
  const kind = r.last_kind || "text";
  const body = kind === "text" || kind === "file" ? r.last_body ?? "" : "";
  return {
    body,
    kind,
    fileName: r.last_file_name ?? null,
    createdAt: r.last_created_at,
    senderId: r.last_sender_id,
  };
}

function safeFilename(name) {
  const base = path.basename(String(name || "file")).replace(/[^\w.\-()\s\u0400-\u04FF]+/g, "_");
  return base.slice(0, 180) || "file";
}

function extFromMime(mime) {
  if (mime === "video/webm") return ".webm";
  if (mime === "video/mp4") return ".mp4";
  if (mime === "video/quicktime") return ".mov";
  return "";
}

function base64url(input) {
  return Buffer.from(input).toString("base64url");
}

function makeApnsJwt() {
  if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_PRIVATE_KEY) return null;
  const header = { alg: "ES256", kid: APNS_KEY_ID };
  const payload = { iss: APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) };
  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const sign = createSign("SHA256");
  sign.update(unsigned);
  sign.end();
  const sig = sign.sign(APNS_PRIVATE_KEY).toString("base64url");
  return `${unsigned}.${sig}`;
}

async function sendApnsToToken(token, alert) {
  const jwtToken = makeApnsJwt();
  if (!jwtToken || !APNS_BUNDLE_ID) return false;
  const host = APNS_USE_PRODUCTION ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
  return await new Promise((resolve) => {
    const client = http2.connect(host);
    client.on("error", () => {
      try {
        client.close();
      } catch {
        /* ignore */
      }
      resolve(false);
    });
    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${token}`,
      authorization: `bearer ${jwtToken}`,
      "apns-topic": APNS_BUNDLE_ID,
      "apns-push-type": "alert",
      "content-type": "application/json",
    });
    let status = 0;
    req.on("response", (headers) => {
      status = Number(headers[":status"] || 0);
    });
    req.on("error", () => {
      try {
        client.close();
      } catch {
        /* ignore */
      }
      resolve(false);
    });
    req.on("end", () => {
      try {
        client.close();
      } catch {
        /* ignore */
      }
      resolve(status >= 200 && status < 300);
    });
    req.end(
      JSON.stringify({
        aps: {
          alert,
          sound: "default",
          badge: 1,
        },
      })
    );
  });
}

function messagePushText(payload) {
  if (payload.kind === "voice") return "Голосовое сообщение";
  if (payload.kind === "video_note") return "Видеосообщение";
  if (payload.kind === "file") return `📎 ${payload.fileName || "Файл"}`;
  return String(payload.body || "Новое сообщение").slice(0, 120);
}

async function pushNewMessage(conversationId, senderId, payload) {
  if (!APNS_BUNDLE_ID || !APNS_KEY_ID || !APNS_TEAM_ID || !APNS_PRIVATE_KEY) return;
  const sender = db.prepare("SELECT display_name FROM users WHERE id = ?").get(senderId);
  const rows = db
    .prepare(
      `SELECT cm.user_id AS user_id, pd.token AS token
       FROM conversation_members cm
       JOIN push_devices pd ON pd.user_id = cm.user_id
       WHERE cm.conversation_id = ? AND cm.user_id != ? AND pd.platform = 'ios'`
    )
    .all(conversationId, senderId);
  if (!rows.length) return;
  const title = sender?.display_name || "Новое сообщение";
  const body = messagePushText(payload);
  const dedup = new Set();
  for (const r of rows) {
    if (!r?.token || dedup.has(r.token)) continue;
    dedup.add(r.token);
    if (isUserOnline(r.user_id)) continue;
    const ok = await sendApnsToToken(r.token, { title, body });
    if (!ok) {
      db.prepare("DELETE FROM push_devices WHERE platform = 'ios' AND token = ?").run(r.token);
    }
  }
}

const app = express();
const httpServer = http.createServer(app);
const io = new Server(httpServer, {
  cors: { origin: CLIENT_ORIGIN, credentials: true },
});

app.use(cors({ origin: CLIENT_ORIGIN, credentials: true }));
app.use(express.json());

const voiceStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, voiceDir),
  filename: (_req, _file, cb) => cb(null, `${randomUUID()}.webm`),
});

const uploadVoice = multer({
  storage: voiceStorage,
  limits: { fileSize: 15 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (file.mimetype.startsWith("audio/") || file.mimetype === "application/octet-stream") {
      cb(null, true);
    } else {
      cb(new Error("Нужен аудиофайл"));
    }
  },
});

const videoStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, videoDir),
  filename: (_req, file, cb) => {
    const ext = extFromMime(file.mimetype) || ".webm";
    cb(null, `${randomUUID()}${ext}`);
  },
});

const uploadVideoNote = multer({
  storage: videoStorage,
  limits: { fileSize: 40 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (file.mimetype.startsWith("video/") || file.mimetype === "application/octet-stream") {
      cb(null, true);
    } else {
      cb(new Error("Нужен видеофайл"));
    }
  },
});

const fileStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, fileDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(safeFilename(file.originalname)) || "";
    cb(null, `${randomUUID()}${ext}`);
  },
});

const uploadAttachment = multer({
  storage: fileStorage,
  limits: { fileSize: 40 * 1024 * 1024 },
});

function authMiddleware(req, res, next) {
  const h = req.headers.authorization;
  if (!h?.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Требуется авторизация" });
  }
  try {
    const token = h.slice(7);
    const decoded = jwt.verify(token, JWT_SECRET);
    if (decoded.sid) {
      const s = db
        .prepare(
          `SELECT sid
           FROM auth_sessions
           WHERE sid = ? AND user_id = ? AND revoked_at IS NULL
             AND datetime(expires_at) > datetime('now')`
        )
        .get(decoded.sid, decoded.sub);
      if (!s) return res.status(401).json({ error: "Сеанс истёк. Войдите снова" });
    }
    req.user = decoded;
    const clientType = detectClientType(req);
    req.clientType = clientType;
    if (clientType === "ios" || clientType === "android") {
      touchHttpPresence(decoded.sub);
    }
    next();
  } catch {
    return res.status(401).json({ error: "Недействительный токен" });
  }
}

setInterval(sweepExpiredHttpPresence, 15_000).unref();

function userPublic(row) {
  if (!row) return null;
  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name,
  };
}

function selectFullMessage(id) {
  return db
    .prepare(
      `SELECT id, sender_id, body, created_at, kind, voice_duration_ms, voice_path,
              file_path, file_name, file_mime, file_size, video_duration_ms, client_msg_id
       FROM messages WHERE id = ?`
    )
    .get(id);
}

function assertConvMember(convId, userId) {
  return db
    .prepare("SELECT 1 FROM conversation_members WHERE conversation_id = ? AND user_id = ?")
    .get(convId, userId);
}

// --- Auth ---
app.post("/api/auth/register", (req, res) => {
  const { username, email, password, displayName } = req.body || {};
  const u = String(username || "").trim();
  const e = String(email || "").trim().toLowerCase();
  const p = String(password || "");
  const dn = String(displayName || u).trim() || u;
  if (u.length < 3) return res.status(400).json({ error: "Логин не короче 3 символов" });
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) return res.status(400).json({ error: "Некорректный email" });
  if (p.length < 6) return res.status(400).json({ error: "Пароль не короче 6 символов" });
  const hash = bcrypt.hashSync(p, 10);
  try {
    const info = db
      .prepare(
        "INSERT INTO users (username, email, password_hash, display_name) VALUES (?, ?, ?, ?)"
      )
      .run(u, e, hash, dn);
    const token = createSessionAndToken(req, info.lastInsertRowid, u);
    const row = db.prepare("SELECT id, username, display_name FROM users WHERE id = ?").get(info.lastInsertRowid);
    touchLastSeen(info.lastInsertRowid);
    res.status(201).json({ token, user: userPublic(row) });
  } catch (err) {
    if (String(err).includes("UNIQUE")) {
      return res.status(409).json({ error: "Пользователь с таким логином или email уже есть" });
    }
    throw err;
  }
});

app.post("/api/auth/login", (req, res) => {
  const { username, password } = req.body || {};
  const u = String(username || "").trim();
  const p = String(password || "");
  if (!u || !p) return res.status(400).json({ error: "Логин и пароль обязательны" });
  const row = db
    .prepare("SELECT id, username, password_hash, display_name FROM users WHERE username = ? COLLATE NOCASE")
    .get(u);
  if (!row || !bcrypt.compareSync(p, row.password_hash)) {
    return res.status(401).json({ error: "Неверный логин или пароль" });
  }
  const token = createSessionAndToken(req, row.id, row.username);
  touchLastSeen(row.id);
  res.json({ token, user: userPublic(row) });
});

app.post("/api/auth/change-password", authMiddleware, (req, res) => {
  const oldPassword = String(req.body?.oldPassword || "");
  const newPassword = String(req.body?.newPassword || "");
  if (!oldPassword || !newPassword) {
    return res.status(400).json({ error: "Старый и новый пароль обязательны" });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ error: "Новый пароль не короче 6 символов" });
  }
  if (oldPassword === newPassword) {
    return res.status(400).json({ error: "Новый пароль должен отличаться от старого" });
  }

  const row = db.prepare("SELECT password_hash FROM users WHERE id = ?").get(req.user.sub);
  if (!row || !bcrypt.compareSync(oldPassword, row.password_hash)) {
    return res.status(401).json({ error: "Старый пароль неверный" });
  }
  const hash = bcrypt.hashSync(newPassword, 10);
  db.prepare("UPDATE users SET password_hash = ? WHERE id = ?").run(hash, req.user.sub);
  db.prepare("UPDATE auth_sessions SET revoked_at = datetime('now') WHERE user_id = ?").run(req.user.sub);
  res.json({ ok: true });
});

app.get("/api/auth/sessions", authMiddleware, (req, res) => {
  const rows = db
    .prepare(
      `SELECT sid, client_type, device, created_at
       FROM auth_sessions
       WHERE user_id = ? AND revoked_at IS NULL
         AND datetime(expires_at) > datetime('now')
       ORDER BY datetime(created_at) DESC`
    )
    .all(req.user.sub);
  res.json({
    sessions: rows.map((r) => ({
      sid: r.sid,
      clientType: r.client_type,
      device: r.device,
      createdAt: r.created_at,
      current: req.user.sid ? r.sid === req.user.sid : false,
    })),
  });
});

app.post("/api/auth/sessions/revoke-others", authMiddleware, (req, res) => {
  if (!req.user.sid) return res.status(400).json({ error: "Текущий сеанс не определён" });
  const info = db
    .prepare(
      `UPDATE auth_sessions
       SET revoked_at = datetime('now')
       WHERE user_id = ? AND sid != ? AND revoked_at IS NULL`
    )
    .run(req.user.sub, req.user.sid);
  res.json({ ok: true, revoked: info.changes || 0 });
});

app.get("/api/auth/me", authMiddleware, (req, res) => {
  const row = db
    .prepare("SELECT id, username, display_name FROM users WHERE id = ?")
    .get(req.user.sub);
  if (!row) return res.status(404).json({ error: "Пользователь не найден" });
  res.json({ user: userPublic(row) });
});

app.get("/api/presence/batch", authMiddleware, (req, res) => {
  const raw = String(req.query.ids || "");
  const ids = raw
    .split(",")
    .map((x) => Number(x.trim()))
    .filter((n) => Number.isFinite(n) && n > 0 && n !== req.user.sub);
  const unique = [...new Set(ids)];
  const out = {};
  for (const id of unique) {
    out[id] = {
      online: isUserOnline(id),
      lastSeenAt: db.prepare("SELECT last_seen_at FROM users WHERE id = ?").get(id)?.last_seen_at ?? null,
    };
  }
  res.json({ presence: out });
});

app.post("/api/presence/ping", authMiddleware, (req, res) => {
  if (req.clientType === "ios" || req.clientType === "android") {
    touchHttpPresence(req.user.sub);
  }
  res.json({ ok: true });
});

app.post("/api/push/register", authMiddleware, (req, res) => {
  const platform = String(req.body?.platform || "").trim().toLowerCase();
  const token = String(req.body?.token || "").trim();
  if (platform !== "ios") return res.status(400).json({ error: "Поддерживается только ios" });
  if (!token || token.length < 20) return res.status(400).json({ error: "Некорректный push token" });
  db.prepare(
    `INSERT INTO push_devices (user_id, platform, token)
     VALUES (?, ?, ?)
     ON CONFLICT(platform, token) DO UPDATE SET
       user_id = excluded.user_id,
       last_seen_at = datetime('now')`
  ).run(req.user.sub, platform, token);
  res.json({ ok: true });
});

app.get("/api/users/search", authMiddleware, (req, res) => {
  const q = String(req.query.q || "").trim();
  if (q.length < 2) return res.json({ users: [] });
  const like = `%${q.replace(/%/g, "").replace(/_/g, "")}%`;
  const rows = db
    .prepare(
      `SELECT id, username, display_name FROM users
       WHERE id != ? AND (username LIKE ? COLLATE NOCASE OR display_name LIKE ? COLLATE NOCASE)
       ORDER BY username COLLATE NOCASE
       LIMIT 30`
    )
    .all(req.user.sub, like, like);
  res.json({ users: rows.map(userPublic) });
});

function getDirectConversationId(a, b) {
  const row = db
    .prepare(
      `SELECT c.id FROM conversations c
       JOIN conversation_members m1 ON m1.conversation_id = c.id AND m1.user_id = ?
       JOIN conversation_members m2 ON m2.conversation_id = c.id AND m2.user_id = ?
       WHERE (SELECT COUNT(*) FROM conversation_members WHERE conversation_id = c.id) = 2
       LIMIT 1`
    )
    .get(a, b);
  return row?.id ?? null;
}

app.post("/api/conversations/direct", authMiddleware, (req, res) => {
  const otherId = Number(req.body?.userId);
  if (!otherId || otherId === req.user.sub) {
    return res.status(400).json({ error: "Некорректный пользователь" });
  }
  const other = db.prepare("SELECT id FROM users WHERE id = ?").get(otherId);
  if (!other) return res.status(404).json({ error: "Пользователь не найден" });

  let convId = getDirectConversationId(req.user.sub, otherId);
  if (!convId) {
    const tx = db.transaction(() => {
      const info = db.prepare("INSERT INTO conversations DEFAULT VALUES").run();
      convId = info.lastInsertRowid;
      db.prepare("INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?)").run(
        convId,
        req.user.sub
      );
      db.prepare("INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?)").run(
        convId,
        otherId
      );
    });
    tx();
  }

  const peer = db
    .prepare("SELECT id, username, display_name FROM users WHERE id = ?")
    .get(otherId);
  const lastMsg = db
    .prepare(
      `SELECT m.body, m.created_at, m.sender_id, m.kind, m.file_name FROM messages m
       WHERE m.conversation_id = ? ORDER BY m.id DESC LIMIT 1`
    )
    .get(convId);

  res.json({
    conversation: {
      id: convId,
      peer: userPublic(peer),
      lastMessage: lastMsg
        ? lastMessageFromRow({
            last_body: lastMsg.body,
            last_created_at: lastMsg.created_at,
            last_sender_id: lastMsg.sender_id,
            last_kind: lastMsg.kind,
            last_file_name: lastMsg.file_name,
          })
        : null,
    },
  });
});

app.get("/api/conversations", authMiddleware, (req, res) => {
  const rows = db
    .prepare(
      `SELECT c.id AS conversation_id,
              u.id AS peer_id, u.username AS peer_username, u.display_name AS peer_display_name,
              m.body AS last_body, m.created_at AS last_created_at, m.sender_id AS last_sender_id,
              m.kind AS last_kind, m.file_name AS last_file_name,
              (
                SELECT COUNT(*)
                FROM messages um
                WHERE um.conversation_id = c.id
                  AND um.sender_id != ?
                  AND um.id > COALESCE(me.last_read_message_id, 0)
              ) AS unread_count
       FROM conversations c
       JOIN conversation_members me ON me.conversation_id = c.id AND me.user_id = ?
       JOIN conversation_members them ON them.conversation_id = c.id AND them.user_id != ?
       JOIN users u ON u.id = them.user_id
       LEFT JOIN messages m ON m.id = (
         SELECT id FROM messages WHERE conversation_id = c.id ORDER BY id DESC LIMIT 1
       )
       ORDER BY COALESCE(m.created_at, c.created_at) DESC`
    )
    .all(req.user.sub, req.user.sub, req.user.sub);

  const list = rows.map((r) => ({
    id: r.conversation_id,
    peer: userPublic({
      id: r.peer_id,
      username: r.peer_username,
      display_name: r.peer_display_name,
    }),
    lastMessage: lastMessageFromRow(r),
    unreadCount: Number(r.unread_count || 0),
  }));
  res.json({ conversations: list });
});

app.get("/api/conversations/:id/messages", authMiddleware, (req, res) => {
  const convId = Number(req.params.id);
  if (!assertConvMember(convId, req.user.sub)) return res.status(404).json({ error: "Чат не найден" });
  const beforeId = Number(req.query.beforeId || 0);
  const limitRaw = Number(req.query.limit || 50);
  const limit = Math.max(1, Math.min(100, Number.isFinite(limitRaw) ? limitRaw : 50));
  const peerLastRead = getPeerLastReadMessageId(convId, req.user.sub);

  const rows = db
    .prepare(
      `SELECT id, sender_id, body, created_at, kind, voice_duration_ms,
              file_name, file_mime, file_size, video_duration_ms, client_msg_id
       FROM messages
       WHERE conversation_id = ?
         AND (? <= 0 OR id < ?)
       ORDER BY id DESC
       LIMIT ?`
    )
    .all(convId, beforeId, beforeId, limit);
  const asc = rows.slice().reverse();
  const hasMore = rows.length === limit;
  const nextBeforeId = hasMore && asc.length > 0 ? asc[0].id : null;
  res.json({
    messages: asc.map((m) => ({
      id: m.id,
      senderId: m.sender_id,
      body: m.body ?? "",
      kind: m.kind || "text",
      voiceDurationMs: m.voice_duration_ms,
      fileName: m.file_name,
      fileMime: m.file_mime,
      fileSize: m.file_size,
      videoDurationMs: m.video_duration_ms,
      clientMsgId: m.client_msg_id ?? null,
      isRead: m.sender_id === req.user.sub ? m.id <= peerLastRead : true,
      createdAt: m.created_at,
    })),
    hasMore,
    nextBeforeId,
  });
});

app.post("/api/conversations/:id/read", authMiddleware, (req, res) => {
  const convId = Number(req.params.id);
  if (!assertConvMember(convId, req.user.sub)) return res.status(404).json({ error: "Чат не найден" });
  const upToMessageId = Number(req.body?.upToMessageId || 0) || null;
  const actual = markConversationRead(convId, req.user.sub, upToMessageId);
  io.to(`conv:${convId}`).emit("read", {
    conversationId: convId,
    readerId: req.user.sub,
    upToMessageId: actual,
  });
  res.json({ ok: true, upToMessageId: actual });
});

app.post("/api/conversations/:id/messages", authMiddleware, (req, res) => {
  const convId = Number(req.params.id);
  const body = String(req.body?.body ?? "").trim();
  const clientMsgId = String(req.body?.clientMsgId ?? "").trim().slice(0, 120) || null;
  if (!body) return res.status(400).json({ error: "Пустое сообщение" });
  if (!assertConvMember(convId, req.user.sub)) return res.status(404).json({ error: "Чат не найден" });

  if (clientMsgId) {
    const existing = db
      .prepare(
        "SELECT id, sender_id, body, created_at, kind, voice_duration_ms, file_name, file_mime, file_size, video_duration_ms, client_msg_id FROM messages WHERE conversation_id = ? AND sender_id = ? AND client_msg_id = ?"
      )
      .get(convId, req.user.sub, clientMsgId);
    if (existing) {
      const payloadExisting = messageToPayload(existing, convId);
      return res.status(200).json({ message: payloadExisting });
    }
  }

  const info = db
    .prepare(
      "INSERT INTO messages (conversation_id, sender_id, body, kind, client_msg_id) VALUES (?, ?, ?, 'text', ?)"
    )
    .run(convId, req.user.sub, body, clientMsgId);
  const msg = selectFullMessage(info.lastInsertRowid);
  const payload = messageToPayload(msg, convId);
  io.to(`conv:${convId}`).emit("message", payload);
  pushNewMessage(convId, req.user.sub, payload).catch(() => {});
  res.status(201).json({ message: payload });
});

app.post(
  "/api/conversations/:id/messages/voice",
  authMiddleware,
  (req, res, next) => {
    uploadVoice.single("audio")(req, res, (err) => {
      if (err) return res.status(400).json({ error: err.message || "Ошибка загрузки" });
      next();
    });
  },
  (req, res) => {
    const convId = Number(req.params.id);
    if (!assertConvMember(convId, req.user.sub)) return res.status(404).json({ error: "Чат не найден" });
    if (!req.file) return res.status(400).json({ error: "Нет аудио" });

    const durationMs = Math.min(
      600_000,
      Math.max(0, Math.floor(Number(req.body?.durationMs) || 0))
    );
    const filename = req.file.filename;

    const info = db
      .prepare(
        `INSERT INTO messages (conversation_id, sender_id, body, kind, voice_path, voice_duration_ms)
         VALUES (?, ?, '', 'voice', ?, ?)`
      )
      .run(convId, req.user.sub, filename, durationMs || null);

    const msg = selectFullMessage(info.lastInsertRowid);
    const payload = messageToPayload(msg, convId);
    io.to(`conv:${convId}`).emit("message", payload);
    pushNewMessage(convId, req.user.sub, payload).catch(() => {});
    res.status(201).json({ message: payload });
  }
);

app.post(
  "/api/conversations/:id/messages/video-note",
  authMiddleware,
  (req, res, next) => {
    uploadVideoNote.single("video")(req, res, (err) => {
      if (err) return res.status(400).json({ error: err.message || "Ошибка загрузки" });
      next();
    });
  },
  (req, res) => {
    const convId = Number(req.params.id);
    if (!assertConvMember(convId, req.user.sub)) return res.status(404).json({ error: "Чат не найден" });
    if (!req.file) return res.status(400).json({ error: "Нет видео" });

    const durationMs = Math.min(
      120_000,
      Math.max(0, Math.floor(Number(req.body?.durationMs) || 0))
    );
    const filename = req.file.filename;
    const mime = req.file.mimetype || "video/webm";
    const size = req.file.size || 0;

    const info = db
      .prepare(
        `INSERT INTO messages (conversation_id, sender_id, body, kind, file_path, file_mime, file_size, video_duration_ms)
         VALUES (?, ?, '', 'video_note', ?, ?, ?, ?)`
      )
      .run(convId, req.user.sub, filename, mime, size, durationMs || null);

    const msg = selectFullMessage(info.lastInsertRowid);
    const payload = messageToPayload(msg, convId);
    io.to(`conv:${convId}`).emit("message", payload);
    pushNewMessage(convId, req.user.sub, payload).catch(() => {});
    res.status(201).json({ message: payload });
  }
);

app.post(
  "/api/conversations/:id/messages/file",
  authMiddleware,
  (req, res, next) => {
    uploadAttachment.single("file")(req, res, (err) => {
      if (err) return res.status(400).json({ error: err.message || "Ошибка загрузки" });
      next();
    });
  },
  (req, res) => {
    const convId = Number(req.params.id);
    if (!assertConvMember(convId, req.user.sub)) return res.status(404).json({ error: "Чат не найден" });
    if (!req.file) return res.status(400).json({ error: "Нет файла" });

    const caption = String(req.body?.caption ?? "").trim().slice(0, 4000);
    const orig = safeFilename(req.file.originalname);
    const filename = req.file.filename;
    const mime = req.file.mimetype || "application/octet-stream";
    const size = req.file.size || 0;

    const info = db
      .prepare(
        `INSERT INTO messages (conversation_id, sender_id, body, kind, file_path, file_name, file_mime, file_size)
         VALUES (?, ?, ?, 'file', ?, ?, ?, ?)`
      )
      .run(convId, req.user.sub, caption, filename, orig, mime, size);

    const msg = selectFullMessage(info.lastInsertRowid);
    const payload = messageToPayload(msg, convId);
    io.to(`conv:${convId}`).emit("message", payload);
    pushNewMessage(convId, req.user.sub, payload).catch(() => {});
    res.status(201).json({ message: payload });
  }
);

app.get("/api/messages/:messageId/media", authMiddleware, (req, res) => {
  const messageId = Number(req.params.messageId);
  const row = db
    .prepare(
      `SELECT m.kind, m.voice_path, m.file_path, m.file_mime, m.file_name
       FROM messages m
       JOIN conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.user_id = ?
       WHERE m.id = ?`
    )
    .get(req.user.sub, messageId);
  if (!row) return res.status(404).json({ error: "Не найдено" });

  if (row.kind === "voice" && row.voice_path) {
    const fp = path.join(voiceDir, row.voice_path);
    if (!fs.existsSync(fp)) return res.status(404).json({ error: "Файл отсутствует" });
    res.setHeader("Content-Type", "audio/webm");
    return res.sendFile(fp);
  }

  if ((row.kind === "video_note" || row.kind === "file") && row.file_path) {
    const base = row.kind === "video_note" ? videoDir : fileDir;
    const fp = path.join(base, row.file_path);
    if (!fs.existsSync(fp)) return res.status(404).json({ error: "Файл отсутствует" });
    const mime = row.file_mime || "application/octet-stream";
    res.setHeader("Content-Type", mime);
    if (req.query.download === "1" && row.file_name) {
      res.setHeader(
        "Content-Disposition",
        `attachment; filename*=UTF-8''${encodeURIComponent(row.file_name)}`
      );
    }
    return res.sendFile(fp);
  }

  return res.status(404).json({ error: "Нет медиа" });
});

app.get("/api/messages/:messageId/voice", authMiddleware, (req, res) => {
  const messageId = Number(req.params.messageId);
  const row = db
    .prepare(
      `SELECT m.voice_path, m.kind FROM messages m
       JOIN conversation_members cm ON cm.conversation_id = m.conversation_id AND cm.user_id = ?
       WHERE m.id = ?`
    )
    .get(req.user.sub, messageId);
  if (!row || row.kind !== "voice" || !row.voice_path) {
    return res.status(404).json({ error: "Не найдено" });
  }
  const filePath = path.join(voiceDir, row.voice_path);
  if (!fs.existsSync(filePath)) return res.status(404).json({ error: "Файл отсутствует" });
  res.setHeader("Content-Type", "audio/webm");
  res.sendFile(filePath);
});

io.use((socket, next) => {
  try {
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error("auth"));
    const decoded = jwt.verify(token, JWT_SECRET);
    socket.userId = decoded.sub;
    next();
  } catch {
    next(new Error("auth"));
  }
});

io.on("connection", (socket) => {
  const uid = socket.userId;
  socket.join(`uid:${uid}`);
  onUserSocketConnect(uid);
  sendPresenceSnapshot(socket, uid);

  socket.on("join", (conversationId) => {
    const cid = Number(conversationId);
    if (!cid) return;
    const ok = assertConvMember(cid, uid);
    if (ok) {
      socket.join(`conv:${cid}`);
      const upToMessageId = markConversationRead(cid, uid);
      io.to(`conv:${cid}`).emit("read", { conversationId: cid, readerId: uid, upToMessageId });
    }
  });
  socket.on("leave", (conversationId) => {
    const cid = Number(conversationId);
    if (cid) socket.leave(`conv:${cid}`);
  });

  socket.on("disconnect", () => {
    onUserSocketDisconnect(uid);
  });
});

httpServer.listen(PORT, () => {
  console.log(`API + WS http://localhost:${PORT}`);
});
