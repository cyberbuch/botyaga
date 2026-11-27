"use client";

// Междинна настройка „ДДС операции“ — като CONTROLISY: категория, код за
// колоната, допълнителен код, ставка, сметки и протокол. Редактират се името,
// сметките и протоколът; кодът/ставката се заключват след записа.

import { useCallback, useEffect, useState } from "react";
import { api, fetchAll } from "../lib/api";
import { useI18n } from "./I18nProvider";

interface Account {
  id: number;
  number: string;
  name: string;
}

interface Op {
  id: number;
  name: string;
  category: string;
  code: number;
  additional: number;
  rate: string;
  counterpart_account_id: number;
  vat_account_id: number;
  protocol: string;
}

export function SettingsVatOpsTab() {
  const { t } = useI18n();
  const [ops, setOps] = useState<Op[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [error, setError] = useState("");
  const [editing, setEditing] = useState<Op | null>(null);
  const [form, setForm] = useState({ name: "", counterpart_account_id: 0, vat_account_id: 0, protocol: "" });
  const [creating, setCreating] = useState(false);
  const [newOp, setNewOp] = useState({ name: "", category: "purchase", code: 1, additional: 0, rate: "20", counterpart_account_id: 0, vat_account_id: 0, protocol: "" });

  const load = useCallback(async () => {
    setError("");
    try {
      const [list, acc] = await Promise.all([
        api.get<{ items: Op[] }>("/v1/vat/operations"),
        fetchAll<Account>("/v1/accounts"),
      ]);
      setOps(list.items ?? []);
      setAccounts(acc);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const accLabel = (id: number) => {
    const a = accounts.find((x) => x.id === id);
    return a ? `${a.number} ${a.name}` : "—";
  };

  const openEdit = (o: Op) => {
    setEditing(o);
    setForm({ name: o.name, counterpart_account_id: o.counterpart_account_id, vat_account_id: o.vat_account_id, protocol: o.protocol });
  };

  const saveEdit = async () => {
    if (!editing) return;
    try {
      await api.patch(`/v1/vat/operations/${editing.id}`, form);
      setEditing(null);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const create = async () => {
    try {
      await api.post("/v1/vat/operations", newOp);
      setCreating(false);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const del = async (o: Op) => {
    if (!window.confirm(t("common.confirmDelete"))) return;
    try {
      await api.del(`/v1/vat/operations/${o.id}`);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const groups: { cat: string; label: string }[] = [
    { cat: "purchase", label: t("vatops.purchase") },
    { cat: "sales", label: t("vatops.sales") },
  ];

  return (
    <div className="card content">
      <div className="page-head">
        <h2 className="invoice-section-title">{t("vatops.title")}</h2>
        <button className="btn btn-primary" onClick={() => setCreating(true)}>{t("common.create")}</button>
      </div>
      <p className="muted">{t("vatops.hint")}</p>
      {error && <div className="error-text">{error}</div>}

      {groups.map((g) => (
        <div key={g.cat} style={{ marginTop: 12 }}>
          <h3>{g.label}</h3>
          <table className="table">
            <thead>
              <tr>
                <th>{t("vatops.name")}</th>
                <th>{t("vatops.code")}</th>
                <th>{t("vatops.additional")}</th>
                <th>{t("vatops.rate")}</th>
                <th>{t("vatops.counterpart")}</th>
                <th>{t("vatops.vat_account")}</th>
                <th>{t("vatops.protocol")}</th>
                <th>{t("common.actions")}</th>
              </tr>
            </thead>
            <tbody>
              {ops.filter((o) => o.category === g.cat).map((o) => (
                <tr key={o.id}>
                  <td>{o.name}</td>
                  <td>{o.code}</td>
                  <td>{o.additional}</td>
                  <td>{o.rate}%</td>
                  <td>{accLabel(o.counterpart_account_id)}</td>
                  <td>{accLabel(o.vat_account_id)}</td>
                  <td>{o.protocol || "—"}</td>
                  <td>
                    <div className="icon-actions">
                      <button className="btn btn-sm" onClick={() => openEdit(o)}>{t("common.edit")}</button>
                      <button className="btn btn-danger btn-sm" onClick={() => del(o)}>{t("common.delete")}</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}

      {editing && (
        <div className="modal-backdrop" onClick={() => setEditing(null)}>
          <div className="card modal" onClick={(e) => e.stopPropagation()}>
            <h2 className="modal-title">{t("common.edit")}</h2>
            <div className="form-grid">
              <div className="field">
                <label className="label">{t("vatops.name")}</label>
                <input className="input" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
              </div>
              <div className="field">
                <label className="label">{t("vatops.counterpart")}</label>
                <select className="select" value={form.counterpart_account_id} onChange={(e) => setForm({ ...form, counterpart_account_id: Number(e.target.value) })}>
                  <option value={0}>—</option>
                  {accounts.map((a) => <option key={a.id} value={a.id}>{a.number} {a.name}</option>)}
                </select>
              </div>
              <div className="field">
                <label className="label">{t("vatops.vat_account")}</label>
                <select className="select" value={form.vat_account_id} onChange={(e) => setForm({ ...form, vat_account_id: Number(e.target.value) })}>
                  <option value={0}>—</option>
                  {accounts.map((a) => <option key={a.id} value={a.id}>{a.number} {a.name}</option>)}
                </select>
              </div>
              <div className="field">
                <label className="label">{t("vatops.protocol")}</label>
                <input className="input" value={form.protocol} onChange={(e) => setForm({ ...form, protocol: e.target.value })} placeholder="чл. 117" />
              </div>
            </div>
            <div className="form-actions">
              <button className="btn" onClick={() => setEditing(null)}>{t("common.cancel")}</button>
              <button className="btn btn-primary" onClick={saveEdit}>{t("common.save")}</button>
            </div>
          </div>
        </div>
      )}

      {creating && (
        <div className="modal-backdrop" onClick={() => setCreating(false)}>
          <div className="card modal" onClick={(e) => e.stopPropagation()}>
            <h2 className="modal-title">{t("common.create")}</h2>
            <div className="form-grid">
              <div className="field">
                <label className="label">{t("vatops.name")}</label>
                <input className="input" value={newOp.name} onChange={(e) => setNewOp({ ...newOp, name: e.target.value })} />
              </div>
              <div className="field">
                <label className="label">{t("vatops.category")}</label>
                <select className="select" value={newOp.category} onChange={(e) => setNewOp({ ...newOp, category: e.target.value })}>
                  <option value="purchase">{t("vatops.purchase")}</option>
                  <option value="sales">{t("vatops.sales")}</option>
                </select>
              </div>
              <div className="field">
                <label className="label">{t("vatops.code")}</label>
                <input className="input" type="number" value={newOp.code} onChange={(e) => setNewOp({ ...newOp, code: Number(e.target.value) })} />
              </div>
              <div className="field">
                <label className="label">{t("vatops.additional")}</label>
                <input className="input" type="number" value={newOp.additional} onChange={(e) => setNewOp({ ...newOp, additional: Number(e.target.value) })} />
              </div>
              <div className="field">
                <label className="label">{t("vatops.rate")}</label>
                <input className="input" value={newOp.rate} onChange={(e) => setNewOp({ ...newOp, rate: e.target.value })} />
              </div>
              <div className="field">
                <label className="label">{t("vatops.protocol")}</label>
                <input className="input" value={newOp.protocol} onChange={(e) => setNewOp({ ...newOp, protocol: e.target.value })} />
              </div>
            </div>
            <div className="form-actions">
              <button className="btn" onClick={() => setCreating(false)}>{t("common.cancel")}</button>
              <button className="btn btn-primary" onClick={create}>{t("common.save")}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
