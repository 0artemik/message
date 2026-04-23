import { useEffect, useState } from "react";
import { fetchAvatarBlobUrl } from "./api.js";

function initials(name) {
  const parts = String(name || "").trim().split(/\s+/);
  const a = parts[0]?.[0] || "?";
  const b = parts[1]?.[0] || "";
  return (a + b).toUpperCase();
}

export default function UserAvatar({ user, className = "", style, imgClassName = "", size = 40 }) {
  const [src, setSrc] = useState("");

  useEffect(() => {
    let active = true;
    let objectUrl = "";
    if (!user?.avatarUrl) {
      setSrc("");
      return undefined;
    }
    fetchAvatarBlobUrl(user.avatarUrl)
      .then((url) => {
        objectUrl = url;
        if (active) setSrc(url);
      })
      .catch(() => {
        if (active) setSrc("");
      });
    return () => {
      active = false;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [user?.avatarUrl]);

  if (src) {
    return (
      <img
        src={src}
        alt={user?.displayName || "Аватар"}
        className={imgClassName || className}
        style={style}
      />
    );
  }

  return (
    <div className={className} style={style} aria-label={user?.displayName || "Аватар"}>
      {initials(user?.displayName || "?").slice(0, Math.max(1, size > 48 ? 2 : 1))}
    </div>
  );
}
