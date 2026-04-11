function pickVideoMime() {
  if (typeof MediaRecorder === "undefined") return "";
  if (MediaRecorder.isTypeSupported("video/webm;codecs=vp8,opus")) return "video/webm;codecs=vp8,opus";
  if (MediaRecorder.isTypeSupported("video/webm")) return "video/webm";
  return "";
}

function readImageBitmap(file) {
  return new Promise((resolve, reject) => {
    const u = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(u);
      resolve(img);
    };
    img.onerror = () => {
      URL.revokeObjectURL(u);
      reject(new Error("image"));
    };
    img.src = u;
  });
}

function canvasToBlob(canvas, type, quality) {
  return new Promise((resolve) => {
    canvas.toBlob((blob) => resolve(blob), type, quality);
  });
}

export async function compressAttachmentForUpload(file) {
  if (!file) return { file, compressed: false, originalSize: 0 };
  if (file.type.startsWith("image/")) {
    return compressImage(file);
  }
  if (file.type.startsWith("video/")) {
    return compressVideo(file);
  }
  return { file, compressed: false, originalSize: file.size || 0 };
}

async function compressImage(file) {
  try {
    const img = await readImageBitmap(file);
    const maxSide = 1600;
    const scale = Math.min(1, maxSide / Math.max(img.width, img.height));
    const w = Math.max(1, Math.round(img.width * scale));
    const h = Math.max(1, Math.round(img.height * scale));
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d", { alpha: false });
    if (!ctx) return { file, compressed: false, originalSize: file.size || 0 };
    ctx.drawImage(img, 0, 0, w, h);
    const blob = await canvasToBlob(canvas, "image/jpeg", 0.82);
    if (!blob || blob.size >= file.size) {
      return { file, compressed: false, originalSize: file.size || 0 };
    }
    const out = new File([blob], file.name.replace(/\.\w+$/, ".jpg"), { type: "image/jpeg" });
    return { file: out, compressed: true, originalSize: file.size || 0 };
  } catch {
    return { file, compressed: false, originalSize: file.size || 0 };
  }
}

async function compressVideo(file) {
  // Browser-side video compression is best-effort and may fail depending on codec support.
  const mime = pickVideoMime();
  if (!mime) return { file, compressed: false, originalSize: file.size || 0 };
  try {
    const srcUrl = URL.createObjectURL(file);
    const video = document.createElement("video");
    video.src = srcUrl;
    video.playsInline = true;
    video.muted = true;
    await video.play().catch(() => {});
    await new Promise((resolve, reject) => {
      video.onloadedmetadata = resolve;
      video.onerror = reject;
    });
    const maxSide = 960;
    const scale = Math.min(1, maxSide / Math.max(video.videoWidth || 1, video.videoHeight || 1));
    const w = Math.max(2, Math.round((video.videoWidth || 640) * scale));
    const h = Math.max(2, Math.round((video.videoHeight || 640) * scale));
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("ctx");
    const draw = () => {
      if (video.paused || video.ended) return;
      ctx.drawImage(video, 0, 0, w, h);
      requestAnimationFrame(draw);
    };
    const stream = canvas.captureStream(24);
    const rec = new MediaRecorder(stream, {
      mimeType: mime,
      videoBitsPerSecond: 900_000,
      audioBitsPerSecond: 64_000,
    });
    const chunks = [];
    rec.ondataavailable = (e) => {
      if (e.data?.size) chunks.push(e.data);
    };
    draw();
    rec.start(250);
    await video.play().catch(() => {});
    await new Promise((resolve) => {
      video.onended = resolve;
      video.currentTime = 0;
      video.play().catch(resolve);
    });
    await new Promise((resolve) => {
      rec.onstop = resolve;
      rec.stop();
    });
    URL.revokeObjectURL(srcUrl);
    const blob = new Blob(chunks, { type: rec.mimeType || "video/webm" });
    if (!blob.size || blob.size >= file.size) {
      return { file, compressed: false, originalSize: file.size || 0 };
    }
    const out = new File([blob], file.name.replace(/\.\w+$/, ".webm"), { type: blob.type || "video/webm" });
    return { file: out, compressed: true, originalSize: file.size || 0 };
  } catch {
    return { file, compressed: false, originalSize: file.size || 0 };
  }
}
