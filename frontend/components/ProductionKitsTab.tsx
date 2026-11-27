"use client";

// Комплектоване на стоки (304) и продукция (303) — пакет по рецепта, без
// производствени разходи: стойността на съставките се прехвърля към комплекта.

import { useCallback, useEffect, useState } from "react";
import { api, fetchAll } from "../lib/api";
import { useI18n } from "./I18nProvider";
import { CompanyLocation, fetchCompanyLocations } from "../lib/locations";

interface Product { id: number; name: string; inventory_account_id: number }
interface Account { id: number; number: string }
interface KLine { product_id: number; quantity: string }
interface Kit {
  id: number; number: string; doc_date: string; status: string; kind: string;
  output_product_id: number; quantity: string; location_id: number; cost: string; lines?: KLine[];
}

export function ProductionKitsTab() {
  const { t } = useI18n();
  const [kits, setKits] = useState<Kit[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [locations, setLocations] = useState<CompanyLocation[]>([]);
  const [error, setError] = useState("");
  const [editing, setEditing] = useState<Kit | null>(null);
  const [kind, setKind] = useState("kit_goods");
  const [output, setOutput] = useState(0);
  const [qty, setQty] = useState("1");
  const [loc, setLoc] = useState(0);
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [lines, setLines] = useState<KLine[]>([]);

  const load = useCallback(async () => {
    try {
      const [k, p, a, l] = await Promise.all([
        api.get<{ items: Kit[] }>("/v1/kits"),
        fetchAll<Product>("/v1/products"),
        fetchAll<Account>("/v1/accounts"),
        fetchCompanyLocations(),
      ]);
      setKits(k.items ?? []);
      setProducts(p);
      setAccounts(a);
      setLocations(l);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const accNum = (id: number) => accounts.find((a) => a.id === id)?.number ?? "";
  const isKitOutput = (p: Product) => (kind === "kit_production" ? accNum(p.inventory_account_id).startsWith("303") : accNum(p.inventory_account_id).startsWith("304"));

  const open = async (k: Kit) => {
    const full = await api.get<Kit>(`/v1/kits/${k.id}`);
    setEditing(full);
    setKind(full.kind); setOutput(full.output_product_id); setQty(full.quantity); setLoc(full.location_id); setDate(full.doc_date);
    setLines(full.lines ?? []);
  };

  const startNew = () => {
    setEditing({ id: 0, number: "", doc_date: date, status: "draft", kind, output_product_id: 0, quantity: "1", location_id: locations[0]?.id ?? 0, cost: "0" });
    setOutput(0); setQty("1"); setLoc(locations[0]?.id ?? 0); setLines([{ product_id: 0, quantity: "1" }]);
  };

  const save = async () => {
    try {
      const body = { doc_date: date, kind, output_product_id: output, quantity: qty, location_id: loc, lines };
      const k = editing && editing.id > 0
        ? await api.patch<Kit>(`/v1/kits/${editing.id}`, body)
        : await api.post<Kit>("/v1/kits", body);
      setEditing(k);
      await load();
    } catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  const act = async (path: string) => {
    try { setError(""); await api.post(path, {}); await load(); if (editing && editing.id > 0) await open(editing); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  const remove = async (id: number) => {
    if (!window.confirm(t("common.confirmDelete"))) return;
    try { await api.del(`/v1/kits/${id}`); setEditing(null); await load(); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  return (
    <div className="card content">
      <div className="page-head">
        <h2 className="invoice-section-title">{t("kit.title")}</h2>
        {!editing && <button className="btn btn-primary" onClick={startNew}>{t("kit.new")}</button>}
      </div>
      {error && <div className="error-text">{error}</div>}

      {!editing && (
        <table className="table">
          <thead><tr><th>{t("kit.number")}</th><th>{t("kit.date")}</th><th>{t("kit.kind")}</th><th>{t("kit.cost")}</th><th>{t("kit.status")}</th><th>{t("common.actions")}</th></tr></thead>
          <tbody>
            {kits.map((k) => (
              <tr key={k.id}>
                <td><button className="btn-ghost" onClick={() => open(k)}>{k.number}</button></td>
                <td>{k.doc_date}</td>
                <td>{k.kind === "kit_production" ? t("kit.production") : t("kit.goods")}</td>
                <td className="num">{k.cost}</td>
                <td>{k.status}</td>
                <td><div className="icon-actions">
                  {k.status === "draft" && <button className="btn btn-sm" onClick={() => act(`/v1/kits/${k.id}/confirm`)}>{t("kit.confirm")}</button>}
                  {k.status === "completed" && <button className="btn btn-sm" onClick={() => act(`/v1/kits/${k.id}/unpost`)}>{t("kit.unpost")}</button>}
                  {k.status === "draft" && <button className="btn btn-danger btn-sm" onClick={() => remove(k.id)}>{t("common.delete")}</button>}
                </div></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {editing && (
        <div>
          <div className="form-grid">
            <div className="field"><label className="label">{t("kit.kind")}</label>
              <select className="select" value={kind} disabled={editing.id > 0} onChange={(e) => setKind(e.target.value)}>
                <option value="kit_goods">{t("kit.goods")}</option>
                <option value="kit_production">{t("kit.production")}</option>
              </select>
            </div>
            <div className="field"><label className="label">{t("kit.output")}</label>
              <select className="select" value={output} onChange={(e) => setOutput(Number(e.target.value))}>
                <option value={0}>—</option>
                {products.filter(isKitOutput).map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
              </select>
            </div>
            <div className="field"><label className="label">{t("kit.qty")}</label><input className="input" value={qty} onChange={(e) => setQty(e.target.value)} /></div>
            <div className="field"><label className="label">{t("kit.date")}</label><input className="input" type="date" value={date} onChange={(e) => setDate(e.target.value)} /></div>
            <div className="field"><label className="label">{t("kit.location")}</label>
              <select className="select" value={loc} onChange={(e) => setLoc(Number(e.target.value))}>
                {locations.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
              </select>
            </div>
          </div>

          <table className="table" style={{ marginTop: 8 }}>
            <thead><tr><th>{t("kit.component")}</th><th>{t("kit.qty")}</th><th></th></tr></thead>
            <tbody>
              {lines.map((l, i) => (
                <tr key={i}>
                  <td><select className="select" value={l.product_id} onChange={(e) => setLines((p) => p.map((x, j) => (j === i ? { ...x, product_id: Number(e.target.value) } : x)))}>
                    <option value={0}>—</option>
                    {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                  </select></td>
                  <td><input className="input" style={{ maxWidth: 90 }} value={l.quantity} onChange={(e) => setLines((p) => p.map((x, j) => (j === i ? { ...x, quantity: e.target.value } : x)))} /></td>
                  <td><button className="btn btn-danger btn-sm" onClick={() => setLines((p) => p.filter((_, j) => j !== i))}>✕</button></td>
                </tr>
              ))}
            </tbody>
          </table>
          <button className="btn btn-sm" onClick={() => setLines((p) => [...p, { product_id: 0, quantity: "1" }])}>+ {t("kit.add")}</button>

          <div className="form-actions">
            <button className="btn" onClick={() => setEditing(null)}>{t("common.cancel")}</button>
            {editing.status === "draft" && <button className="btn" onClick={save}>{t("common.save")}</button>}
            {editing.id > 0 && editing.status === "draft" && <button className="btn btn-primary" onClick={() => act(`/v1/kits/${editing.id}/confirm`)}>{t("kit.confirm")}</button>}
          </div>
        </div>
      )}
    </div>
  );
}
