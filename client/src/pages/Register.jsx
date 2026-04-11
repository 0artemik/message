import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api } from "../api.js";
import { useAuth } from "../authContext.jsx";
import "./Auth.css";

export default function Register() {
  const nav = useNavigate();
  const { setSession, user } = useAuth();
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (user) nav("/", { replace: true });
  }, [user, nav]);

  async function onSubmit(e) {
    e.preventDefault();
    setError("");
    setBusy(true);
    try {
      const data = await api("/auth/register", {
        method: "POST",
        body: {
          username,
          email,
          password,
          displayName: displayName || username,
        },
      });
      setSession({ token: data.token, user: data.user });
      nav("/", { replace: true });
    } catch (err) {
      setError(err.message || "Ошибка регистрации");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-logo">✈</div>
        <h1 className="auth-title">Регистрация</h1>
        <p className="auth-sub">Создайте аккаунт, чтобы начать переписку</p>
        <form className="auth-form" onSubmit={onSubmit}>
          {error ? <div className="auth-error">{error}</div> : null}
          <label className="auth-label">
            Логин
            <input
              className="auth-input"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              autoComplete="username"
              required
              minLength={3}
            />
          </label>
          <label className="auth-label">
            Email
            <input
              className="auth-input"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="email"
              required
            />
          </label>
          <label className="auth-label">
            Имя (как вас видят другие)
            <input
              className="auth-input"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder={username || "Иван"}
            />
          </label>
          <label className="auth-label">
            Пароль
            <input
              className="auth-input"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="new-password"
              required
              minLength={6}
            />
          </label>
          <button className="auth-submit" type="submit" disabled={busy}>
            {busy ? "…" : "Создать аккаунт"}
          </button>
        </form>
        <p className="auth-footer">
          Уже есть аккаунт? <Link to="/login">Войти</Link>
        </p>
      </div>
    </div>
  );
}
