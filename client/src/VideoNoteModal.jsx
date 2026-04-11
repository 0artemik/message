import { useEffect, useRef, useState } from "react";
import { uploadVideoNote } from "./api.js";

function pickVideoMime() {
  if (typeof MediaRecorder === "undefined") return "";
  if (MediaRecorder.isTypeSupported("video/webm;codecs=vp9,opus")) return "video/webm;codecs=vp9,opus";
  if (MediaRecorder.isTypeSupported("video/webm;codecs=vp8,opus")) return "video/webm;codecs=vp8,opus";
  if (MediaRecorder.isTypeSupported("video/webm")) return "video/webm";
  return "";
}

export default function VideoNoteModal({ open, conversationId, onClose, onSent }) {
  const videoRef = useRef(null);
  const streamRef = useRef(null);
  const recRef = useRef(null);
  const chunksRef = useRef([]);
  const startRef = useRef(0);
  const phaseRef = useRef("idle");
  const maxMs = 60_000;

  const [phase, setPhase] = useState("idle");
  const [error, setError] = useState("");
  const [secs, setSecs] = useState(0);
  const [uploadProgress, setUploadProgress] = useState(0);

  function setPhaseBoth(p) {
    phaseRef.current = p;
    setPhase(p);
  }

  function hardStop() {
    const rec = recRef.current;
    recRef.current = null;
    if (rec && rec.state !== "inactive") {
      try {
        rec.stop();
      } catch {
        /* ignore */
      }
    }
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    setPhaseBoth("idle");
    setSecs(0);
  }

  useEffect(() => {
    if (!open) {
      hardStop();
      setError("");
      return undefined;
    }

    let cancelled = false;
    setError("");

    (async () => {
      if (!navigator.mediaDevices?.getUserMedia) {
        setError("Камера недоступна");
        return;
      }
      const mime = pickVideoMime();
      if (!mime) {
        setError("Запись WebM не поддерживается (нужен Chrome / Firefox / Edge)");
        return;
      }
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "user", width: { ideal: 480 }, height: { ideal: 480 } },
          audio: true,
        });
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }
        streamRef.current = stream;
        const el = videoRef.current;
        if (el) {
          el.srcObject = stream;
          await el.play().catch(() => {});
        }
        setPhaseBoth("preview");
      } catch {
        if (!cancelled) setError("Нет доступа к камере / микрофону");
      }
    })();

    return () => {
      cancelled = true;
      hardStop();
    };
  }, [open]);

  useEffect(() => {
    if (phase !== "recording") return undefined;
    const id = setInterval(() => {
      const elapsed = Date.now() - startRef.current;
      setSecs(Math.floor(elapsed / 1000));
      if (elapsed >= maxMs) {
        void finalizeRecording(true);
      }
    }, 200);
    return () => clearInterval(id);
  }, [phase]);

  async function finalizeRecording(send) {
    const rec = recRef.current;
    if (!rec || phaseRef.current !== "recording") return;
    recRef.current = null;
    await new Promise((resolve) => {
      rec.onstop = resolve;
      try {
        rec.requestData?.();
      } catch {
        /* ignore */
      }
      try {
        rec.stop();
      } catch {
        resolve();
      }
    });
    const durationMs = Date.now() - startRef.current;
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    setPhaseBoth("idle");
    setSecs(0);
    if (!send || !conversationId) {
      onClose();
      return;
    }
    const blob = new Blob(chunksRef.current, { type: rec.mimeType || "video/webm" });
    chunksRef.current = [];
    if (blob.size < 32) {
      setError("Слишком короткое видео");
      onClose();
      return;
    }
    try {
      setPhaseBoth("uploading");
      await uploadVideoNote(conversationId, blob, durationMs, (p) => setUploadProgress(p));
      onSent?.();
      onClose();
    } catch (e) {
      setError(e.message || "Не удалось отправить");
      setPhaseBoth("idle");
    }
  }

  function startRecord() {
    const stream = streamRef.current;
    const mime = pickVideoMime();
    if (!stream || !mime) return;
    setError("");
    chunksRef.current = [];
    const rec = new MediaRecorder(stream, {
      mimeType: mime,
      videoBitsPerSecond: 700_000,
      audioBitsPerSecond: 64_000,
    });
    recRef.current = rec;
    rec.ondataavailable = (e) => {
      if (e.data?.size) chunksRef.current.push(e.data);
    };
    startRef.current = Date.now();
    setSecs(0);
    rec.start(250);
    setPhaseBoth("recording");
  }

  function handleClose() {
    if (phaseRef.current === "recording") {
      void finalizeRecording(false);
      return;
    }
    hardStop();
    onClose();
  }

  if (!open) return null;

  return (
    <div className="video-note-overlay" role="presentation" onClick={() => phase === "preview" && handleClose()}>
      <div className="video-note-dialog" onClick={(e) => e.stopPropagation()}>
        <div className="video-note-title">Видеосообщение</div>
        <p className="video-note-hint">Круглое видео — до 60 сек. Работает в браузерах с WebM.</p>
        {error ? <div className="video-note-error">{error}</div> : null}
        <div className="video-note-circle-wrap">
          <video ref={videoRef} className="video-note-video" playsInline muted />
        </div>
        {phase === "preview" ? (
          <div className="video-note-actions">
            <button type="button" className="video-note-btn secondary" onClick={handleClose}>
              Закрыть
            </button>
            <button type="button" className="video-note-btn primary" onClick={startRecord}>
              Записать
            </button>
          </div>
        ) : null}
        {phase === "recording" ? (
          <div className="video-note-recording">
            <div className="video-note-rec-row">
              <span className="video-note-rec-dot" />
              <span className="video-note-rec-time">
                {String(Math.floor(secs / 60)).padStart(2, "0")}:{String(secs % 60).padStart(2, "0")}
              </span>
            </div>
            <div className="video-note-actions">
              <button type="button" className="video-note-btn secondary" onClick={() => void finalizeRecording(false)}>
                Отмена
              </button>
              <button type="button" className="video-note-btn primary" onClick={() => void finalizeRecording(true)}>
                Отправить
              </button>
            </div>
          </div>
        ) : null}
        {phase === "uploading" ? (
          <div className="video-note-recording">
            <div className="video-note-rec-row">
              <span className="video-note-rec-time">Загрузка: {uploadProgress}%</span>
            </div>
            <div className="upload-progress-bar">
              <div className="upload-progress-value" style={{ width: `${uploadProgress}%` }} />
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}
