"use client";

// PDF протокол + прикачени файлове към документ (както CONTROLISY).

import { useCallback, useEffect, useRef, useState } from "react";
import { api, getToken } from "../lib/api";
import { useI18n } from "./I18nProvider";

interface Att { id: number; filename: string; size: number }

export function DocExtras({ docType, docId, pdfPath }: { docType: string; docId: number; pdfPath: string }) {
  const { t } = useI18n();
  const [atts, setAtts] = useState<Att[]>([]);
  const [error, setError] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    try {
      setAtts((await api.get<{ items: Att[] }>(`/v1/attachments/${docType}/${docId}`)).items ?? []);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, [docType, docId]);

  useEffect(() => { load(); }, [load]);

  const upload = async (f: File) => {
    setError("");
    const fd = new FormData();
    fd.append("file", f);
    try {
      const res = await fetch(`/v1/attachments/${docType}/${docId}`, {
        method: "POST",
        headers: { Authorization: `Bearer ${getToken()}` },
        body: fd,
      });
      if (!res.ok) throw new Error((await res.json()).detail || String(res.status));
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const download = (a: Att) => {
    window.open(`/v1/attachments/${a.id}/download`, "_blank");
  };

  const remove = async (a: Att) => {
    if (!window.confirm(t("common.confirmDelete"))) return;
    try { await api.del(`/v1/attachments/${a.id}`); await load(); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  };

  const pdf = () => window.open(pdfPath, "_blank");

  return (
    <div className="card content" style={{ marginTop: 12 }}>
      <div className="page-head">
        <h3 className="invoice-section-title">{t("att.title")}</h3>
        <div className="icon-actions">
          <button className="btn btn-sm" onClick={pdf}>{t("att.pdf")}</button>
          <button className="btn btn-sm" onClick={() => fileRef.current?.click()}>+ {t("att.attach")}</button>
        </div>
      </div>
      <input ref={fileRef} type="file" style={{ display: "none" }} onChange={(e) => { const f = e.target.files?.[0]; if (f) upload(f); e.target.value = ""; }} />
      {error && <div className="error-text">{error}</div>}
      {atts.length === 0 ? (
        <div className="muted">{t("att.empty")}</div>
      ) : (
        <table className="table">
          <tbody>
            {atts.map((a) => (
              <tr key={a.id}>
                <td><button className="btn-ghost" onClick={() => download(a)}>{a.filename}</button></td>
                <td className="num">{a.size}</td>
                <td><button className="btn btn-danger btn-sm" onClick={() => remove(a)}>{t("common.delete")}</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
