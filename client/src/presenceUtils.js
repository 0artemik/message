export function formatPresenceLabel({ online, lastSeenAt }) {
  if (online) return "в сети";
  if (!lastSeenAt) return "не в сети";
  const raw = String(lastSeenAt);
  const normalized =
    /[zZ]$|[+\-]\d{2}:\d{2}$/.test(raw) ? raw : `${raw.includes("T") ? raw : raw.replace(" ", "T")}Z`;
  const d = new Date(normalized);
  if (Number.isNaN(d.getTime())) return "не в сети";

  const now = new Date();
  const diffMs = now - d;
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 1) return "был(а) только что";
  if (diffMin < 60) return `был(а) ${diffMin} мин. назад`;
  const mskDate = (value) =>
    value.toLocaleDateString("sv-SE", {
      timeZone: "Europe/Moscow",
    });

  const sameDay = mskDate(d) === mskDate(now);
  const timeStr = d.toLocaleTimeString("ru-RU", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Europe/Moscow",
  });
  if (sameDay) return `был(а) сегодня в ${timeStr}`;

  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const ySame = mskDate(d) === mskDate(yesterday);
  if (ySame) return `был(а) вчера в ${timeStr}`;

  return `был(а) ${d.toLocaleDateString("ru-RU", {
    day: "numeric",
    month: "short",
    timeZone: "Europe/Moscow",
  })} в ${timeStr}`;
}
