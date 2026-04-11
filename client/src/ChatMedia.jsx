import { useEffect, useRef, useState } from "react";
import { downloadMessageFile, fetchMediaBlobUrl } from "./api.js";

export function VideoCircleMessage({ messageId }) {
  const [url, setUrl] = useState(null);
  const [err, setErr] = useState(false);
  const revoked = useRef(null);

  useEffect(() => {
    let cancelled = false;
    revoked.current = null;
    (async () => {
      try {
        const u = await fetchMediaBlobUrl(messageId);
        if (cancelled) {
          URL.revokeObjectURL(u);
          return;
        }
        revoked.current = u;
        setUrl(u);
      } catch {
        if (!cancelled) setErr(true);
      }
    })();
    return () => {
      cancelled = true;
      if (revoked.current) {
        URL.revokeObjectURL(revoked.current);
        revoked.current = null;
      }
    };
  }, [messageId]);

  if (err) return <span className="voice-msg-fallback">Видео недоступно</span>;
  if (!url) return <span className="voice-msg-fallback">Загрузка…</span>;

  return (
    <div className="video-circle-msg">
      <video className="video-circle-msg-inner" src={url} playsInline controls loop muted={false} />
    </div>
  );
}

export function FileAttachmentMessage({ messageId, fileName, fileMime, fileSize, caption }) {
  const [previewUrl, setPreviewUrl] = useState(null);
  const [imageOpen, setImageOpen] = useState(false);
  const revoked = useRef(null);
  const isImage = fileMime?.startsWith("image/");

  useEffect(() => {
    if (!isImage) return undefined;
    let cancelled = false;
    revoked.current = null;
    (async () => {
      try {
        const u = await fetchMediaBlobUrl(messageId);
        if (cancelled) {
          URL.revokeObjectURL(u);
          return;
        }
        revoked.current = u;
        setPreviewUrl(u);
      } catch {
        /* ignore */
      }
    })();
    return () => {
      cancelled = true;
      if (revoked.current) {
        URL.revokeObjectURL(revoked.current);
        revoked.current = null;
      }
    };
  }, [messageId, isImage]);

  const sizeStr =
    fileSize != null && fileSize > 0
      ? fileSize < 1024
        ? `${fileSize} Б`
        : fileSize < 1024 * 1024
          ? `${(fileSize / 1024).toFixed(1)} КБ`
          : `${(fileSize / (1024 * 1024)).toFixed(1)} МБ`
      : null;

  return (
    <div className={`file-attach-msg${isImage ? " image" : ""}`}>
      {previewUrl ? (
        <>
          <img
            className="file-attach-img"
            src={previewUrl}
            alt={fileName || ""}
            role="button"
            tabIndex={0}
            onClick={() => setImageOpen(true)}
            onKeyDown={(e) => {
              if (e.key === "Enter" || e.key === " ") setImageOpen(true);
            }}
          />
          {imageOpen ? (
            <div className="media-lightbox" role="presentation" onClick={() => setImageOpen(false)}>
              <img
                className="media-lightbox-img"
                src={previewUrl}
                alt={fileName || ""}
                onClick={(e) => e.stopPropagation()}
              />
              <button type="button" className="media-lightbox-close" onClick={() => setImageOpen(false)}>
                ✕
              </button>
            </div>
          ) : null}
        </>
      ) : (
        <div className="file-attach-row">
          <span className="file-attach-icon">📎</span>
          <div className="file-attach-meta">
            <div className="file-attach-name">{fileName || "Файл"}</div>
            {sizeStr ? <div className="file-attach-size">{sizeStr}</div> : null}
          </div>
        </div>
      )}
      {caption ? <div className="file-attach-caption">{caption}</div> : null}
      {!isImage ? (
        <button
          type="button"
          className="file-attach-dl"
          onClick={() => downloadMessageFile(messageId, fileName).catch(() => {})}
        >
          Скачать
        </button>
      ) : null}
    </div>
  );
}
