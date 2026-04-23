import Database from "better-sqlite3";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dbPath = path.join(__dirname, "data.sqlite");

export const db = new Database(dbPath);

db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE COLLATE NOCASE,
    email TEXT NOT NULL UNIQUE COLLATE NOCASE,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    avatar_path TEXT,
    last_seen_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS conversation_members (
    conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_read_message_id INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (conversation_id, user_id)
  );

  CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL DEFAULT '',
    kind TEXT NOT NULL DEFAULT 'text',
    voice_path TEXT,
    voice_duration_ms INTEGER,
    file_path TEXT,
    file_name TEXT,
    file_mime TEXT,
    file_size INTEGER,
    video_duration_ms INTEGER,
    client_msg_id TEXT,
    reply_to_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
    forward_from_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
    forward_from_sender_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    edited_at TEXT,
    deleted_for_self TEXT,
    deleted_for_all TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, id);

  CREATE TABLE IF NOT EXISTS auth_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sid TEXT NOT NULL UNIQUE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_type TEXT NOT NULL DEFAULT 'web',
    device TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL,
    revoked_at TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_auth_sessions_user ON auth_sessions(user_id, created_at DESC);

  CREATE TABLE IF NOT EXISTS push_devices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    token TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(platform, token)
  );
  CREATE INDEX IF NOT EXISTS idx_push_devices_user ON push_devices(user_id, platform);
`);

function migrate() {
  const ucols = db.prepare("PRAGMA table_info(users)").all().map((c) => c.name);
  if (!ucols.includes("last_seen_at")) {
    try {
      db.exec("ALTER TABLE users ADD COLUMN last_seen_at TEXT");
    } catch {
      /* ignore */
    }
  }
  if (!ucols.includes("avatar_path")) {
    try {
      db.exec("ALTER TABLE users ADD COLUMN avatar_path TEXT");
    } catch {
      /* ignore */
    }
  }
  const msgMigrations = [
    ["kind", "ALTER TABLE messages ADD COLUMN kind TEXT DEFAULT 'text'"],
    ["voice_path", "ALTER TABLE messages ADD COLUMN voice_path TEXT"],
    ["voice_duration_ms", "ALTER TABLE messages ADD COLUMN voice_duration_ms INTEGER"],
    ["file_path", "ALTER TABLE messages ADD COLUMN file_path TEXT"],
    ["file_name", "ALTER TABLE messages ADD COLUMN file_name TEXT"],
    ["file_mime", "ALTER TABLE messages ADD COLUMN file_mime TEXT"],
    ["file_size", "ALTER TABLE messages ADD COLUMN file_size INTEGER"],
    ["video_duration_ms", "ALTER TABLE messages ADD COLUMN video_duration_ms INTEGER"],
    ["client_msg_id", "ALTER TABLE messages ADD COLUMN client_msg_id TEXT"],
    ["reply_to_message_id", "ALTER TABLE messages ADD COLUMN reply_to_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL"],
    ["forward_from_message_id", "ALTER TABLE messages ADD COLUMN forward_from_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL"],
    ["forward_from_sender_id", "ALTER TABLE messages ADD COLUMN forward_from_sender_id INTEGER REFERENCES users(id) ON DELETE SET NULL"],
    ["edited_at", "ALTER TABLE messages ADD COLUMN edited_at TEXT"],
    ["deleted_for_self", "ALTER TABLE messages ADD COLUMN deleted_for_self TEXT"],
    ["deleted_for_all", "ALTER TABLE messages ADD COLUMN deleted_for_all TEXT"],
  ];
  for (const [col, sql] of msgMigrations) {
    const mcols = db.prepare("PRAGMA table_info(messages)").all().map((c) => c.name);
    if (!mcols.includes(col)) {
      try {
        db.exec(sql);
      } catch {
        /* ignore */
      }
    }
  }

  const cmCols = db.prepare("PRAGMA table_info(conversation_members)").all().map((c) => c.name);
  if (!cmCols.includes("last_read_message_id")) {
    try {
      db.exec("ALTER TABLE conversation_members ADD COLUMN last_read_message_id INTEGER NOT NULL DEFAULT 0");
    } catch {
      /* ignore */
    }
  }

  try {
    db.exec(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_client_msg ON messages (conversation_id, sender_id, client_msg_id) WHERE client_msg_id IS NOT NULL"
    );
  } catch {
    /* ignore */
  }

  db.exec(`
    CREATE TABLE IF NOT EXISTS auth_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sid TEXT NOT NULL UNIQUE,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      client_type TEXT NOT NULL DEFAULT 'web',
      device TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT NOT NULL,
      revoked_at TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_auth_sessions_user ON auth_sessions(user_id, created_at DESC);
    CREATE TABLE IF NOT EXISTS push_devices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      platform TEXT NOT NULL,
      token TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(platform, token)
    );
    CREATE INDEX IF NOT EXISTS idx_push_devices_user ON push_devices(user_id, platform);
  `);
}

migrate();
