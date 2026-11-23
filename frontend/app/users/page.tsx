"use client";

// Админ панел: потребители × фирми × роли (матрица) + лог за влизане/излизане с IP.

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { RequireAuth } from "../../components/RequireAuth";
import { useI18n } from "../../components/I18nProvider";
import { useAuth } from "../../components/AuthProvider";
import { api, ListResponse } from "../../lib/api";
import { IconButton } from "../../components/IconButton";
import { Pagination } from "../../components/Pagination";

const PAGE_SIZE = 50;

interface Membership {
  company_id: number;
  company_name: string;
  role_id: number;
  role: string;
}

interface Role {
  id: number;
  name: string;
}

interface User {
  id: number;
  email: string;
  name: string;
  is_active: number;
  is_super_admin: number;
  role_id: number;
  memberships: Membership[];
}

interface AccessPack {
  users: User[];
  roles: Role[];
  companies: { id: number; name: string }[];
}

interface LoginEvent {
  id: number;
  user_id: number;
  user_login: string;
  event: string;
  ip: string;
  user_agent: string;
  detail: string;
  created_at: string;
}

const EVENTS = [
  "login",
  "logout",
  "login_failed",
  "mfa_required",
  "mfa_failed",
  "locked",
  "sessions_revoked",
];

const empty = {
  email: "",
  name: "",
  password: "",
  is_active: true,
  is_super_admin: false,
  role_id: 0,
  memberships: [] as { company_id: number; role_id: number }[],
};

function eventBadge(event: string): string {
  if (event === "login") return "badge-success";
  if (event === "logout") return "badge-muted";
  if (event === "login_failed" || event === "mfa_failed" || event === "locked") return "badge-warning";
  return "badge-muted";
}

