"use client";

// OSS режим в Съюза: отчети по чл.119 ал.5, месечно деклариране (вид 81) и
// тримесечна справка-декларация по чл.159 (Приложение 32). Като CONTROLISY.

import { useCallback, useEffect, useState } from "react";
import { RequireAuth } from "../../components/RequireAuth";
import { useI18n } from "../../components/I18nProvider";
import { api } from "../../lib/api";
import { OSS_COUNTRIES } from "../../lib/invoice";

interface Line {
  id?: number;
  account: string;
  country: string;
  supply_kind: string;
  rate_kind: string;
  rate: string;
  gross: string;
  currency: string;
  base_eur?: string;
  vat_eur?: string;
}
interface Report {
  id: number;
  number: string;
  month: string;
  doc_date: string;
  status: string;
  lines?: Line[];
}
interface Quarter {
  status: string;
  submitted_at?: string;
  data: {
    part2a: Agg[];
    part2b: Agg[];
    part3: Agg[];
    part4: { country: string; vat_eur: string }[];
    part5_total: string;
  };
}
interface Agg {
  country: string;
  supply_kind: string;
  rate_kind: string;
  rate: string;
  base_eur: string;
  vat_eur: string;
}

const emptyLine = (): Line => ({ account: "702", country: "DE", supply_kind: "goods", rate_kind: "standard", rate: "19", gross: "0", currency: "EUR" });

