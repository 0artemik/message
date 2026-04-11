const API = "/api";
const AUTH_EXPIRED_EVENT = "auth:expired";

export function getToken() {
  return localStorage.getItem("token");
}

export async function api(path, options = {}) {
  const headers = { "X-Client-Type": "web", ...options.headers };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  if (options.body && typeof options.body === "object" && !(options.body instanceof FormData)) {
    headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(options.body);
  }
  const res = await fetch(`${API}${path}`, { ...options, headers });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { error: text || "Ошибка" };
  }
  if (!res.ok) {
    if (res.status === 401) {
      window.dispatchEvent(new CustomEvent(AUTH_EXPIRED_EVENT));
    }
    const err = new Error(data?.error || res.statusText);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

export async function uploadVoice(conversationId, blob, durationMs) {
  const fd = new FormData();
  fd.append("audio", blob, "voice.webm");
  fd.append("durationMs", String(durationMs ?? ""));
  const headers = { "X-Client-Type": "web" };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${API}/conversations/${conversationId}/messages/voice`, {
    method: "POST",
    headers,
    body: fd,
  });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { error: text || "Ошибка" };
  }
  if (!res.ok) {
    if (res.status === 401) {
      window.dispatchEvent(new CustomEvent(AUTH_EXPIRED_EVENT));
    }
    const err = new Error(data?.error || res.statusText);
    err.status = res.status;
    throw err;
  }
  return data;
}

export async function uploadVideoNote(conversationId, blob, durationMs, onProgress) {
  const fd = new FormData();
  fd.append("video", blob, "note.webm");
  fd.append("durationMs", String(durationMs ?? ""));
  return uploadMultipart(`/conversations/${conversationId}/messages/video-note`, fd, onProgress);
}

function uploadMultipart(path, formData, onProgress) {
  const headers = { "X-Client-Type": "web" };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", `${API}${path}`);
    Object.entries(headers).forEach(([k, v]) => xhr.setRequestHeader(k, v));
    xhr.upload.onprogress = (ev) => {
      if (!onProgress || !ev.lengthComputable) return;
      onProgress(Math.max(0, Math.min(100, Math.round((ev.loaded / ev.total) * 100))));
    };
    xhr.onerror = () => reject(new Error("Сетевая ошибка"));
    xhr.onload = () => {
      const text = xhr.responseText || "";
      let data = null;
      try {
        data = text ? JSON.parse(text) : null;
      } catch {
        data = { error: text || "Ошибка" };
      }
      if (xhr.status >= 400) {
        if (xhr.status === 401) {
          window.dispatchEvent(new CustomEvent(AUTH_EXPIRED_EVENT));
        }
        const err = new Error(data?.error || `Ошибка ${xhr.status}`);
        err.status = xhr.status;
        reject(err);
        return;
      }
      resolve(data);
    };
    xhr.send(formData);
  });
}

export async function uploadFileAttachment(conversationId, file, caption = "", onProgress) {
  const fd = new FormData();
  fd.append("file", file);
  if (caption) fd.append("caption", caption);
  return uploadMultipart(`/conversations/${conversationId}/messages/file`, fd, onProgress);
}

export async function fetchMediaBlobUrl(messageId) {
  const token = getToken();
  const res = await fetch(`${API}/messages/${messageId}/media`, {
    headers: token
      ? { Authorization: `Bearer ${token}`, "X-Client-Type": "web" }
      : { "X-Client-Type": "web" },
  });
  if (!res.ok) {
    if (res.status === 401) {
      window.dispatchEvent(new CustomEvent(AUTH_EXPIRED_EVENT));
    }
    throw new Error("media");
  }
  const blob = await res.blob();
  return URL.createObjectURL(blob);
}

export async function downloadMessageFile(messageId, fileName) {
  const token = getToken();
  const res = await fetch(`${API}/messages/${messageId}/media?download=1`, {
    headers: token
      ? { Authorization: `Bearer ${token}`, "X-Client-Type": "web" }
      : { "X-Client-Type": "web" },
  });
  if (!res.ok) {
    if (res.status === 401) {
      window.dispatchEvent(new CustomEvent(AUTH_EXPIRED_EVENT));
    }
    throw new Error("download");
  }
  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = fileName || "file";
  a.click();
  URL.revokeObjectURL(url);
}

export { AUTH_EXPIRED_EVENT };
