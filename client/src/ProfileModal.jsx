import { useEffect, useRef, useState } from "react";
import { updateProfile, uploadAvatar } from "./api.js";
import { useAuth } from "./authContext.jsx";
import UserAvatar from "./UserAvatar.jsx";
import "./ProfileModal.css";

export default function ProfileModal({
  open,
  profile,
  editable = false,
  statusText = "",
  onClose,
  onUpdated,
  onOpenSettings,
}) {
  const { updateUser } = useAuth();
  const fileInputRef = useRef(null);
  const [editing, setEditing] = useState(false);
  const [displayName, setDisplayName] = useState(profile?.displayName || "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [avatarBusy, setAvatarBusy] = useState(false);

  useEffect(() => {
    setEditing(false);
    setDisplayName(profile?.displayName || "");
    setBusy(false);
    setAvatarBusy(false);
    setError("");
  }, [profile, open]);

  if (!open || !profile) return null;

  async function submit(e) {
    e.preventDefault();
    const nextDisplayName = displayName.trim();
    if (!nextDisplayName) {
      setError("Имя не должно быть пустым");
      return;
    }
    setBusy(true);
    setError("");
    try {
      const data = await updateProfile(nextDisplayName);
      updateUser(data.user);
      onUpdated?.(data.user);
      setEditing(false);
    } catch (err) {
      setError(err.message || "Не удалось обновить имя");
    } finally {
      setBusy(false);
    }
  }

  async function onAvatarChange(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setAvatarBusy(true);
    setError("");
    try {
      const data = await uploadAvatar(file);
      updateUser(data.user);
      onUpdated?.(data.user);
    } catch (err) {
      setError(err.message || "Не удалось обновить фото");
    } finally {
      setAvatarBusy(false);
      e.target.value = "";
    }
  }

  function openAvatarPicker() {
    if (avatarBusy) return;
    fileInputRef.current?.click();
  }

  return (
    <div className="profile-overlay" role="presentation" onClick={onClose}>
      <div
        className="profile-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="profile-title"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="profile-head">
          <button type="button" className="profile-close" onClick={onClose} aria-label="Закрыть">
            ←
          </button>
          <div id="profile-title" className="profile-head-title">
            Профиль
          </div>
        </div>

        <div className="profile-body">
          <div className="profile-hero">
            <UserAvatar user={profile} className="profile-avatar" imgClassName="profile-avatar profile-avatar-image" />
            <div className="profile-name">{profile.displayName}</div>
            <div className="profile-username">@{profile.username}</div>
            {statusText ? <div className="profile-status">{statusText}</div> : null}
            {editable ? (
              <>
                <button
                  type="button"
                  className={`profile-upload-btn${avatarBusy ? " disabled" : ""}`}
                  onClick={openAvatarPicker}
                  disabled={avatarBusy}
                >
                {avatarBusy ? "Загрузка фото..." : "Изменить фото"}
                </button>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/*"
                  onChange={onAvatarChange}
                  disabled={avatarBusy}
                  style={{ display: "none" }}
                />
              </>
            ) : null}
            {error ? <div className="profile-error">{error}</div> : null}
          </div>

          {editable ? (
            <div className="profile-card">
              {!editing ? (
                <>
                  <div className="profile-info-row">
                    <div>
                      <div className="profile-info-label">Имя</div>
                      <div className="profile-info-value">{profile.displayName}</div>
                    </div>
                    <button type="button" className="profile-action-btn" onClick={() => setEditing(true)}>
                      Изменить имя
                    </button>
                  </div>
                  <div className="profile-info-row">
                    <div>
                      <div className="profile-info-label">Логин</div>
                      <div className="profile-info-value muted">@{profile.username}</div>
                    </div>
                  </div>
                  {onOpenSettings ? (
                    <button type="button" className="profile-secondary-btn" onClick={onOpenSettings}>
                      Открыть настройки
                    </button>
                  ) : null}
                </>
              ) : (
                <form className="profile-form" onSubmit={submit}>
                  <label className="profile-info-label" htmlFor="profileDisplayName">
                    Имя
                  </label>
                  <input
                    id="profileDisplayName"
                    className="profile-input"
                    value={displayName}
                    onChange={(e) => setDisplayName(e.target.value)}
                    maxLength={80}
                    autoFocus
                  />
                  <div className="profile-actions">
                    <button type="submit" className="profile-primary-btn" disabled={busy}>
                      {busy ? "Сохранение..." : "Сохранить"}
                    </button>
                    <button
                      type="button"
                      className="profile-secondary-btn"
                      onClick={() => {
                        setEditing(false);
                        setDisplayName(profile.displayName || "");
                        setError("");
                      }}
                    >
                      Отмена
                    </button>
                  </div>
                </form>
              )}
            </div>
          ) : (
            <div className="profile-card">
              <div className="profile-info-row compact">
                <div className="profile-info-label">Имя</div>
                <div className="profile-info-value">{profile.displayName}</div>
              </div>
              <div className="profile-info-row compact">
                <div className="profile-info-label">Логин</div>
                <div className="profile-info-value muted">@{profile.username}</div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
