"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { RequireAuth } from "../../../components/RequireAuth";
import { useI18n } from "../../../components/I18nProvider";
import { transport, transportFetchAll } from "../../../lib/transport";
import { IconButton } from "../../../components/IconButton";

interface Destination { id: number; country: string; city: string; kind: string; per_diem: string; per_diem_no_overnight: string; lodging_limit: string }
interface Trip {
  id: number;
  number: string;
  worker_name: string;
  destination_id: number;
  country: string;
  city: string;
  start_date: string;
  end_date: string;
  days: number;
  overnight: number;
  per_diem_rate: string;
  per_diem_total: string;
  lodging: string;
  lodging_limit: string;
  transport_cost: string;
  advance: string;
  status: string;
  note: string;
}

const empty = { worker_name: "", destination_id: 0, start_date: "", end_date: "", overnight: 1, lodging: "0", transport_cost: "0", advance: "0", note: "" };

function TripsInner() {
  const { t } = useI18n();
  const [rows, setRows] = useState<Trip[]>([]);
  const [dests, setDests] = useState<Destination[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [modal, setModal] = useState(false);
  const [editing, setEditing] = useState<Trip | null>(null);
  const [form, setForm] = useState(empty);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [tr, d] = await Promise.all([
        transportFetchAll<Trip>("/trips"),
        transportFetchAll<Destination>("/destinations"),
      ]);
      setRows(tr);
      setDests(d);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const openCreate = () => {
    setForm(empty);
    setEditing(null);
    setFormError("");
    setModal(true);
  };

  const openEdit = (tr: Trip) => {
    setForm({ worker_name: tr.worker_name, destination_id: tr.destination_id, start_date: tr.start_date, end_date: tr.end_date, overnight: tr.overnight, lodging: tr.lodging, transport_cost: tr.transport_cost, advance: tr.advance, note: tr.note });
    setEditing(tr);
    setFormError("");
    setModal(true);
  };

  const save = async (e: FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setFormError("");
    try {
      if (editing) await transport.patch(`/trips/${editing.id}`, form);
      else await transport.post("/trips", form);
      setModal(false);
      await load();
    } catch (err) {
      setFormError(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  };

  const report = async (tr: Trip) => {
    try {
      await transport.post(`/trips/${tr.id}/report`, {});
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const del = async (tr: Trip) => {
    if (!window.confirm(t("common.confirmDelete"))) return;
    try {
      await transport.del(`/trips/${tr.id}`);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const destLabel = (d: Destination) => `${d.country}${d.city ? " · " + d.city : ""}`;

  return (
    <div>
      <div className="page-head">
        <h1 className="page-title">{t("transport.trips")}</h1>
        <button className="btn btn-primary" onClick={openCreate}>{t("common.create")}</button>
      </div>
      {error && <div className="error-text">{error}</div>}
      <div className="card">
        {loading ? (
          <div className="content muted">{t("common.loading")}</div>
        ) : rows.length === 0 ? (
          <div className="content muted">{t("common.empty")}</div>
        ) : (
          <table className="table">
            <thead>
              <tr>
                <th>{t("transport.worker")}</th>
                <th>{t("transport.destination")}</th>
                <th>{t("transport.period")}</th>
                <th className="num">{t("transport.days")}</th>
                <th className="num">{t("transport.per_diem_total")}</th>
                <th className="num">{t("transport.lodging")}</th>
                <th>{t("transport.status")}</th>
                <th>{t("common.actions")}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((tr) => (
                <tr key={tr.id}>
                  <td>{tr.worker_name}</td>
                  <td>{tr.country}{tr.city ? " · " + tr.city : ""}</td>
                  <td>{tr.start_date} → {tr.end_date}</td>
                  <td className="num">{tr.days}</td>
                  <td className="num">{tr.per_diem_total}</td>
                  <td className="num">{tr.lodging}</td>
                  <td>
                    <span className={`badge ${tr.status === "reported" ? "badge-success" : "badge-muted"}`}>
                      {tr.status === "reported" ? t("transport.reported") : t("transport.draft")}
                    </span>
                  </td>
                  <td>
                    <div className="icon-actions">
                      <IconButton icon="edit" title={t("common.edit")} onClick={() => openEdit(tr)} />
                      {tr.status !== "reported" && (
                        <button className="btn btn-sm" onClick={() => void report(tr)}>{t("transport.report")}</button>
                      )}
                      <IconButton icon="delete" title={t("common.delete")} danger onClick={() => void del(tr)} />
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {modal && (
        <div className="modal-backdrop" onClick={() => setModal(false)}>
          <div className="card modal" onClick={(e) => e.stopPropagation()}>
            <h2 className="modal-title">{editing ? t("common.edit") : t("common.create")}</h2>
            <form onSubmit={save}>
              <div className="form-grid">
                <div className="field">
                  <label className="label">{t("transport.worker")} *</label>
                  <input className="input" required value={form.worker_name} onChange={(e) => setForm({ ...form, worker_name: e.target.value })} />
                </div>
                <div className="field">
                  <label className="label">{t("transport.destination")}</label>
                  <select className="select" value={form.destination_id} onChange={(e) => setForm({ ...form, destination_id: Number(e.target.value) })}>
                    <option value={0}>—</option>
                    {dests.map((d) => <option key={d.id} value={d.id}>{destLabel(d)} ({d.kind === "domestic" ? t("transport.kind.domestic") : t("transport.kind.abroad")})</option>)}
                  </select>
                </div>
                <div className="field">
                  <label className="label">{t("transport.start_date")}</label>
                  <input className="input" type="date" value={form.start_date} onChange={(e) => setForm({ ...form, start_date: e.target.value })} />
                </div>
                <div className="field">
                  <label className="label">{t("transport.end_date")}</label>
                  <input className="input" type="date" value={form.end_date} onChange={(e) => setForm({ ...form, end_date: e.target.value })} />
                </div>
                <div className="field">
                  <label className="label">{t("transport.overnight")}</label>
                  <input type="checkbox" checked={form.overnight === 1} onChange={(e) => setForm({ ...form, overnight: e.target.checked ? 1 : 0 })} />
                </div>
                <div className="field">
                  <label className="label">{t("transport.lodging")}</label>
                  <input className="input" value={form.lodging} onChange={(e) => setForm({ ...form, lodging: e.target.value })} />
                </div>
                <div className="field">
                  <label className="label">{t("transport.transport_cost")}</label>
                  <input className="input" value={form.transport_cost} onChange={(e) => setForm({ ...form, transport_cost: e.target.value })} />
                </div>
                <div className="field">
                  <label className="label">{t("transport.advance")}</label>
                  <input className="input" value={form.advance} onChange={(e) => setForm({ ...form, advance: e.target.value })} />
                </div>
              </div>
              {formError && <div className="error-text">{formError}</div>}
              <div className="form-actions">
                <button type="button" className="btn" onClick={() => setModal(false)}>{t("common.cancel")}</button>
                <button className="btn btn-primary" disabled={saving}>{t("common.save")}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

export default function TripsPage() {
  return (
    <RequireAuth>
      <TripsInner />
    </RequireAuth>
  );
}
