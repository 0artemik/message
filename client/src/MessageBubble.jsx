import { useState, useRef } from "react";

export default function MessageBubble({
  message,
  isOwn,
  onEdit,
  onDelete,
  onReply,
  onForward,
  children,
  time,
  statusMark,
}) {
  const [showMenu, setShowMenu] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [editText, setEditText] = useState(message.body || "");
  const menuRef = useRef(null);

  const canEdit = isOwn && message.kind === "text" && !message.deletedForSelf && !message.deletedForAll;
  const canDelete = isOwn && !message.deletedForSelf && !message.deletedForAll;

  const handleEdit = () => {
    setIsEditing(true);
    setShowMenu(false);
  };

  const handleSaveEdit = () => {
    if (editText.trim() && editText !== message.body) {
      onEdit(message.id, editText.trim());
    }
    setIsEditing(false);
  };

  const handleCancelEdit = () => {
    setEditText(message.body || "");
    setIsEditing(false);
  };

  const handleDelete = (deleteForAll = false) => {
    onDelete(message.id, deleteForAll);
    setShowMenu(false);
  };

  const handleReply = () => {
    onReply?.(message);
    setShowMenu(false);
  };

  const handleForward = () => {
    onForward?.(message);
    setShowMenu(false);
  };

  const handleKeyDown = (e) => {
    if (e.key === "Escape") {
      handleCancelEdit();
    } else if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSaveEdit();
    }
  };

  return (
    <div className={`chat-bubble-row${isOwn ? " out" : ""}`}>
      <div
        className={`chat-bubble${isOwn ? " out" : " in"}${message.kind !== "text" ? " bubble-media" : ""}`}
        ref={menuRef}
      >
        {isEditing ? (
          <div className="message-edit-container">
            <textarea
              className="message-edit-input"
              value={editText}
              onChange={(e) => setEditText(e.target.value)}
              onKeyDown={handleKeyDown}
              autoFocus
              rows={1}
            />
            <div className="message-edit-actions">
              <button
                type="button"
                className="message-edit-button save"
                onClick={handleSaveEdit}
                disabled={!editText.trim()}
              >
                Сохранить
              </button>
              <button
                type="button"
                className="message-edit-button cancel"
                onClick={handleCancelEdit}
              >
                Отмена
              </button>
            </div>
          </div>
        ) : (
          <>
            {message.forwardFrom ? (
              <div className="message-forward-badge">
                Переслано от {message.forwardFrom.senderName}
              </div>
            ) : null}
            {message.replyTo ? (
              <div className="message-reference-block">
                <div className="message-reference-name">{message.replyTo.senderName}</div>
                <div className="message-reference-text">{message.replyTo.body || "Сообщение"}</div>
              </div>
            ) : null}
            <div className="message-content">
              {children}
              {message.editedAt && <span className="edited-indicator">(изменено)</span>}
            </div>
            {time && (
              <span className="chat-bubble-time">
                {time} {statusMark}
              </span>
            )}
            {(canEdit || canDelete) && (
              <button
                type="button"
                className="message-menu-button"
                onClick={() => setShowMenu(!showMenu)}
                aria-label="Message options"
              >
                ···
              </button>
            )}
            {showMenu && (
              <div className="message-menu">
                {canEdit && (
                  <button
                    type="button"
                    className="message-menu-item"
                    onClick={handleEdit}
                  >
                    Изменить
                  </button>
                )}
                <button
                  type="button"
                  className="message-menu-item"
                  onClick={handleReply}
                >
                  Ответить
                </button>
                <button
                  type="button"
                  className="message-menu-item"
                  onClick={handleForward}
                >
                  Переслать
                </button>
                {canDelete && (
                  <>
                    <button
                      type="button"
                      className="message-menu-item"
                      onClick={() => handleDelete(false)}
                    >
                      Удалить у себя
                    </button>
                    <button
                      type="button"
                      className="message-menu-item"
                      onClick={() => handleDelete(true)}
                    >
                      Удалить у всех
                    </button>
                  </>
                )}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
