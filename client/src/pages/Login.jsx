import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api } from "../api.js";
import { useAuth } from "../authContext.jsx";
import "./Auth.css";

export default function Login() {
  const nav = useNavigate();
  const { setSession, user } = useAuth();
  const [username, setUsername] = useState("");
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
      const data = await api("/auth/login", {
        method: "POST",
        body: { username, password },
      });
      setSession({ token: data.token, user: data.user });
      nav("/", { replace: true });
    } catch (err) {
      setError(err.message || "Ошибка входа");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-logo">✈</div>
        <h1 className="auth-title">Войти</h1>
        <p className="auth-sub">Добро пожаловать в мессенджер</p>
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
            />
          </label>
          <label className="auth-label">
            Пароль
            <input
              className="auth-input"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
              required
            />
          </label>
          <button className="auth-submit" type="submit" disabled={busy}>
            {busy ? "…" : "Войти"}
          </button>
        </form>
        <p className="auth-footer">
          Нет аккаунта? <Link to="/register">Зарегистрироваться</Link>
        </p>
      </div>
    </div>
  );
}
