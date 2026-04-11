export function formatPresenceLabel({ online, lastSeenAt }) {
  if (online) return "в сети";
  if (!lastSeenAt) return "не в сети";
  const d = new Date(
    String(lastSeenAt).includes("T") ? lastSeenAt : String(lastSeenAt).replace(" ", "T")
  );
  if (Number.isNaN(d.getTime())) return "не в сети";

  const now = new Date();
  const diffMs = now - d;
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 1) return "был(а) только что";
  if (diffMin < 60) return `был(а) ${diffMin} мин. назад`;

  const sameDay =
    d.getDate() === now.getDate() &&
    d.getMonth() === now.getMonth() &&
    d.getFullYear() === now.getFullYear();
  const timeStr = d.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" });
  if (sameDay) return `был(а) сегодня в ${timeStr}`;

  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const ySame =
    d.getDate() === yesterday.getDate() &&
    d.getMonth() === yesterday.getMonth() &&
    d.getFullYear() === yesterday.getFullYear();
  if (ySame) return `был(а) вчера в ${timeStr}`;

  return `был(а) ${d.toLocaleDateString("ru-RU", { day: "numeric", month: "short" })} в ${timeStr}`;
}
