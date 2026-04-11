import { useCallback, useEffect, useRef, useState } from "react";
import { io } from "socket.io-client";
import { Link } from "react-router-dom";
import { api, uploadFileAttachment, uploadVoice } from "../api.js";
import { useAuth } from "../authContext.jsx";
import { FileAttachmentMessage, VideoCircleMessage } from "../ChatMedia.jsx";
import { compressAttachmentForUpload } from "../mediaCompression.js";
import { formatPresenceLabel } from "../presenceUtils.js";
import SettingsModal from "../SettingsModal.jsx";
import VideoNoteModal from "../VideoNoteModal.jsx";
import VoiceMessage from "../VoiceMessage.jsx";
import VoiceWaveform from "../VoiceWaveform.jsx";
import "./Chat.css";

function initials(name) {
  const parts = String(name || "").trim().split(/\s+/);
  const a = parts[0]?.[0] || "?";
  const b = parts[1]?.[0] || "";
  return (a + b).toUpperCase();
}

function formatTime(iso) {
  if (!iso) return "";
  const d = new Date(String(iso).includes("T") ? iso : iso.replace(" ", "T"));
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" });
}

function formatRecordClock(totalSec) {
  const s = Math.max(0, totalSec);
  const m = Math.floor(s / 60);
  const r = s % 60;
  return `${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}`;
}

function previewLastMessage(lastMessage, myId) {
  if (!lastMessage) return "Нет сообщений";
  const prefix = lastMessage.senderId === myId ? "Вы: " : "";
  if (lastMessage.kind === "voice") return `${prefix}Голосовое сообщение`;
  if (lastMessage.kind === "video_note") return `${prefix}Видеосообщение`;
  if (lastMessage.kind === "file") return `${prefix}📎 ${lastMessage.fileName || "Файл"}`;
  return `${prefix}${lastMessage.body || ""}`;
}

