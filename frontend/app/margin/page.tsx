"use client";

// Режим на маржа (чл.143–151 ЗДДС, чл.90 ППЗДС): месечен протокол за стоки втора употреба.

import { useCallback, useEffect, useState } from "react";
import { RequireAuth } from "../../components/RequireAuth";
import { useI18n } from "../../components/I18nProvider";
import { api } from "../../lib/api";

interface MLine { product_id: number; purchase_price: string; sale_price: string; margin: string; base: string; vat: string; export: number }
interface Preview { lines: MLine[]; errors: string[]; total_base: string; total_vat: string }
interface Protocol { id: number; month: string; number: string; status: string; total_base: string; total_vat: string }

function Inner() {
  const { t } = useI18n();
  const [month, setMonth] = useState(new Date().toISOString().slice(0, 7));
  const [preview, setPreview] = useState<Preview | null>(null);
  const [protocols, setProtocols] = useState<Protocol[]>([]);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    try { setProtocols((await api.get<{ items: Protocol[] }>("/v1/vat/margin")).items ?? []); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const doPreview = async () => {
    setError("");
    try { setPreview(await api.get<Preview>(`/v1/vat/margin/preview?month=${month}`)); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  const create = async () => {
    setError("");
    try { await api.post("/v1/vat/margin", { month }); setPreview(null); await load(); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  const del = async (p: Protocol) => {
    if (!window.confirm(t("common.confirmDelete"))) return;
    try { await api.del(`/v1/vat/margin/${p.id}`); await load(); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  return (
    <div>
      <div className="page-head"><h1 className="page-title">{t("margin.title")}</h1></div>
      <p className="muted">{t("margin.hint")}</p>
      {error && <div className="error-text">{error}</div>}
      <div className="card content">
        <div className="form-grid">
          <div className="field"><label className="label">{t("margin.month")}</label><input className="input" type="month" value={month} onChange={(e) => setMonth(e.target.value)} /></div>
          <div className="field"><label className="label">&nbsp;</label><button className="btn" onClick={doPreview}>{t("margin.preview")}</button></div>
        </div>
        {preview && (
          <div style={{ marginTop: 12 }}>
            {preview.errors.length > 0 && preview.errors.map((e, i) => <div key={i} className="error-text">{e}</div>)}
            <table className="table">
              <thead><tr><th>{t("margin.product")}</th><th>{t("margin.purchase")}</th><th>{t("margin.sale")}</th><th>{t("margin.margin")}</th><th>{t("margin.base")}</th><th>{t("margin.vat")}</th></tr></thead>
              <tbody>
                {preview.lines.map((l, i) => (
                  <tr key={i}><td>{l.product_id}</td><td className="num">{l.purchase_price}</td><td className="num">{l.sale_price}</td><td className="num">{l.margin}</td><td className="num">{l.base}</td><td className="num">{l.vat}</td></tr>
                ))}
              </tbody>
            </table>
            <div className="content">{t("margin.base")}: {preview.total_base} · {t("margin.vat")}: {preview.total_vat}</div>
            {preview.errors.length === 0 && <div className="form-actions"><button className="btn btn-primary" onClick={create}>{t("margin.create")}</button></div>}
          </div>
        )}
      </div>
      <div className="card" style={{ marginTop: 12 }}>
        <table className="table">
          <thead><tr><th>{t("margin.number")}</th><th>{t("margin.month")}</th><th>{t("margin.base")}</th><th>{t("margin.vat")}</th><th></th></tr></thead>
          <tbody>
            {protocols.map((p) => (
              <tr key={p.id}><td>{p.number}</td><td>{p.month}</td><td className="num">{p.total_base}</td><td className="num">{p.total_vat}</td>
                <td><button className="btn btn-danger btn-sm" onClick={() => del(p)}>{t("common.delete")}</button></td></tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export default function MarginPage() {
  return <RequireAuth><Inner /></RequireAuth>;
}