function Inner() {
  const { t } = useI18n();
  const [tab, setTab] = useState<"reports" | "month" | "quarter">("reports");
  const [reports, setReports] = useState<Report[]>([]);
  const [error, setError] = useState("");
  const [editing, setEditing] = useState<Report | null>(null);
  const [month, setMonth] = useState(new Date().toISOString().slice(0, 7));
  const [lines, setLines] = useState<Line[]>([emptyLine()]);
  const [preview, setPreview] = useState<null | { errors: { error: string }[]; total_base: string; total_vat: string }>(null);
  const [monthInfo, setMonthInfo] = useState<null | { base: string; declared: boolean }>(null);
  const [year, setYear] = useState(new Date().getFullYear());
  const [quarter, setQuarter] = useState(Math.floor(new Date().getMonth() / 3) + 1);
  const [qdata, setQdata] = useState<Quarter | null>(null);
  const [submitNo, setSubmitNo] = useState("");

  const loadReports = useCallback(async () => {
    try {
      setReports((await api.get<{ items: Report[] }>("/v1/oss/reports")).items ?? []);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  useEffect(() => {
    loadReports();
  }, [loadReports]);

  const loadMonth = async () => {
    try {
      setMonthInfo(await api.get(`/v1/oss/month/${month}`));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const loadQuarter = async () => {
    try {
      setQdata(await api.get(`/v1/oss/quarter/${year}/${quarter}`));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const saveReport = async () => {
    try {
      const body = { month, lines };
      const r = editing
        ? await api.patch<Report>(`/v1/oss/reports/${editing.id}`, body)
        : await api.post<Report>("/v1/oss/reports", body);
      setEditing(r);
      setLines(r.lines ?? [emptyLine()]);
      await loadReports();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const doPreview = async () => {
    if (!editing) return;
    setPreview(await api.get(`/v1/oss/reports/${editing.id}/preview`));
  };

  const act = async (path: string, method: "post" | "delete" = "post") => {
    try {
      setError("");
      if (method === "post") await api.post(path, {});
      else await api.del(path);
      await loadReports();
      if (editing) setEditing(await api.get(`/v1/oss/reports/${editing.id}`));
      if (tab === "month") await loadMonth();
      if (tab === "quarter") await loadQuarter();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const setLine = (i: number, patch: Partial<Line>) =>
    setLines((prev) => prev.map((l, idx) => (idx === i ? { ...l, ...patch } : l)));

  return (
    <div>
      <div className="page-head">
        <h1 className="page-title">{t("oss.title")}</h1>
      </div>
      <div className="tabs">
        {(["reports", "month", "quarter"] as const).map((k) => (
          <button key={k} className={`tab${tab === k ? " tab-active" : ""}`} onClick={() => setTab(k)}>
            {t(`oss.tab.${k}`)}
          </button>
        ))}
      </div>
      {error && <div className="error-text">{error}</div>}

      {tab === "reports" && !editing && (
        <div className="card content">
          <button className="btn btn-primary" onClick={() => { setEditing(null); setLines([emptyLine()]); setPreview(null); setEditing({ id: 0, number: "", month, doc_date: "", status: "draft" }); }}>
            {t("oss.new_report")}
          </button>
          <table className="table" style={{ marginTop: 12 }}>
            <thead>
              <tr><th>{t("oss.number")}</th><th>{t("oss.month")}</th><th>{t("oss.status")}</th><th>{t("common.actions")}</th></tr>
            </thead>
            <tbody>
              {reports.map((r) => (
                <tr key={r.id}>
                  <td><button className="btn-ghost" onClick={async () => { const full = await api.get<Report>(`/v1/oss/reports/${r.id}`); setEditing(full); setLines(full.lines ?? []); setPreview(null); }}>{r.number}</button></td>
                  <td>{r.month}</td>
                  <td>{r.status}</td>
                  <td>
                    <div className="icon-actions">
                      {r.status === "draft" && <button className="btn btn-sm" onClick={() => act(`/v1/oss/reports/${r.id}/confirm`)}>{t("oss.confirm")}</button>}
                      {r.status === "active" && <button className="btn btn-sm" onClick={() => act(`/v1/oss/reports/${r.id}/unpost`)}>{t("oss.unpost")}</button>}
                      {r.status === "draft" && <button className="btn btn-danger btn-sm" onClick={() => act(`/v1/oss/reports/${r.id}`, "delete")}>{t("common.delete")}</button>}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === "reports" && editing && (
        <div className="card content">
          <div className="form-grid">
            <div className="field">
              <label className="label">{t("oss.month")}</label>
              <input className="input" type="month" value={month} onChange={(e) => setMonth(e.target.value)} disabled={editing.status !== "draft"} />
            </div>
          </div>
          <table className="table" style={{ marginTop: 12 }}>
            <thead>
              <tr><th>{t("oss.account")}</th><th>{t("oss.country")}</th><th>{t("oss.supply")}</th><th>{t("oss.rate_kind")}</th><th>{t("oss.rate")}</th><th>{t("oss.gross")}</th><th>{t("oss.currency")}</th><th></th></tr>
            </thead>
            <tbody>
              {lines.map((l, i) => (
                <tr key={i}>
                  <td><select className="select" value={l.account} onChange={(e) => setLine(i, { account: e.target.value })}>{["701", "702", "703", "706", "709"].map((a) => <option key={a}>{a}</option>)}</select></td>
                  <td><select className="select" value={l.country} onChange={(e) => setLine(i, { country: e.target.value })}>{OSS_COUNTRIES.map((c) => <option key={c}>{c}</option>)}</select></td>
                  <td><select className="select" value={l.supply_kind} onChange={(e) => setLine(i, { supply_kind: e.target.value })}><option value="goods">{t("oss.goods")}</option><option value="services">{t("oss.services")}</option></select></td>
                  <td><select className="select" value={l.rate_kind} onChange={(e) => setLine(i, { rate_kind: e.target.value })}><option value="standard">{t("oss.standard")}</option><option value="reduced">{t("oss.reduced")}</option></select></td>
                  <td><input className="input" style={{ maxWidth: 70 }} value={l.rate} onChange={(e) => setLine(i, { rate: e.target.value })} /></td>
                  <td><input className="input" style={{ maxWidth: 100 }} value={l.gross} onChange={(e) => setLine(i, { gross: e.target.value })} /></td>
                  <td><input className="input" style={{ maxWidth: 70 }} value={l.currency} onChange={(e) => setLine(i, { currency: e.target.value })} /></td>
                  <td><button className="btn btn-danger btn-sm" onClick={() => setLines((p) => p.filter((_, x) => x !== i))}>✕</button></td>
                </tr>
              ))}
            </tbody>
          </table>
          <button className="btn btn-sm" onClick={() => setLines((p) => [...p, emptyLine()])}>+ {t("oss.add_row")}</button>
          {preview && (
            <div style={{ marginTop: 12 }}>
              {preview.errors.length > 0 ? (
                preview.errors.map((e, i) => <div key={i} className="error-text">{e.error}</div>)
              ) : (
                <div className="content">{t("oss.preview_ok")}: {t("oss.base")} {preview.total_base} · {t("oss.vat")} {preview.total_vat}</div>
              )}
            </div>
          )}
          <div className="form-actions">
            <button className="btn" onClick={() => { setEditing(null); setPreview(null); }}>{t("common.cancel")}</button>
            {editing.status === "draft" && <button className="btn" onClick={saveReport}>{t("common.save")}</button>}
            {editing.id > 0 && <button className="btn" onClick={doPreview}>{t("oss.preview")}</button>}
            {editing.id > 0 && editing.status === "draft" && <button className="btn btn-primary" onClick={() => act(`/v1/oss/reports/${editing.id}/confirm`)}>{t("oss.confirm")}</button>}
          </div>
        </div>
      )}

      {tab === "month" && (
        <div className="card content">
          <div className="form-grid">
            <div className="field">
              <label className="label">{t("oss.month")}</label>
              <input className="input" type="month" value={month} onChange={(e) => setMonth(e.target.value)} />
            </div>
            <div className="field">
              <label className="label">&nbsp;</label>
              <button className="btn" onClick={loadMonth}>{t("oss.show")}</button>
            </div>
          </div>
          {monthInfo && (
            <div style={{ marginTop: 12 }}>
              <div className="content">{t("oss.month_base")}: {monthInfo.base}</div>
              <div className="content">{monthInfo.declared ? t("oss.declared") : t("oss.not_declared")}</div>
              <div className="form-actions">
                {!monthInfo.declared && <button className="btn btn-primary" onClick={() => act(`/v1/oss/month/${month}/declare`)}>{t("oss.declare")}</button>}
                {monthInfo.declared && <button className="btn btn-danger" onClick={() => act(`/v1/oss/month/${month}/declare`, "delete")}>{t("oss.undeclare")}</button>}
              </div>
            </div>
          )}
        </div>
      )}

      {tab === "quarter" && (
        <div className="card content">
          <div className="form-grid">
            <div className="field"><label className="label">{t("oss.year")}</label><input className="input" type="number" value={year} onChange={(e) => setYear(Number(e.target.value))} /></div>
            <div className="field"><label className="label">{t("oss.quarter")}</label><select className="select" value={quarter} onChange={(e) => setQuarter(Number(e.target.value))}>{[1, 2, 3, 4].map((q) => <option key={q} value={q}>{q}</option>)}</select></div>
            <div className="field"><label className="label">&nbsp;</label><button className="btn" onClick={loadQuarter}>{t("oss.show")}</button></div>
          </div>
          {qdata && (
            <div style={{ marginTop: 12 }}>
              <h3>{t("oss.part2b")}</h3>
              <AggTable rows={qdata.data.part2b} t={t} />
              <h3>{t("oss.part2a")}</h3>
              <AggTable rows={qdata.data.part2a} t={t} />
              <h3>{t("oss.part3")}</h3>
              <AggTable rows={qdata.data.part3} t={t} />
              <h3>{t("oss.part4")}</h3>
              <table className="table"><tbody>{qdata.data.part4.map((c) => <tr key={c.country}><td>{c.country}</td><td className="num">{c.vat_eur}</td></tr>)}</tbody></table>
              <div className="content" style={{ fontWeight: 700 }}>{t("oss.part5")}: {qdata.data.part5_total} EUR</div>
              <div className="content muted">{t("oss.status")}: {qdata.status}{qdata.submitted_at ? ` · ${qdata.submitted_at}` : ""}</div>
              <div className="form-actions">
                <button className="btn" onClick={() => act(`/v1/oss/quarter/${year}/${quarter}/freeze`)}>{t("oss.freeze")}</button>
                {qdata.status === "final" && (
                  <>
                    <input className="input" style={{ maxWidth: 140 }} placeholder={t("oss.submission_no")} value={submitNo} onChange={(e) => setSubmitNo(e.target.value)} />
                    <button className="btn btn-primary" onClick={async () => { await api.post(`/v1/oss/quarter/${year}/${quarter}/submit`, { date: new Date().toISOString().slice(0, 10), number: submitNo }); await loadQuarter(); }}>{t("oss.submit")}</button>
                  </>
                )}
                {qdata.status === "submitted" && <button className="btn" onClick={() => act(`/v1/oss/quarter/${year}/${quarter}/unsubmit`)}>{t("oss.unsubmit")}</button>}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function AggTable({ rows, t }: { rows: Agg[]; t: (k: string) => string }) {
  return (
    <table className="table">
      <thead><tr><th>{t("oss.country")}</th><th>{t("oss.supply")}</th><th>{t("oss.rate")}</th><th>{t("oss.base")}</th><th>{t("oss.vat")}</th></tr></thead>
      <tbody>
        {rows.map((r, i) => (
          <tr key={i}><td>{r.country}</td><td>{r.supply_kind}</td><td>{r.rate}%</td><td className="num">{r.base_eur}</td><td className="num">{r.vat_eur}</td></tr>
        ))}
      </tbody>
    </table>
  );
}

export default function OssPage() {
  return (
    <RequireAuth>
      <Inner />
    </RequireAuth>
  );
}