export default function Chat() {
  const { user, logout, token } = useAuth();
  const [query, setQuery] = useState("");
  const [searchHits, setSearchHits] = useState([]);
  const [conversations, setConversations] = useState([]);
  const [activeId, setActiveId] = useState(null);
  const [activePeer, setActivePeer] = useState(null);
  const [messages, setMessages] = useState([]);
  const [hasMoreMessages, setHasMoreMessages] = useState(false);
  const [nextBeforeId, setNextBeforeId] = useState(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [draft, setDraft] = useState("");
  const [menuOpen, setMenuOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [videoOpen, setVideoOpen] = useState(false);
  const [presence, setPresence] = useState({});
  const [recording, setRecording] = useState(false);
  const [recordingStream, setRecordingStream] = useState(null);
  const [recordSecs, setRecordSecs] = useState(0);
  const [voiceError, setVoiceError] = useState("");
  const [attachBusy, setAttachBusy] = useState(false);
  const [uploadPreview, setUploadPreview] = useState(null);
  const messagesEnd = useRef(null);
  const socketRef = useRef(null);
  const joinedConvRef = useRef(null);
  const activeIdRef = useRef(null);
  const mediaRecorderRef = useRef(null);
  const mediaStreamRef = useRef(null);
  const voiceChunksRef = useRef([]);
  const recordStartRef = useRef(0);
  const fileInputRef = useRef(null);
  const messagesListRef = useRef(null);
  const pendingQueueRef = useRef([]);
  const sendingRef = useRef(false);
  const shouldStickToBottomRef = useRef(true);

  const scrollMessagesToBottom = useCallback((smooth = false) => {
    const el = messagesListRef.current;
    if (!el) return;
    if (smooth) {
      el.scrollTo({ top: el.scrollHeight, behavior: "smooth" });
      return;
    }
    el.scrollTop = el.scrollHeight;
  }, []);

  const upsertMessage = useCallback((prev, incoming) => {
    const incomingId = incoming?.id != null ? String(incoming.id) : null;
    const incomingClientMsgId = incoming?.clientMsgId ? String(incoming.clientMsgId) : null;
    const byClientIdx =
      incomingClientMsgId != null
        ? prev.findIndex(
            (m) =>
              m?.clientMsgId &&
              String(m.clientMsgId) === incomingClientMsgId &&
              Number(m.senderId) === Number(incoming.senderId)
          )
        : -1;
    if (byClientIdx >= 0) {
      const next = [...prev];
      next[byClientIdx] = { ...incoming, pending: false };
      return next.filter((m, i, arr) => {
        const id = m?.id != null ? String(m.id) : "";
        if (!id) return true;
        return arr.findIndex((x) => String(x?.id ?? "") === id) === i;
      });
    }
    if (incomingId && prev.some((m) => String(m?.id ?? "") === incomingId)) return prev;
    return [...prev, incoming];
  }, []);

  const mergePresenceBatch = useCallback((batch) => {
    setPresence((prev) => {
      const next = { ...prev };
      for (const [idStr, v] of Object.entries(batch || {})) {
        const id = Number(idStr);
        if (Number.isFinite(id)) next[id] = v;
      }
      return next;
    });
  }, []);

  const loadConversations = useCallback(async () => {
    const data = await api("/conversations");
    setConversations(data.conversations || []);
  }, []);

  useEffect(() => {
    loadConversations().catch(() => {});
  }, [loadConversations]);

  useEffect(() => {
    const ids = conversations.map((c) => c.peer?.id).filter(Boolean);
    if (ids.length === 0) return undefined;
    const key = [...new Set(ids)].sort((a, b) => a - b).join(",");
    let cancelled = false;
    api(`/presence/batch?ids=${encodeURIComponent(key)}`)
      .then((d) => {
        if (!cancelled) mergePresenceBatch(d.presence);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [conversations, mergePresenceBatch]);

  useEffect(() => {
    const ids = searchHits.map((u) => u.id).filter(Boolean);
    if (ids.length === 0) return undefined;
    const key = [...new Set(ids)].sort((a, b) => a - b).join(",");
    let cancelled = false;
    api(`/presence/batch?ids=${encodeURIComponent(key)}`)
      .then((d) => {
        if (!cancelled) mergePresenceBatch(d.presence);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [searchHits, mergePresenceBatch]);

  useEffect(() => {
    if (!token) return undefined;
    const socket = io({
      auth: { token },
      transports: ["websocket", "polling"],
    });
    socketRef.current = socket;
    socket.on("message", (payload) => {
      const k = payload.kind || "text";
      setConversations((prev) =>
        prev.map((c) =>
          c.id === payload.conversationId
            ? {
                ...c,
                lastMessage: {
                  body: k === "text" || k === "file" ? payload.body : "",
                  kind: k,
                  fileName: payload.fileName ?? null,
                  createdAt: payload.createdAt,
                  senderId: payload.senderId,
                },
              }
            : c
        )
      );
      setMessages((prev) => {
        if (Number(payload.conversationId) !== Number(activeIdRef.current)) return prev;
        if (payload.senderId !== user?.id) {
          markRead(payload.conversationId, payload.id).catch(() => {});
        }
        return upsertMessage(prev, payload);
      });
    });
    socket.on("read", ({ conversationId, readerId, upToMessageId }) => {
      if (Number(conversationId) !== Number(activeIdRef.current)) return;
      if (Number(readerId) === Number(user?.id)) return;
      setMessages((prev) =>
        prev.map((m) =>
          m.senderId === user?.id && Number(m.id) <= Number(upToMessageId) ? { ...m, isRead: true } : m
        )
      );
    });
    socket.on("presence", (p) => {
      if (!p?.userId) return;
      setPresence((prev) => ({
        ...prev,
        [p.userId]: { online: p.online, lastSeenAt: p.lastSeenAt },
      }));
    });
    return () => {
      socket.disconnect();
      socketRef.current = null;
    };
  }, [token, upsertMessage, user?.id]);

  useEffect(() => {
    const q = query.trim();
    if (q.length < 2) {
      setSearchHits([]);
      return undefined;
    }
    const t = setTimeout(() => {
      api(`/users/search?q=${encodeURIComponent(q)}`)
        .then((d) => setSearchHits(d.users || []))
        .catch(() => setSearchHits([]));
    }, 250);
    return () => clearTimeout(t);
  }, [query]);

  useEffect(() => {
    activeIdRef.current = activeId;
  }, [activeId]);

  useEffect(() => {
    if (shouldStickToBottomRef.current) {
      scrollMessagesToBottom(false);
    }
  }, [messages, activeId, scrollMessagesToBottom]);

  useEffect(() => {
    if (!recording) {
      setRecordSecs(0);
      return undefined;
    }
    const id = setInterval(() => {
      setRecordSecs(Math.floor((Date.now() - recordStartRef.current) / 1000));
    }, 200);
    return () => clearInterval(id);
  }, [recording]);

  useEffect(() => {
    if (!menuOpen && !settingsOpen) return undefined;
    function onKey(e) {
      if (e.key === "Escape") {
        setMenuOpen(false);
        setSettingsOpen(false);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [menuOpen, settingsOpen]);

  useEffect(() => {
    if (!menuOpen) return undefined;
    function onDoc() {
      setMenuOpen(false);
    }
    const t = setTimeout(() => document.addEventListener("click", onDoc), 0);
    return () => {
      clearTimeout(t);
      document.removeEventListener("click", onDoc);
    };
  }, [menuOpen]);

  async function openWithUser(peer) {
    setQuery("");
    setSearchHits([]);
    const data = await api("/conversations/direct", {
      method: "POST",
      body: { userId: peer.id },
    });
    const conv = data.conversation;
    setActiveId(conv.id);
    setActivePeer(conv.peer);
    await loadConversations();
    try {
      const pr = await api(`/presence/batch?ids=${encodeURIComponent(String(peer.id))}`);
      mergePresenceBatch(pr.presence);
    } catch {
      /* ignore */
    }
    const msgData = await api(`/conversations/${conv.id}/messages?limit=50`);
    setMessages(msgData.messages || []);
    setHasMoreMessages(Boolean(msgData.hasMore));
    setNextBeforeId(msgData.nextBeforeId ?? null);
    shouldStickToBottomRef.current = true;
    requestAnimationFrame(() => scrollMessagesToBottom(false));
    await markRead(conv.id, msgData.messages?.at(-1)?.id);
    const s = socketRef.current;
    if (s) {
      if (joinedConvRef.current) s.emit("leave", joinedConvRef.current);
      joinedConvRef.current = conv.id;
      s.emit("join", conv.id);
    }
  }

  async function selectConversation(c) {
    setActiveId(c.id);
    setActivePeer(c.peer);
    const msgData = await api(`/conversations/${c.id}/messages?limit=50`);
    setMessages(msgData.messages || []);
    setHasMoreMessages(Boolean(msgData.hasMore));
    setNextBeforeId(msgData.nextBeforeId ?? null);
    shouldStickToBottomRef.current = true;
    requestAnimationFrame(() => scrollMessagesToBottom(false));
    await markRead(c.id, msgData.messages?.at(-1)?.id);
    const s = socketRef.current;
    if (s) {
      if (joinedConvRef.current) s.emit("leave", joinedConvRef.current);
      joinedConvRef.current = c.id;
      s.emit("join", c.id);
    }
  }

  async function markRead(conversationId, upToMessageId) {
    if (!conversationId || !upToMessageId) return;
    await api(`/conversations/${conversationId}/read`, {
      method: "POST",
      body: { upToMessageId },
    });
    await loadConversations();
  }

  async function flushPendingQueue() {
    if (sendingRef.current) return;
    if (pendingQueueRef.current.length === 0) return;
    if (!navigator.onLine) return;
    const now = Date.now();
    const idx = pendingQueueRef.current.findIndex((q) => q.nextTryAt <= now);
    if (idx < 0) return;
    const item = pendingQueueRef.current[idx];
    sendingRef.current = true;
    try {
      const data = await api(`/conversations/${item.conversationId}/messages`, {
        method: "POST",
        body: { body: item.text, clientMsgId: item.clientMsgId },
      });
      const msg = data.message;
      pendingQueueRef.current = pendingQueueRef.current.filter((x) => x.clientMsgId !== item.clientMsgId);
      setMessages((prev) => upsertMessage(prev, msg));
      await loadConversations();
    } catch {
      item.attempts += 1;
      item.nextTryAt = Date.now() + Math.min(30_000, 1000 * 2 ** Math.min(item.attempts, 5));
      pendingQueueRef.current[idx] = item;
    } finally {
      sendingRef.current = false;
    }
  }

  async function sendMessage() {
    const text = draft.trim();
    if (!text || !activeId) return;
    setDraft("");
    const clientMsgId = `c-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const local = {
      id: `local-${clientMsgId}`,
      senderId: user?.id,
      body: text,
      kind: "text",
      createdAt: new Date().toISOString(),
      pending: true,
      isRead: false,
      clientMsgId,
    };
    setMessages((prev) => [...prev, local]);
    shouldStickToBottomRef.current = true;
    pendingQueueRef.current.push({
      conversationId: activeId,
      text,
      clientMsgId,
      attempts: 0,
      nextTryAt: Date.now(),
    });
    flushPendingQueue().catch(() => {});
  }

  function onKeyDown(e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  }

  function stopMedia() {
    const rec = mediaRecorderRef.current;
    mediaRecorderRef.current = null;
    const stream = mediaStreamRef.current;
    mediaStreamRef.current = null;
    stream?.getTracks().forEach((t) => t.stop());
    setRecordingStream(null);
    if (rec && rec.state !== "inactive") {
      try {
        rec.stop();
      } catch {
        /* ignore */
      }
    }
  }

  async function startRecording() {
    if (!activeId || recording) return;
    setVoiceError("");
    if (!navigator.mediaDevices?.getUserMedia) {
      setVoiceError("Запись недоступна в этом браузере");
      return;
    }
    let mimeType = "";
    if (typeof MediaRecorder !== "undefined") {
      if (MediaRecorder.isTypeSupported("audio/webm")) mimeType = "audio/webm";
      else if (MediaRecorder.isTypeSupported("audio/webm;codecs=opus")) mimeType = "audio/webm;codecs=opus";
    }
    if (!mimeType) {
      setVoiceError("Нужен формат WebM (Chrome, Firefox, Edge)");
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      mediaStreamRef.current = stream;
      setRecordingStream(stream);
      voiceChunksRef.current = [];
      const rec = new MediaRecorder(stream, { mimeType });
      mediaRecorderRef.current = rec;
      rec.ondataavailable = (ev) => {
        if (ev.data?.size) voiceChunksRef.current.push(ev.data);
      };
      recordStartRef.current = Date.now();
      setRecordSecs(0);
      rec.start(200);
      setRecording(true);
    } catch {
      setVoiceError("Нет доступа к микрофону");
      stopMedia();
      setRecording(false);
    }
  }

  async function finishRecording(send) {
    const rec = mediaRecorderRef.current;
    if (!rec) {
      stopMedia();
      setRecording(false);
      return;
    }
    const started = recordStartRef.current;
    const chunks = voiceChunksRef.current;
    await new Promise((resolve) => {
      rec.onstop = resolve;
      try {
        rec.requestData?.();
      } catch {
        /* ignore */
      }
      rec.stop();
    });
    mediaRecorderRef.current = null;
    mediaStreamRef.current?.getTracks().forEach((t) => t.stop());
    mediaStreamRef.current = null;
    setRecordingStream(null);
    setRecording(false);
    if (!send || !activeId) return;
    const durationMs = Date.now() - started;
    const blob = new Blob(chunks, { type: "audio/webm" });
    if (blob.size < 64) {
      setVoiceError("Слишком короткая запись");
      return;
    }
    try {
      const data = await uploadVoice(activeId, blob, durationMs);
      const msg = data.message;
      setMessages((prev) => (prev.some((m) => m.id === msg.id) ? prev : [...prev, msg]));
      await loadConversations();
    } catch (e) {
      setVoiceError(e.message || "Не удалось отправить");
    }
  }

  async function onPickFile(e) {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (f) await handleAttachmentUpload(f);
  }

  async function handleAttachmentUpload(file) {
    const f = file;
    if (!f || !activeId) return;
    setAttachBusy(true);
    setVoiceError("");
    try {
      const cap = draft.trim();
      if (uploadPreview?.url) URL.revokeObjectURL(uploadPreview.url);
      const compressed = await compressAttachmentForUpload(f);
      const fileToUpload = compressed.file || f;
      const previewUrl =
        fileToUpload.type.startsWith("image/") || fileToUpload.type.startsWith("video/")
          ? URL.createObjectURL(fileToUpload)
          : null;
      setUploadPreview({
        url: previewUrl,
        name: fileToUpload.name,
        type: fileToUpload.type,
        progress: 0,
        compressed: compressed.compressed,
      });
      const data = await uploadFileAttachment(activeId, fileToUpload, cap, (p) => {
        setUploadPreview((prev) => (prev ? { ...prev, progress: p } : prev));
      });
      if (cap) setDraft("");
      const msg = data.message;
      setMessages((prev) => (prev.some((m) => m.id === msg.id) ? prev : [...prev, msg]));
      await loadConversations();
      setUploadPreview((prev) => {
        if (prev?.url) URL.revokeObjectURL(prev.url);
        return null;
      });
    } catch (err) {
      setVoiceError(err.message || "Не удалось отправить файл");
      setUploadPreview((prev) => {
        if (prev?.url) URL.revokeObjectURL(prev.url);
        return null;
      });
    } finally {
      setAttachBusy(false);
    }
  }

  async function onComposePaste(e) {
    const items = Array.from(e.clipboardData?.items || []);
    const mediaItem = items.find((it) => it.kind === "file" && String(it.type || "").startsWith("image/"));
    if (!mediaItem) return;
    const file = mediaItem.getAsFile();
    if (!file) return;
    e.preventDefault();
    await handleAttachmentUpload(file);
  }

  useEffect(() => {
    return () => {
      stopMedia();
      if (uploadPreview?.url) URL.revokeObjectURL(uploadPreview.url);
    };
  }, [uploadPreview]);

  useEffect(() => {
    const t = setInterval(() => {
      flushPendingQueue().catch(() => {});
    }, 1200);
    function onOnline() {
      flushPendingQueue().catch(() => {});
    }
    window.addEventListener("online", onOnline);
    return () => {
      clearInterval(t);
      window.removeEventListener("online", onOnline);
    };
  }, []);

  const peerStatus = activePeer?.id != null ? presence[activePeer.id] : null;
  const statusLine = activePeer
    ? formatPresenceLabel({
        online: peerStatus?.online,
        lastSeenAt: peerStatus?.lastSeenAt,
      })
    : "";

  function renderMessageBody(m) {
    if (m.kind === "voice") {
      return <VoiceMessage messageId={m.id} durationMs={m.voiceDurationMs} />;
    }
    if (m.kind === "video_note") {
      return <VideoCircleMessage messageId={m.id} />;
    }
    if (m.kind === "file") {
      return (
        <FileAttachmentMessage
          messageId={m.id}
          fileName={m.fileName}
          fileMime={m.fileMime}
          fileSize={m.fileSize}
          caption={m.body}
        />
      );
    }
    return m.body;
  }

  function statusMark(m) {
    if (m.senderId !== user?.id) return "";
    if (m.pending) return "🕓";
    return m.isRead ? "✓✓" : "✓";
  }

  async function loadMoreMessages() {
    if (!activeId || !hasMoreMessages || !nextBeforeId || loadingMore) return;
    setLoadingMore(true);
    try {
      shouldStickToBottomRef.current = false;
      const d = await api(`/conversations/${activeId}/messages?limit=50&beforeId=${nextBeforeId}`);
      setMessages((prev) => [...(d.messages || []), ...prev]);
      setHasMoreMessages(Boolean(d.hasMore));
      setNextBeforeId(d.nextBeforeId ?? null);
    } finally {
      setLoadingMore(false);
    }
  }

  return (
    <div className="chat-shell">
      <SettingsModal open={settingsOpen} onClose={() => setSettingsOpen(false)} />
      <VideoNoteModal
        open={videoOpen}
        conversationId={activeId}
        onClose={() => setVideoOpen(false)}
        onSent={async () => {
          await loadConversations();
          const cid = activeIdRef.current;
          if (cid) {
            try {
              const d = await api(`/conversations/${cid}/messages`);
              setMessages(d.messages || []);
            } catch {
              /* ignore */
            }
          }
        }}
      />
      <aside className="chat-sidebar">
        <header className="chat-sidebar-header">
          <button
            type="button"
            className="chat-menu-btn"
            aria-label="Меню"
            onClick={(e) => {
              e.stopPropagation();
              setMenuOpen((v) => !v);
            }}
          >
            ☰
          </button>
          <span className="chat-sidebar-title">Чаты</span>
          {menuOpen ? (
            <div className="chat-menu-popover" onClick={(e) => e.stopPropagation()}>
              <div className="chat-menu-panel">
                <div style={{ padding: "8px 12px", fontSize: 14, fontWeight: 500 }}>{user?.displayName}</div>
                <div
                  style={{
                    padding: "0 12px 8px",
                    fontSize: 12,
                    color: "var(--tg-text-secondary)",
                  }}
                >
                  @{user?.username}
                </div>
                <button
                  type="button"
                  className="chat-menu-item"
                  onClick={() => {
                    setMenuOpen(false);
                    setSettingsOpen(true);
                  }}
                >
                  Настройки
                </button>
                <div className="chat-menu-divider" />
                <button
                  type="button"
                  className="chat-menu-item"
                  onClick={() => {
                    setMenuOpen(false);
                    logout();
                  }}
                >
                  Выйти
                </button>
              </div>
            </div>
          ) : null}
          <span className="chat-user-chip" title={user?.username}>
            {user?.displayName}
          </span>
        </header>
        <div className="chat-search-wrap">
          <div className="chat-search-row">
            <span className="chat-search-icon">🔍</span>
            <input
              className="chat-search"
              placeholder="Поиск пользователей…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </div>
        </div>
        {query.trim().length >= 2 ? (
          <div className="search-results">
            <div className="search-results-title">Люди</div>
            {searchHits.length === 0 ? (
              <div className="search-empty">Никого не нашли</div>
            ) : (
              searchHits.map((u) => {
                const pr = presence[u.id];
                return (
                  <button
                    key={u.id}
                    type="button"
                    className="chat-list-item"
                    onClick={() => openWithUser(u)}
                  >
                    <div style={{ position: "relative" }}>
                      <div className="chat-avatar">{initials(u.displayName)}</div>
                      {pr?.online ? (
                        <span
                          className="chat-online-dot"
                          style={{ position: "absolute", bottom: 2, right: 2, width: 12, height: 12 }}
                        />
                      ) : null}
                    </div>
                    <div className="chat-list-meta">
                      <div className="chat-list-name-row">
                        <span className="chat-list-name">{u.displayName}</span>
                      </div>
                      <div className="chat-list-preview">
                        @{u.username}
                        {pr && !pr.online && pr.lastSeenAt
                          ? ` · ${formatPresenceLabel(pr)}`
                          : pr?.online
                            ? " · в сети"
                            : ""}
                      </div>
                    </div>
                  </button>
                );
              })
            )}
          </div>
        ) : null}
        <div className="chat-list">
          {conversations.map((c) => {
            const pr = presence[c.peer?.id];
            return (
              <button
                key={c.id}
                type="button"
                className={`chat-list-item${c.id === activeId ? " active" : ""}`}
                onClick={() => selectConversation(c)}
              >
                <div style={{ position: "relative" }}>
                  <div className="chat-avatar">{initials(c.peer?.displayName)}</div>
                  {pr?.online ? (
                    <span
                      className="chat-online-dot"
                      style={{ position: "absolute", bottom: 2, right: 2, width: 12, height: 12 }}
                    />
                  ) : null}
                </div>
                <div className="chat-list-meta">
                  <div className="chat-list-name-row">
                    <span className="chat-list-name">{c.peer?.displayName}</span>
                    {c.unreadCount > 0 ? <span className="chat-unread-badge">{c.unreadCount}</span> : null}
                  </div>
                  <div className="chat-list-preview">{previewLastMessage(c.lastMessage, user?.id)}</div>
                </div>
              </button>
            );
          })}
        </div>
      </aside>
      <main className="chat-main">
        {!activeId ? (
          <div className="chat-main-empty">
            <div className="chat-main-empty-icon">💬</div>
            <h2>Выберите чат</h2>
            <p>Или найдите пользователя в поиске слева и начните диалог.</p>
            <p style={{ marginTop: 16, fontSize: 14 }}>
              <Link to="/login">Сменить аккаунт</Link>
            </p>
          </div>
        ) : (
          <>
            <header className="chat-main-header">
              <div className="chat-avatar" style={{ width: 40, height: 40, fontSize: 15 }}>
                {initials(activePeer?.displayName)}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="chat-main-header-name">{activePeer?.displayName}</div>
                <div className="chat-main-header-sub chat-peer-row">
                  {peerStatus?.online ? (
                    <>
                      <span className="chat-online-dot" style={{ width: 8, height: 8 }} />
                      <span>{statusLine}</span>
                    </>
                  ) : (
                    <span>{statusLine}</span>
                  )}
                </div>
              </div>
            </header>
            <div
              className="chat-messages"
              ref={messagesListRef}
              onScroll={(e) => {
                const el = e.currentTarget;
                const delta = el.scrollHeight - el.scrollTop - el.clientHeight;
                shouldStickToBottomRef.current = delta < 48;
              }}
            >
              {hasMoreMessages ? (
                <div style={{ textAlign: "center", padding: 8 }}>
                  <button type="button" className="chat-load-more" onClick={loadMoreMessages} disabled={loadingMore}>
                    {loadingMore ? "Загрузка..." : "Загрузить старые"}
                  </button>
                </div>
              ) : null}
              {messages.map((m) => {
                const out = m.senderId === user?.id;
                const isImageFile = m.kind === "file" && String(m.fileMime || "").startsWith("image/");
                const isVoice = m.kind === "voice";
                return (
                  <div key={m.id} className={`chat-bubble-row${out ? " out" : ""}`}>
                    <div
                      className={`chat-bubble${out ? " out" : " in"}${m.kind !== "text" ? " bubble-media" : ""}${isImageFile ? " media-image" : ""}${isVoice ? " media-voice" : ""}`}
                    >
                      {renderMessageBody(m)}
                      {!isVoice ? (
                        <span className="chat-bubble-time">
                          {formatTime(m.createdAt)} {statusMark(m)}
                        </span>
                      ) : null}
                      {isVoice ? <span className="chat-bubble-time voice-time">{formatTime(m.createdAt)}</span> : null}
                    </div>
                  </div>
                );
              })}
              <div ref={messagesEnd} />
            </div>
            {recording ? (
              <div className="voice-record-strip">
                <div className="voice-record-strip-inner">
                  <span className="voice-record-pulse" aria-hidden />
                  <VoiceWaveform stream={recordingStream} />
                  <span className="voice-record-timer">{formatRecordClock(recordSecs)}</span>
                  <span className="voice-record-label">Запись…</span>
                </div>
                <div className="voice-record-actions">
                  <button
                    type="button"
                    className="chat-mic recording"
                    title="Отправить голосовое"
                    aria-label="Отправить голосовое"
                    onClick={() => finishRecording(true)}
                  >
                    ●
                  </button>
                  <button type="button" className="voice-record-cancel" onClick={() => finishRecording(false)}>
                    Отмена
                  </button>
                </div>
              </div>
            ) : null}
            {uploadPreview ? (
              <div className="upload-preview-strip">
                {uploadPreview.url && uploadPreview.type.startsWith("image/") ? (
                  <img className="upload-preview-thumb" src={uploadPreview.url} alt={uploadPreview.name} />
                ) : uploadPreview.url && uploadPreview.type.startsWith("video/") ? (
                  <video className="upload-preview-thumb" src={uploadPreview.url} muted />
                ) : (
                  <div className="upload-preview-file">📎</div>
                )}
                <div className="upload-preview-meta">
                  <div className="upload-preview-name">{uploadPreview.name}</div>
                  <div className="upload-progress-row">
                    <div className="upload-progress-bar">
                      <div className="upload-progress-value" style={{ width: `${uploadPreview.progress || 0}%` }} />
                    </div>
                    <span>{uploadPreview.progress || 0}%</span>
                  </div>
                  {uploadPreview.compressed ? <div className="upload-compressed-note">Сжато перед отправкой</div> : null}
                </div>
              </div>
            ) : null}
            <div className="chat-compose">
              <input
                ref={fileInputRef}
                type="file"
                className="chat-file-input"
                onChange={onPickFile}
              />
              <button
                type="button"
                className="chat-attach"
                title="Вложение"
                aria-label="Прикрепить файл"
                disabled={!activeId || attachBusy || recording}
                onClick={() => fileInputRef.current?.click()}
              >
                📎
              </button>
              <button
                type="button"
                className="chat-attach"
                title="Видеосообщение"
                aria-label="Видеосообщение"
                disabled={!activeId || attachBusy || recording}
                onClick={() => setVideoOpen(true)}
              >
                ⏺
              </button>
              <textarea
                className="chat-compose-input"
                rows={1}
                placeholder="Сообщение…"
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={onKeyDown}
                onPaste={(e) => {
                  onComposePaste(e).catch(() => {});
                }}
                disabled={recording}
              />
              {!recording ? (
                <button
                  type="button"
                  className="chat-mic"
                  title="Голосовое сообщение"
                  aria-label="Записать голосовое"
                  disabled={!activeId || attachBusy}
                  onClick={() => startRecording()}
                >
                  🎤
                </button>
              ) : null}
              <button
                type="button"
                className="chat-send"
                disabled={!draft.trim() || recording || attachBusy}
                onClick={sendMessage}
                aria-label="Отправить"
              >
                ➤
              </button>
            </div>
            {voiceError ? (
              <div
                style={{
                  padding: "0 16px 10px",
                  fontSize: 13,
                  color: "#c62828",
                  background: "var(--tg-header)",
                }}
              >
                {voiceError}
              </div>
            ) : null}
          </>
        )}
      </main>
    </div>
  );
}
