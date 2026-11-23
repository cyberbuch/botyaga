"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { RequireAuth } from "../../../components/RequireAuth";
import { useI18n } from "../../../components/I18nProvider";
import { transport, transportFetchAll } from "../../../lib/transport";
import { IconButton } from "../../../components/IconButton";

interface Vehicle { id: number; name: string; plate: string; norm: string }
interface Driver { id: number; name: string }
interface Row {
  id?: number;
  kind: string;
  date: string;
  description: string;
  city_km: string;
  out_km: string;
  winter: number;
  fuel_liters: string;
  fuel_cost: string;
}
interface Waybill {
  id: number;
  number: string;
  date: string;
  status: string;
  vehicle_id: number;
  vehicle_name: string;
  plate: string;
  driver_id: number;
  driver_name: string;
  approver: string;
  start_odometer: string;
  start_fuel: string;
  end_odometer: string;
  end_fuel: string;
  total_km: string;
  total_refuel: string;
  norm_consumption: string;
  expected_end_fuel: string;
  expected_end_odometer: number;
  rows: Row[];
  note: string;
}

const emptyRow = (): Row => ({
  kind: "route", date: "", description: "", city_km: "0", out_km: "0", winter: 0, fuel_liters: "0", fuel_cost: "0",
});

function WaybillsInner() {
  const { t } = useI18n();
  const [rows, setRows] = useState<Waybill[]>([]);
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [modal, setModal] = useState(false);
  const [editing, setEditing] = useState<Waybill | null>(null);
  const [form, setForm] = useState({ date: "", vehicle_id: 0, driver_id: 0, approver: "", start_odometer: "0", start_fuel: "0", note: "" });
  const [formRows, setFormRows] = useState<Row[]>([emptyRow()]);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState("");
  const [closing, setClosing] = useState<Waybill | null>(null);
  const [closeForm, setCloseForm] = useState({ end_odometer: "", end_fuel: "" });

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [w, v, d] = await Promise.all([
        transportFetchAll<Waybill>("/waybills"),
        transportFetchAll<Vehicle>("/vehicles"),
        transportFetchAll<Driver>("/drivers"),
      ]);
      setRows(w);
      setVehicles(v);
      setDrivers(d);
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
    setForm({ date: new Date().toISOString().slice(0, 10), vehicle_id: 0, driver_id: 0, approver: "", start_odometer: "0", start_fuel: "0", note: "" });
    setFormRows([emptyRow()]);
    setEditing(null);
    setFormError("");
    setModal(true);
  };

  const openEdit = async (w: Waybill) => {
    try {
      const full = await transport.get<Waybill>(`/waybills/${w.id}`);
      setForm({ date: full.date, vehicle_id: full.vehicle_id, driver_id: full.driver_id, approver: full.approver, start_odometer: full.start_odometer, start_fuel: full.start_fuel, note: full.note });
      setFormRows(full.rows.length ? full.rows : [emptyRow()]);
      setEditing(full);
      setFormError("");
      setModal(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const save = async (e: FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setFormError("");
    try {
      const payload = { ...form, rows: formRows };
      if (editing) await transport.patch(`/waybills/${editing.id}`, payload);
      else await transport.post("/waybills", payload);
      setModal(false);
      await load();
    } catch (err) {
      setFormError(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  };

  const openClose = async (w: Waybill) => {
    const full = await transport.get<Waybill>(`/waybills/${w.id}`);
    setCloseForm({ end_odometer: String(full.expected_end_odometer), end_fuel: full.expected_end_fuel });
    setClosing(full);
  };

  const doClose = async (e: FormEvent) => {
    e.preventDefault();
    if (!closing) return;
    setSaving(true);
    try {
      await transport.post(`/waybills/${closing.id}/close`, closeForm);
      setClosing(null);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  };

  const del = async (w: Waybill) => {
    if (!window.confirm(t("common.confirmDelete"))) return;
    try {
      await transport.del(`/waybills/${w.id}`);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const setRow = (i: number, patch: Partial<Row>) =>
    setFormRows((prev) => prev.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));

  return (
    <div>
      <div className="page-head">
        <h1 className="page-title">{t("transport.waybills")}</h1>
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
                <th>{t("transport.vehicle")}</th>
                <th>{t("transport.date")}</th>
                <th>{t("transport.driver")}</th>
                <th>{t("transport.status")}</th>
                <th className="num">{t("transport.total_km")}</th>
                <th className="num">{t("transport.norm_consumption")}</th>
                <th>{t("common.actions")}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((w) => (
                <tr key={w.id}>
                  <td>{w.vehicle_name}<div className="muted">{w.plate}</div></td>
                  <td>{w.date}</td>
                  <td>{w.driver_name}</td>
                  <td>
                    <span className={`badge ${w.status === "closed" ? "badge-success" : "badge-warning"}`}>
                      {w.status === "closed" ? t("transport.closed") : t("transport.open")}
                    </span>
                  </td>
                  <td className="num">{w.total_km}</td>
                  <td className="num">{w.norm_consumption}</td>
                  <td>
                    <div className="icon-actions">
                      {w.status !== "closed" && (
                        <>
                          <IconButton icon="edit" title={t("common.edit")} onClick={() => void openEdit(w)} />
                          <button className="btn btn-sm" onClick={() => void openClose(w)}>{t("transport.close")}</button>
                        </>
                      )}
                      <IconButton icon="delete" title={t("common.delete")} danger onClick={() => void del(w)} />
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
          <div className="card modal modal-lg" onClick={(e) => e.stopPropagation()}>
            <h2 className="modal-title">{editing ? t("common.edit") : t("common.create")}</h2>
            <form onSubmit={save}>
              <div className="form-grid">
                <div className="field">
                  <label className="label">{t("transport.date")} *</label>
                  <input className="input" type="date" required value={form.date} onChange={(e) => setForm({ ...form, date: e.target.value })} />
                </div>
                <div className="field">
                  <label className="label">{t("transport.vehicle")}</label>
                  <select className="select" value={form.vehicle_id} onChange={(e) => setForm({ ...form, vehicle_id: Number(e.target.value) })}>
                    <option value={0}>—</option>
                    {vehicles.map((v) => <option key={v.id} value={v.id}>{v.name} ({v.plate})</option>)}
                  </select>
                </div>
                <div className="field">
                  <label className="label">{t("transport.driver")}</label>
                  <select className="select" value={form.driver_id} onChange={(e) => setForm({ ...form, driver_id: Number(e.target.value) })}>
                    <option value={0}>—</option>
                    {drivers.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                  </select>
                </div>
                <div className="field">
                  <label className="label">{t("transport.approver")}</label>
                  <input className="input" value={form.approver} onChange={(e) => setForm({ ...form, approver: e.target.value })} />
                </div>
                <div className="field">
                  <label className="label">{t("transport.start_odometer")}</label>
                  <input className="input" value={form.start_odometer} onChange={(e) => setForm({ ...form, start_odometer: e.target.value })} />
                </div>
                <div className="field">
                  <label className="label">{t("transport.start_fuel")}</label>
                  <input className="input" value={form.start_fuel} onChange={(e) => setForm({ ...form, start_fuel: e.target.value })} />
                </div>
              </div>

              <h3 style={{ margin: "16px 0 8px" }}>{t("transport.rows")}</h3>
              {formRows.map((r, i) => (
                <div key={i} className="form-grid" style={{ marginBottom: 8, alignItems: "end" }}>
                  <div className="field">
                    <label className="label">{t("transport.row_kind")}</label>
                    <select className="select" value={r.kind} onChange={(e) => setRow(i, { kind: e.target.value })}>
                      <option value="route">{t("transport.route")}</option>
                      <option value="refuel">{t("transport.refuel")}</option>
                    </select>
                  </div>
                  <div className="field" style={{ gridColumn: "span 2" }}>
                    <label className="label">{t("transport.description")}</label>
                    <input className="input" value={r.description} onChange={(e) => setRow(i, { description: e.target.value })} />
                  </div>
                  {r.kind === "route" ? (
                    <>
                      <div className="field">
                        <label className="label">{t("transport.city_km")}</label>
                        <input className="input" value={r.city_km} onChange={(e) => setRow(i, { city_km: e.target.value })} />
                      </div>
                      <div className="field">
                        <label className="label">{t("transport.out_km")}</label>
                        <input className="input" value={r.out_km} onChange={(e) => setRow(i, { out_km: e.target.value })} />
                      </div>
                      <div className="field">
                        <label className="label">{t("transport.winter")}</label>
                        <input type="checkbox" checked={r.winter === 1} onChange={(e) => setRow(i, { winter: e.target.checked ? 1 : 0 })} />
                      </div>
                    </>
                  ) : (
                    <>
                      <div className="field">
                        <label className="label">{t("transport.fuel_liters")}</label>
                        <input className="input" value={r.fuel_liters} onChange={(e) => setRow(i, { fuel_liters: e.target.value })} />
                      </div>
                      <div className="field">
                        <label className="label">{t("transport.fuel_cost")}</label>
                        <input className="input" value={r.fuel_cost} onChange={(e) => setRow(i, { fuel_cost: e.target.value })} />
                      </div>
                    </>
                  )}
                  <div className="field">
                    <button type="button" className="btn btn-danger btn-sm" onClick={() => setFormRows((prev) => prev.filter((_, idx) => idx !== i))}>✕</button>
                  </div>
                </div>
              ))}
              <button type="button" className="btn btn-sm" onClick={() => setFormRows((prev) => [...prev, emptyRow()])}>+ {t("transport.add_row")}</button>

              {formError && <div className="error-text">{formError}</div>}
              <div className="form-actions">
                <button type="button" className="btn" onClick={() => setModal(false)}>{t("common.cancel")}</button>
                <button className="btn btn-primary" disabled={saving}>{t("common.save")}</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {closing && (
        <div className="modal-backdrop" onClick={() => setClosing(null)}>
          <div className="card modal" onClick={(e) => e.stopPropagation()}>
            <h2 className="modal-title">{t("transport.close")}</h2>
            <form onSubmit={doClose}>
              <div className="form-grid">
                <div className="field">
                  <label className="label">{t("transport.end_odometer")}</label>
                  <input className="input" value={closeForm.end_odometer} onChange={(e) => setCloseForm({ ...closeForm, end_odometer: e.target.value })} />
                </div>
                <div className="field">
                  <label className="label">{t("transport.end_fuel")}</label>
                  <input className="input" value={closeForm.end_fuel} onChange={(e) => setCloseForm({ ...closeForm, end_fuel: e.target.value })} />
                </div>
              </div>
              <p className="muted">{t("transport.close_hint")}</p>
              <div className="form-actions">
                <button type="button" className="btn" onClick={() => setClosing(null)}>{t("common.cancel")}</button>
                <button className="btn btn-primary" disabled={saving}>{t("common.save")}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

export default function WaybillsPage() {
  return (
    <RequireAuth>
      <WaybillsInner />
    </RequireAuth>
  );
}
