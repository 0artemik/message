import { useEffect, useRef, useState } from "react";
import { fetchMediaBlobUrl } from "./api.js";

export default function VoiceMessage({ messageId, durationMs }) {
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

  const label =
    durationMs != null && durationMs > 0
      ? `${Math.max(1, Math.round(durationMs / 1000))} сек`
      : null;

  if (err) {
    return <span className="voice-msg-fallback">Не удалось загрузить аудио</span>;
  }
  if (!url) {
    return <span className="voice-msg-fallback">Загрузка…</span>;
  }

  return (
    <div className="voice-msg">
      <audio className="voice-msg-audio" controls src={url} preload="metadata" />
      {label ? <span className="voice-msg-meta">{label}</span> : null}
    </div>
  );
}
