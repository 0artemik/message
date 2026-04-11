import { useEffect, useState } from "react";
import { api } from "./api.js";
import { useAuth } from "./authContext.jsx";
import { useTheme } from "./themeContext.jsx";
import "./SettingsModal.css";

export default function SettingsModal({ open, onClose }) {
  const { theme, setTheme } = useTheme();
  const { user, logout } = useAuth();
  const [tab, setTab] = useState("general");
  const [oldPassword, setOldPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordBusy, setPasswordBusy] = useState(false);
  const [passwordError, setPasswordError] = useState("");
  const [passwordSuccess, setPasswordSuccess] = useState("");
  const [sessions, setSessions] = useState([]);
  const [sessionsBusy, setSessionsBusy] = useState(false);
  const [sessionsError, setSessionsError] = useState("");
  async function submitPassword(e) {
    e.preventDefault();
    setPasswordError("");
    setPasswordSuccess("");
    if (!oldPassword.trim()) {
      setPasswordError("Введите старый пароль");
      return;
    }
    if (newPassword.trim().length < 6) {
      setPasswordError("Новый пароль не короче 6 символов");
      return;
    }
    if (newPassword !== confirmPassword) {
      setPasswordError("Подтверждение не совпадает");
      return;
    }
    setPasswordBusy(true);
    try {
      await api("/auth/change-password", {
        method: "POST",
        body: { oldPassword, newPassword },
      });
      setOldPassword("");
      setNewPassword("");
      setConfirmPassword("");
      setPasswordSuccess("Пароль изменен. Выполните вход снова");
      setTimeout(() => {
        logout();
        onClose();
      }, 500);
    } catch (err) {
      setPasswordError(err.message || "Не удалось сменить пароль");
    } finally {
      setPasswordBusy(false);
    }
  }

  async function loadSessions() {
    setSessionsBusy(true);
    setSessionsError("");
    try {
      const data = await api("/auth/sessions");
      setSessions(data.sessions || []);
    } catch (err) {
      setSessionsError(err.message || "Не удалось загрузить сеансы");
    } finally {
      setSessionsBusy(false);
    }
  }

  async function revokeOtherSessions() {
    setSessionsBusy(true);
    setSessionsError("");
    try {
      await api("/auth/sessions/revoke-others", { method: "POST" });
      await loadSessions();
    } catch (err) {
      setSessionsError(err.message || "Не удалось завершить другие сеансы");
    } finally {
      setSessionsBusy(false);
    }
  }

  useEffect(() => {
    if (open && tab === "sessions") {
      loadSessions();
    }
  }, [open, tab]);

  function clientLabel(clientType) {
    if (String(clientType).toLowerCase() === "ios") return "iOS";
    if (String(clientType).toLowerCase() === "android") return "Android";
    return "Web";
  }

  if (!open) return null;

  return (
    <div className="settings-overlay" role="presentation" onClick={onClose}>
      <div
        className="settings-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="settings-title"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="settings-head">
          <h2 id="settings-title" className="settings-title">
            Настройки
          </h2>
          <button type="button" className="settings-close" onClick={onClose} aria-label="Закрыть">
            ×
          </button>
        </div>
        <div className="settings-body">
          <div className="settings-tabs">
            <button type="button" className={tab === "general" ? "active" : ""} onClick={() => setTab("general")}>
              Общие
            </button>
            <button type="button" className={tab === "password" ? "active" : ""} onClick={() => setTab("password")}>
              Пароль
            </button>
            <button type="button" className={tab === "sessions" ? "active" : ""} onClick={() => setTab("sessions")}>
              Сеансы
            </button>
          </div>

          {tab === "general" ? (
            <div className="settings-row">
              <div>
                <div className="settings-label">{user?.displayName || "Пользователь"}</div>
                <div className="settings-hint">@{user?.username || ""}</div>
              </div>
              <div>
                <div className="settings-label">Тема оформления</div>
                <div className="settings-hint">Как в Telegram: светлая или тёмная</div>
              </div>
              <div className="settings-segment">
                <button
                  type="button"
                  className={theme === "light" ? "active" : ""}
                  onClick={() => setTheme("light")}
                >
                  Светлая
                </button>
                <button
                  type="button"
                  className={theme === "dark" ? "active" : ""}
                  onClick={() => setTheme("dark")}
                >
                  Тёмная
                </button>
              </div>
            </div>
          ) : null}

          {tab === "password" ? (
            <form className="settings-form" onSubmit={submitPassword}>
              <label className="settings-label" htmlFor="oldPassword">
                Старый пароль
              </label>
              <input
                id="oldPassword"
                type="password"
                className="settings-input"
                value={oldPassword}
                onChange={(e) => setOldPassword(e.target.value)}
                autoComplete="current-password"
              />
              <label className="settings-label" htmlFor="newPassword">
                Новый пароль
              </label>
              <input
                id="newPassword"
                type="password"
                className="settings-input"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                autoComplete="new-password"
              />
              <label className="settings-label" htmlFor="confirmPassword">
                Подтвердите новый пароль
              </label>
              <input
                id="confirmPassword"
                type="password"
                className="settings-input"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                autoComplete="new-password"
              />

              {passwordError ? <div className="settings-error">{passwordError}</div> : null}
              {passwordSuccess ? <div className="settings-success">{passwordSuccess}</div> : null}

              <button type="submit" className="settings-primary-btn" disabled={passwordBusy}>
                {passwordBusy ? "Сохранение..." : "Сменить пароль"}
              </button>
            </form>
          ) : null}

          {tab === "sessions" ? (
            <div className="settings-row">
              <button type="button" className="settings-primary-btn" onClick={loadSessions} disabled={sessionsBusy}>
                {sessionsBusy ? "Обновление..." : "Обновить список"}
              </button>
              <button
                type="button"
                className="settings-primary-btn settings-danger-btn"
                onClick={revokeOtherSessions}
                disabled={sessionsBusy}
              >
                Завершить все кроме текущего
              </button>

              {sessionsError ? <div className="settings-error">{sessionsError}</div> : null}

              <div className="settings-sessions">
                {sessions.length === 0 ? (
                  <div className="settings-hint">Активных сеансов нет</div>
                ) : (
                  sessions.map((s) => (
                    <div className="settings-session-card" key={s.sid}>
                      <div className="settings-session-top">
                        <span className="settings-label">{clientLabel(s.clientType)}</span>
                        {s.current ? <span className="settings-current-pill">Текущий</span> : null}
                      </div>
                      <div className="settings-hint">{s.device}</div>
                      <div className="settings-hint">Вход: {s.createdAt}</div>
                    </div>
                  ))
                )}
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}
