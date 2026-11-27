"use client";

// OSS ДДС ставки по държави с аналитични сметки и история (начална дата).
// Нова ставка = копиран ред с нова начална дата.

import { useCallback, useEffect, useState } from "react";
import { api } from "../lib/api";
import { useI18n } from "./I18nProvider";
import { OSS_COUNTRIES } from "../lib/invoice";

interface Rate {
  id: number; country: string; account_id: number; account_number: string;
  rate: string; rate_kind: string; supply_kind: string; valid_from: string;
}

export function OssRatesTab() {
  const { t } = useI18n();
  const [rates, setRates] = useState<Rate[]>([]);
  const [error, setError] = useState("");
  const [form, setForm] = useState({ country: "DE", account_number: "453401", rate: "19", rate_kind: "standard", supply_kind: "goods", valid_from: new Date().toISOString().slice(0, 10) });

  const load = useCallback(async () => {
    try {
      setRates((await api.get<{ items: Rate[] }>("/v1/oss/rates")).items ?? []);
    } catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const add = async () => {
    try { await api.post("/v1/oss/rates", form); await load(); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  const copy = async (r: Rate) => {
    const d = window.prompt(t("ossr.new_date"), new Date().toISOString().slice(0, 10));
    if (!d) return;
    const rate = window.prompt(t("ossr.new_rate"), r.rate) ?? r.rate;
    try { await api.post(`/v1/oss/rates/${r.id}/copy`, { valid_from: d, rate }); await load(); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  const del = async (r: Rate) => {
    if (!window.confirm(t("common.confirmDelete"))) return;
    try { await api.del(`/v1/oss/rates/${r.id}`); await load(); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  return (
    <div className="card content">
      <div className="page-head"><h2 className="invoice-section-title">{t("ossr.title")}</h2></div>
      <p className="muted">{t("ossr.hint")}</p>
      {error && <div className="error-text">{error}</div>}
      <div className="form-grid">
        <div className="field"><label className="label">{t("oss.country")}</label>
          <select className="select" value={form.country} onChange={(e) => setForm({ ...form, country: e.target.value })}>{OSS_COUNTRIES.map((c) => <option key={c}>{c}</option>)}</select></div>
        <div className="field"><label className="label">{t("ossr.account")}</label><input className="input" value={form.account_number} onChange={(e) => setForm({ ...form, account_number: e.target.value })} /></div>
        <div className="field"><label className="label">{t("oss.rate")}</label><input className="input" value={form.rate} onChange={(e) => setForm({ ...form, rate: e.target.value })} /></div>
        <div className="field"><label className="label">{t("oss.rate_kind")}</label>
          <select className="select" value={form.rate_kind} onChange={(e) => setForm({ ...form, rate_kind: e.target.value })}><option value="standard">{t("oss.standard")}</option><option value="reduced">{t("oss.reduced")}</option></select></div>
        <div className="field"><label className="label">{t("oss.supply")}</label>
          <select className="select" value={form.supply_kind} onChange={(e) => setForm({ ...form, supply_kind: e.target.value })}><option value="goods">{t("oss.goods")}</option><option value="services">{t("oss.services")}</option></select></div>
        <div className="field"><label className="label">{t("ossr.from")}</label><input className="input" type="date" value={form.valid_from} onChange={(e) => setForm({ ...form, valid_from: e.target.value })} /></div>
      </div>
      <div className="form-actions"><button className="btn btn-primary" onClick={add}>{t("ossr.add")}</button></div>

      <table className="table" style={{ marginTop: 12 }}>
        <thead><tr><th>{t("oss.country")}</th><th>{t("ossr.account")}</th><th>{t("oss.rate")}</th><th>{t("oss.rate_kind")}</th><th>{t("oss.supply")}</th><th>{t("ossr.from")}</th><th></th></tr></thead>
        <tbody>
          {rates.map((r) => (
            <tr key={r.id}>
              <td>{r.country}</td><td>{r.account_number}</td><td>{r.rate}%</td><td>{r.rate_kind}</td><td>{r.supply_kind}</td><td>{r.valid_from}</td>
              <td><div className="icon-actions">
                <button className="btn btn-sm" onClick={() => copy(r)}>{t("ossr.copy")}</button>
                <button className="btn btn-danger btn-sm" onClick={() => del(r)}>{t("common.delete")}</button>
              </div></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