function UsersInner() {
  const { t } = useI18n();
  const [tab, setTab] = useState<"access" | "companies" | "sessions">("access");
  const [pack, setPack] = useState<AccessPack>({ users: [], roles: [], companies: [] });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [modal, setModal] = useState(false);
  const [editing, setEditing] = useState<User | null>(null);
  const [form, setForm] = useState(empty);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState("");
  const [q, setQ] = useState("");
  const [offset, setOffset] = useState(0);

  const [events, setEvents] = useState<LoginEvent[]>([]);
  const [evTotal, setEvTotal] = useState(0);
  const [evOffset, setEvOffset] = useState(0);
  const [evUser, setEvUser] = useState("");
  const [evEvent, setEvEvent] = useState("");
  const [evLoading, setEvLoading] = useState(false);

  const loadAccess = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      setPack(await api.get<AccessPack>("/v1/admin/access"));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  const loadEvents = useCallback(async () => {
    setEvLoading(true);
    setError("");
    try {
      const r = await api.get<ListResponse<LoginEvent>>("/v1/admin/login-events", {
        user: evUser || undefined,
        event: evEvent || undefined,
        limit: PAGE_SIZE,
        offset: evOffset,
      });
      setEvents(r.items ?? []);
      setEvTotal(r.total ?? 0);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setEvLoading(false);
    }
  }, [evUser, evEvent, evOffset]);

  useEffect(() => {
    void loadAccess();
  }, [loadAccess]);

  useEffect(() => {
    if (tab === "sessions") void loadEvents();
  }, [tab, loadEvents]);

  const openCreate = () => {
    setForm(empty);
    setEditing(null);
    setFormError("");
    setModal(true);
  };

  const openEdit = (u: User) => {
    setForm({
      email: u.email,
      name: u.name,
      password: "",
      is_active: Number(u.is_active) === 1,
      is_super_admin: Number(u.is_super_admin) === 1,
      role_id: u.role_id || 0,
      memberships: u.memberships.map((m) => ({ company_id: m.company_id, role_id: m.role_id })),
    });
    setEditing(u);
    setFormError("");
    setModal(true);
  };

  const save = async (e: FormEvent) => {
    e.preventDefault();
    const memberships = form.memberships.filter((m) => m.company_id > 0 && m.role_id > 0);
    if (!form.is_super_admin && memberships.length === 0) {
      setFormError(t("users.need_company"));
      return;
    }
    setSaving(true);
    setFormError("");
    try {
      const payload: Record<string, unknown> = {
        email: form.email,
        name: form.name,
        is_active: form.is_active ? 1 : 0,
        is_super_admin: form.is_super_admin ? 1 : 0,
        role_id: form.role_id,
        memberships,
      };
      if (form.password) payload.password = form.password;
      if (editing) {
        await api.patch(`/v1/users/${editing.id}`, payload);
      } else {
        await api.post("/v1/users", payload);
      }
      setModal(false);
      await loadAccess();
    } catch (err) {
      setFormError(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  };

  const del = async (u: User) => {
    if (!window.confirm(t("common.confirmDelete"))) return;
    try {
      await api.del(`/v1/users/${u.id}`);
      await loadAccess();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const revoke = async (u: User) => {
    if (!window.confirm(t("users.revoke_confirm"))) return;
    try {
      await api.post(`/v1/admin/users/${u.id}/revoke-sessions`, {});
      setNotice(t("users.sessions_revoked"));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase();
    if (!s) return pack.users;
    return pack.users.filter((u) =>
      `${u.email} ${u.name} ${u.memberships.map((m) => `${m.company_name} ${m.role}`).join(" ")}`
        .toLowerCase()
        .includes(s)
    );
  }, [pack.users, q]);

  const setMembership = (i: number, patch: Partial<{ company_id: number; role_id: number }>) =>
    setForm((f) => ({
      ...f,
      memberships: f.memberships.map((m, idx) => (idx === i ? { ...m, ...patch } : m)),
    }));

  const addMembership = () =>
    setForm((f) => ({ ...f, memberships: [...f.memberships, { company_id: 0, role_id: 0 }] }));

  const removeMembership = (i: number) =>
    setForm((f) => ({ ...f, memberships: f.memberships.filter((_, idx) => idx !== i) }));

  // Обратна матрица: фирма → потребители и роли.
  const byCompany = useMemo(() => {
    return pack.companies.map((c) => {
      const members = pack.users
        .filter((u) => Number(u.is_super_admin) !== 1)
        .map((u) => ({ user: u, m: u.memberships.find((x) => x.company_id === c.id) }))
        .filter((x) => x.m);
      const supers = pack.users.filter((u) => Number(u.is_super_admin) === 1);
      return { company: c, members, supers };
    });
  }, [pack]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const page = Math.min(Math.floor(offset / PAGE_SIZE), pageCount - 1);
  const start = page * PAGE_SIZE;
  const paged = filtered.slice(start, start + PAGE_SIZE);

  return (
    <div>
      <div className="page-head">
        <h1 className="page-title">{t("users.title")}</h1>
        {tab === "access" && (
          <button className="btn btn-primary" type="button" onClick={openCreate}>
            {t("common.create")}
          </button>
        )}
      </div>
      {error && <div className="error-text">{error}</div>}
      {notice && <div className="muted" style={{ marginBottom: 8 }}>{notice}</div>}

      <div className="tabs" style={{ marginBottom: 12 }}>
        {(["access", "companies", "sessions"] as const).map((k) => (
          <button
            key={k}
            type="button"
            className={`tab${tab === k ? " tab-active" : ""}`}
            onClick={() => setTab(k)}
          >
            {t(`users.tab.${k}`)}
          </button>
        ))}
      </div>

      {tab === "access" && (
        <>
          <div className="card" style={{ marginBottom: 12 }}>
            <input
              className="input"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder={t("common.search")}
            />
          </div>
          <div className="card">
            {loading ? (
              <div className="content muted">{t("common.loading")}</div>
            ) : filtered.length === 0 ? (
              <div className="content muted">{t("common.empty")}</div>
            ) : (
              <table className="table">
                <thead>
                  <tr>
                    <th>{t("users.name")}</th>
                    <th>{t("users.email")}</th>
                    <th>{t("users.memberships")}</th>
                    <th>{t("users.active")}</th>
                    <th>{t("users.super")}</th>
                    <th>{t("common.actions")}</th>
                  </tr>
                </thead>
                <tbody>
                  {paged.map((u) => (
                    <tr key={u.id}>
                      <td>{u.name}</td>
                      <td>{u.email}</td>
                      <td>
                        {Number(u.is_super_admin) === 1 ? (
                          <span className="badge badge-success">*</span>
                        ) : u.memberships.length === 0 ? (
                          <span className="muted">{t("users.no_memberships")}</span>
                        ) : (
                          <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
                            {u.memberships.map((m) => (
                              <span key={m.company_id} className="badge badge-muted" title={m.role}>
                                {m.company_name}: {m.role}
                              </span>
                            ))}
                          </div>
                        )}
                      </td>
                      <td>{Number(u.is_active) === 1 ? "✓" : ""}</td>
                      <td>{Number(u.is_super_admin) === 1 ? "✓" : ""}</td>
                      <td>
                        <div className="icon-actions">
                          <IconButton icon="edit" title={t("common.edit")} onClick={() => openEdit(u)} />
                          <IconButton
                            icon="action"
                            title={t("users.revoke_sessions")}
                            onClick={() => void revoke(u)}
                          />
                          <IconButton
                            icon="delete"
                            title={t("common.delete")}
                            danger
                            onClick={() => void del(u)}
                          />
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            <Pagination
              total={filtered.length}
              limit={PAGE_SIZE}
              offset={start}
              onPageChange={setOffset}
            />
          </div>
        </>
      )}

      {tab === "companies" && (
        <div>
          {loading ? (
            <div className="card content muted">{t("common.loading")}</div>
          ) : byCompany.length === 0 ? (
            <div className="card content muted">{t("common.empty")}</div>
          ) : (
            byCompany.map(({ company, members, supers }) => (
              <div className="card" key={company.id} style={{ marginBottom: 12 }}>
                <div className="content" style={{ paddingBottom: 0 }}>
                  <strong>{company.name}</strong>
                </div>
                <table className="table">
                  <thead>
                    <tr>
                      <th>{t("users.name")}</th>
                      <th>{t("users.email")}</th>
                      <th>{t("users.role")}</th>
                      <th>{t("common.actions")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {supers.map((u) => (
                      <tr key={`s${u.id}`}>
                        <td>{u.name}</td>
                        <td>{u.email}</td>
                        <td><span className="badge badge-success">{t("users.super")}</span></td>
                        <td>
                          <IconButton icon="edit" title={t("common.edit")} onClick={() => openEdit(u)} />
                        </td>
                      </tr>
                    ))}
                    {members.map(({ user, m }) => (
                      <tr key={user.id}>
                        <td>{user.name}</td>
                        <td>{user.email}</td>
                        <td><span className="badge badge-muted">{m!.role}</span></td>
                        <td>
                          <IconButton icon="edit" title={t("common.edit")} onClick={() => openEdit(user)} />
                        </td>
                      </tr>
                    ))}
                    {members.length === 0 && supers.length === 0 && (
                      <tr><td colSpan={4} className="muted">{t("users.no_memberships")}</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            ))
          )}
        </div>
      )}

      {tab === "sessions" && (
        <div className="card">
          <div className="content" style={{ display: "flex", gap: 8, flexWrap: "wrap", paddingBottom: 0 }}>
            <input
              className="input"
              style={{ maxWidth: 260 }}
              value={evUser}
              onChange={(e) => {
                setEvUser(e.target.value);
                setEvOffset(0);
              }}
              placeholder={t("sessions.filter_user")}
            />
            <select
              className="select"
              style={{ maxWidth: 220 }}
              value={evEvent}
              onChange={(e) => {
                setEvEvent(e.target.value);
                setEvOffset(0);
              }}
            >
              <option value="">{t("sessions.all_events")}</option>
              {EVENTS.map((ev) => (
                <option key={ev} value={ev}>
                  {t(`sessions.event.${ev}`)}
                </option>
              ))}
            </select>
          </div>
          {evLoading ? (
            <div className="content muted">{t("common.loading")}</div>
          ) : events.length === 0 ? (
            <div className="content muted">{t("common.empty")}</div>
          ) : (
            <table className="table">
              <thead>
                <tr>
                  <th>{t("sessions.time")}</th>
                  <th>{t("sessions.user")}</th>
                  <th>{t("sessions.event")}</th>
                  <th>{t("sessions.ip")}</th>
                  <th>{t("sessions.agent")}</th>
                  <th>{t("sessions.detail")}</th>
                </tr>
              </thead>
              <tbody>
                {events.map((e) => (
                  <tr key={e.id}>
                    <td style={{ whiteSpace: "nowrap" }}>{e.created_at}</td>
                    <td>{e.user_login}</td>
                    <td>
                      <span className={`badge ${eventBadge(e.event)}`}>
                        {t(`sessions.event.${e.event}`)}
                      </span>
                    </td>
                    <td style={{ fontFamily: "ui-monospace, monospace" }}>{e.ip}</td>
                    <td className="muted" style={{ maxWidth: 280, overflow: "hidden", textOverflow: "ellipsis" }} title={e.user_agent}>
                      {e.user_agent}
                    </td>
                    <td className="muted">{e.detail}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          <Pagination
            total={evTotal}
            limit={PAGE_SIZE}
            offset={evOffset}
            onPageChange={setEvOffset}
          />
        </div>
      )}

      {modal && (
        <div className="modal-backdrop" onClick={() => setModal(false)}>
          <div className="card modal" onClick={(e) => e.stopPropagation()}>
            <h2 className="modal-title">
              {editing ? t("common.edit") : t("common.create")}
            </h2>
            <form onSubmit={save}>
              <div className="form-grid">
                <div className="field">
                  <label className="label">{t("users.email")} *</label>
                  <input
                    className="input"
                    required
                    value={form.email}
                    onChange={(e) => setForm({ ...form, email: e.target.value })}
                  />
                </div>
                <div className="field">
                  <label className="label">{t("users.name")} *</label>
                  <input
                    className="input"
                    required
                    value={form.name}
                    onChange={(e) => setForm({ ...form, name: e.target.value })}
                  />
                </div>
                <div className="field">
                  <label className="label">
                    {t("users.password")}
                    {editing ? "" : " *"}
                  </label>
                  <input
                    className="input"
                    type="password"
                    required={!editing}
                    value={form.password}
                    onChange={(e) => setForm({ ...form, password: e.target.value })}
                    placeholder={editing ? t("users.password_keep") : ""}
                  />
                </div>
                <div className="field">
                  <label className="label">{t("users.role")}</label>
                  <select
                    className="select"
                    value={form.role_id}
                    onChange={(e) =>
                      setForm({ ...form, role_id: Number(e.target.value) })
                    }
                  >
                    <option value={0}>{t("users.role_none")}</option>
                    {pack.roles.map((r) => (
                      <option key={r.id} value={r.id}>
                        {r.name}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
              <label className="label" style={{ display: "flex", gap: 8, marginTop: 8 }}>
                <input
                  type="checkbox"
                  checked={form.is_active}
                  onChange={(e) => setForm({ ...form, is_active: e.target.checked })}
                />
                {t("users.active")}
              </label>
              <label className="label" style={{ display: "flex", gap: 8 }}>
                <input
                  type="checkbox"
                  checked={form.is_super_admin}
                  onChange={(e) =>
                    setForm({ ...form, is_super_admin: e.target.checked })
                  }
                />
                {t("users.super")}
              </label>
              {!form.is_super_admin && (
                <div style={{ marginTop: 12 }}>
                  <label className="label">{t("users.memberships")} *</label>
                  {form.memberships.map((m, i) => (
                    <div key={i} style={{ display: "flex", gap: 8, marginBottom: 6, flexWrap: "wrap" }}>
                      <select
                        className="select"
                        value={m.company_id}
                        onChange={(e) => setMembership(i, { company_id: Number(e.target.value) })}
                      >
                        <option value={0}>{t("users.pick_company")}</option>
                        {pack.companies.map((c) => (
                          <option key={c.id} value={c.id}>
                            {c.name}
                          </option>
                        ))}
                      </select>
                      <select
                        className="select"
                        value={m.role_id}
                        onChange={(e) => setMembership(i, { role_id: Number(e.target.value) })}
                      >
                        <option value={0}>{t("users.pick_role")}</option>
                        {pack.roles.map((r) => (
                          <option key={r.id} value={r.id}>
                            {r.name}
                          </option>
                        ))}
                      </select>
                      <button
                        type="button"
                        className="btn btn-danger btn-sm"
                        onClick={() => removeMembership(i)}
                      >
                        ✕
                      </button>
                    </div>
                  ))}
                  <button type="button" className="btn btn-sm" onClick={addMembership}>
                    + {t("users.add_company")}
                  </button>
                </div>
              )}
              {formError && <div className="error-text">{formError}</div>}
              <div className="form-actions">
                <button type="button" className="btn" onClick={() => setModal(false)}>
                  {t("common.cancel")}
                </button>
                <button className="btn btn-primary" disabled={saving}>
                  {t("common.save")}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

function UsersGate() {
  const { t } = useI18n();
  const { isSuperAdmin } = useAuth();
  if (!isSuperAdmin) {
    return (
      <div className="card card-pad">
        <p className="muted" style={{ margin: 0 }}>
          {t("common.super_only")}
        </p>
      </div>
    );
  }
  return <UsersInner />;
}

export default function UsersPage() {
  return (
    <RequireAuth>
      <UsersGate />
    </RequireAuth>
  );
}
