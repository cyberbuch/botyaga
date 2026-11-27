"use client";

// Месечна производствена карта (фактическо производство) — ръчен подход:
// материали 601, преки 602–609, дял общи, незавършено производство, разпределение
// по количество×коефициент или ръчна сума.

import { useCallback, useEffect, useState } from "react";
import { api, fetchAll } from "../lib/api";
import { useI18n } from "./I18nProvider";
import { DocExtras } from "./DocExtras";

interface Account { id: number; number: string; name: string }
interface Product { id: number; name: string }
interface CProduct { id?: number; product_id: number; name?: string; quantity: string; coefficient: string; manual_amount: string; cost?: string }
interface Card {
  id: number; number: string; month: string; status: string;
  materials_account_id: number; production_account_id: number;
  direct_accounts: number[]; common_accounts: number[];
  common_share_percent: string; wip_end_mode: string; wip_end_value: string;
  products?: CProduct[];
  preview?: { materials: string; common_share: string; wip_begin: string; wip_end: string; total: string; errors: string[] };
}

export function ProductionCardsTab() {
  const { t } = useI18n();
  const [cards, setCards] = useState<Card[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [error, setError] = useState("");
  const [editing, setEditing] = useState<Card | null>(null);
  const [month, setMonth] = useState(new Date().toISOString().slice(0, 7));
  const [rows, setRows] = useState<CProduct[]>([]);

  const load = useCallback(async () => {
    try {
      const [c, a, p] = await Promise.all([
        api.get<{ items: Card[] }>("/v1/production-cards"),
        fetchAll<Account>("/v1/accounts"),
        fetchAll<Product>("/v1/products"),
      ]);
      setCards(c.items ?? []);
      setAccounts(a);
      setProducts(p);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  useEffect(() => { load(); }, [load]);


  const open = async (c: Card) => {
    const full = await api.get<Card>(`/v1/production-cards/${c.id}`);
    setEditing(full);
    setRows(full.products ?? []);
  };

  const create = async () => {
    try {
      const c = await api.post<Card>("/v1/production-cards", { month, products: rows.map((r) => ({ product_id: r.product_id, quantity: r.quantity, coefficient: r.coefficient, manual_amount: r.manual_amount })) });
      setEditing(c); setRows(c.products ?? []);
      await load();
    } catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  const save = async () => {
    if (!editing) return;
    try {
      const c = await api.patch<Card>(`/v1/production-cards/${editing.id}`, {
        direct_accounts: editing.direct_accounts, common_accounts: editing.common_accounts,
        common_share_percent: editing.common_share_percent, wip_end_mode: editing.wip_end_mode, wip_end_value: editing.wip_end_value,
        products: rows.map((r) => ({ product_id: r.product_id, quantity: r.quantity, coefficient: r.coefficient, manual_amount: r.manual_amount })),
      });
      setEditing(c); setRows(c.products ?? []);
      await load();
    } catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  const act = async (path: string) => {
    try { setError(""); await api.post(path, {}); await load(); if (editing) await open(editing); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  const toggle = (key: "direct_accounts" | "common_accounts", id: number) => {
    if (!editing) return;
    const cur = editing[key];
    setEditing({ ...editing, [key]: cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id] });
  };

  const setRow = (i: number, patch: Partial<CProduct>) => setRows((p) => p.map((r, x) => (x === i ? { ...r, ...patch } : r)));

  return (
    <div className="card content">
      <div className="page-head">
        <h2 className="invoice-section-title">{t("pc.title")}</h2>
        {!editing && <button className="btn btn-primary" onClick={() => { setEditing({ id: 0, number: "", month, status: "draft", materials_account_id: 0, production_account_id: 0, direct_accounts: [], common_accounts: [], common_share_percent: "100", wip_end_mode: "amount", wip_end_value: "0" }); setRows([{ product_id: products[0]?.id ?? 0, quantity: "1", coefficient: "1", manual_amount: "" }]); }}>{t("pc.new")}</button>}
      </div>
      {error && <div className="error-text">{error}</div>}

      {!editing && (
        <table className="table">
          <thead><tr><th>{t("pc.number")}</th><th>{t("pc.month")}</th><th>{t("pc.status")}</th><th>{t("common.actions")}</th></tr></thead>
          <tbody>
            {cards.map((c) => (
              <tr key={c.id}>
                <td><button className="btn-ghost" onClick={() => open(c)}>{c.number}</button></td>
                <td>{c.month}</td>
                <td>{c.status}</td>
                <td><div className="icon-actions">
                  {c.status === "draft" && <button className="btn btn-sm" onClick={() => act(`/v1/production-cards/${c.id}/confirm`)}>{t("pc.confirm")}</button>}
                  {c.status === "confirmed" && <button className="btn btn-sm" onClick={() => act(`/v1/production-cards/${c.id}/unpost`)}>{t("pc.unpost")}</button>}
                </div></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {editing && (
        <div>
          <div className="form-grid">
            <div className="field"><label className="label">{t("pc.month")}</label><input className="input" type="month" value={editing.month || month} onChange={(e) => setMonth(e.target.value)} disabled={editing.id > 0} /></div>
            <div className="field"><label className="label">{t("pc.share")}</label><input className="input" value={editing.common_share_percent} onChange={(e) => setEditing({ ...editing, common_share_percent: e.target.value })} /></div>
            <div className="field"><label className="label">{t("pc.wip_mode")}</label><select className="select" value={editing.wip_end_mode} onChange={(e) => setEditing({ ...editing, wip_end_mode: e.target.value })}><option value="amount">{t("pc.amount")}</option><option value="percent">{t("pc.percent")}</option></select></div>
            <div className="field"><label className="label">{t("pc.wip_end")}</label><input className="input" value={editing.wip_end_value} onChange={(e) => setEditing({ ...editing, wip_end_value: e.target.value })} /></div>
          </div>

          <div className="form-grid" style={{ marginTop: 8 }}>
            <div className="field"><label className="label">{t("pc.direct")}</label>
              <div>{accounts.filter((a) => /^60[2-9]/.test(a.number)).map((a) => (
                <label key={a.id} style={{ display: "block" }}><input type="checkbox" checked={editing.direct_accounts.includes(a.id)} onChange={() => toggle("direct_accounts", a.id)} /> {a.number} {a.name}</label>
              ))}</div>
            </div>
            <div className="field"><label className="label">{t("pc.common")}</label>
              <div>{accounts.filter((a) => /^60[2-9]/.test(a.number)).map((a) => (
                <label key={a.id} style={{ display: "block" }}><input type="checkbox" checked={editing.common_accounts.includes(a.id)} onChange={() => toggle("common_accounts", a.id)} /> {a.number} {a.name}</label>
              ))}</div>
            </div>
          </div>

          <table className="table" style={{ marginTop: 8 }}>
            <thead><tr><th>{t("pc.product")}</th><th>{t("pc.qty")}</th><th>{t("pc.coef")}</th><th>{t("pc.manual")}</th><th>{t("pc.cost")}</th><th></th></tr></thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={i}>
                  <td><select className="select" value={r.product_id} onChange={(e) => setRow(i, { product_id: Number(e.target.value) })}>{products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></td>
                  <td><input className="input" style={{ maxWidth: 80 }} value={r.quantity} onChange={(e) => setRow(i, { quantity: e.target.value })} /></td>
                  <td><input className="input" style={{ maxWidth: 70 }} value={r.coefficient} onChange={(e) => setRow(i, { coefficient: e.target.value })} /></td>
                  <td><input className="input" style={{ maxWidth: 90 }} value={r.manual_amount} onChange={(e) => setRow(i, { manual_amount: e.target.value })} /></td>
                  <td className="num">{r.cost ?? "—"}</td>
                  <td><button className="btn btn-danger btn-sm" onClick={() => setRows((p) => p.filter((_, x) => x !== i))}>✕</button></td>
                </tr>
              ))}
            </tbody>
          </table>
          <button className="btn btn-sm" onClick={() => setRows((p) => [...p, { product_id: products[0]?.id ?? 0, quantity: "1", coefficient: "1", manual_amount: "" }])}>+ {t("pc.add")}</button>

          {editing.preview && (
            <div className="content" style={{ marginTop: 8 }}>
              {t("pc.materials")}: {editing.preview.materials} · {t("pc.common_share")}: {editing.preview.common_share} · {t("pc.wip_begin")}: {editing.preview.wip_begin} · {t("pc.wip_end")}: {editing.preview.wip_end} · <b>{t("pc.total")}: {editing.preview.total}</b>
              {editing.preview.errors.map((e, i) => <div key={i} className="error-text">{e}</div>)}
            </div>
          )}

          <div className="form-actions">
            <button className="btn" onClick={() => setEditing(null)}>{t("common.cancel")}</button>
            {editing.id === 0 && <button className="btn btn-primary" onClick={create}>{t("common.save")}</button>}
            {editing.id > 0 && editing.status === "draft" && <button className="btn" onClick={save}>{t("common.save")}</button>}
            {editing.id > 0 && editing.status === "draft" && <button className="btn btn-primary" onClick={() => act(`/v1/production-cards/${editing.id}/confirm`)}>{t("pc.confirm")}</button>}
          </div>
          {editing.id > 0 && <DocExtras docType="production_card" docId={editing.id} pdfPath={`/v1/production-cards/${editing.id}/pdf`} />}
        </div>
      )}
    </div>
  );
}
