"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { RequireAuth } from "../../components/RequireAuth";
import { useI18n } from "../../components/I18nProvider";
import { ACTIVE_COMPANY_EVENT, api, fetchAll } from "../../lib/api";
import { Pagination } from "../../components/Pagination";
import { AuditHistoryPanel, AuditStampBadge } from "../../components/AuditHistory";
import { DocExtras } from "../../components/DocExtras";
import { AuditEntry } from "../../lib/invoice";

const PAGE_SIZE = 50;

interface Account {
  id: number;
  number: string;
  name: string;
}

interface Product {
  id: number;
  name: string;
  code: string;
  unit: string;
  is_inventory: number;
  inventory_account_id: number;
  revenue_account_id: number;
  expense_account_id?: number;
}

interface PreviewLine {
  product_id: number;
  product_name: string;
  code: string;
  unit: string;
  sold_quantity: string;
  sold_revenue: string;
  sold_amount: string;
  unit_cost: string;
  inventory_account_id: number;
  revenue_account_id: number;
  expense_account_id: number;
}

interface TurnRow {
  account_id: number;
  number: string;
  name: string;
  amount: string;
}

interface Preview {
  month: string;
  doc_date: string;
  lines: PreviewLine[];
  expense_total: string;
  expense_turnover: TurnRow[];
  indirect: TurnRow[];
}

interface Line {
  id?: number;
  line_no?: number;
  product_id: number;
  sold_quantity: string;
  sold_amount: string;
  ending_quantity: string;
  coefficient?: string;
  manual_amount?: string;
  quantity: string;
  unit_cost: string;
  amount: string;
  allocated_amount?: string;
  writeoff_amount?: string;
  inventory_account_id: number;
  revenue_account_id: number;
  expense_account_id: number;
}

interface Alloc {
  id?: number;
  line_no?: number;
  product_id: number;
  account_id: number;
  base_amount: string;
  amount: string;
}

interface Doc {
  id: number;
  number: string;
  doc_date: string;
  month: string;
  status: string;
  notes: string;
  wip_end_mode?: string;
  wip_end_value?: string;
  journal_entry_id: number;
  lines?: Line[];
  allocations?: Alloc[];
  created_by?: string;
  created_at?: string;
  updated_by?: string;
  updated_at?: string;
  edit_count?: number;
  audit_history?: AuditEntry[];
}

interface EntryLine {
  account_number: string;
  account_name: string;
  direction: string;
  amount: string;
}

interface Entry {
  id: number;
  entry_date: string;
  description: string;
  document_number: string;
  lines: EntryLine[];
}

function num(s: string | undefined | null): number {
  const n = parseFloat(String(s ?? "").replace(",", "."));
  return Number.isFinite(n) ? n : 0;
}

function fmtQty(n: number): string {
  return String(Math.round(n * 1e6) / 1e6);
}

function fmtMoney(n: number): string {
  return (Math.round(n * 100) / 100).toFixed(2);
}

function monthNow(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function Inner() {
  const { t } = useI18n();
  const [rows, setRows] = useState<Doc[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [doc, setDoc] = useState<Doc | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState("");
  const [offset, setOffset] = useState(0);
  const [tab, setTab] = useState<"docs" | "new">("docs");

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [list, prods, acc] = await Promise.all([
        fetchAll<Doc>("/v1/production-receipts"),
        fetchAll<Product>("/v1/products"),
        fetchAll<Account>("/v1/accounts"),
      ]);
      setRows(list);
      setProducts(prods);
      setAccounts(acc);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
    const onChange = () => {
      setDoc(null);
      load();
    };
    window.addEventListener(ACTIVE_COMPANY_EVENT, onChange);
    return () => window.removeEventListener(ACTIVE_COMPANY_EVENT, onChange);
  }, [load]);

  const productName = useCallback(
    (id: number) => {
      const p = products.find((x) => x.id === id);
      return p ? `${p.code ? p.code + " " : ""}${p.name}` : `#${id}`;
    },
    [products]
  );

  const accLabel = useCallback(
    (id: number) => {
      const a = accounts.find((x) => x.id === id);
      return a ? `${a.number} ${a.name}` : "";
    },
    [accounts]
  );

  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase();
    if (!s) return rows;
    return rows.filter((d) =>
      `${d.number} ${d.month} ${d.doc_date} ${d.status} ${d.notes}`.toLowerCase().includes(s)
    );
  }, [rows, q]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const page = Math.min(Math.floor(offset / PAGE_SIZE), pageCount - 1);
  const start = page * PAGE_SIZE;
  const paged = filtered.slice(start, start + PAGE_SIZE);

  async function open(id: number) {
    setError("");
    try {
      const full = await api.get<Doc>(`/v1/production-receipts/${id}`);
      setDoc(full);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }

  return (
    <div>
      <div className="page-head">
        <h1 className="page-title">{t("pr.title")}</h1>
        {!doc && tab === "docs" && (
          <button type="button" className="btn btn-primary" onClick={() => setTab("new")}>
            {t("pr.new")}
          </button>
        )}
      </div>
      {!doc && (
        <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
          <button
            type="button"
            className={`btn ${tab === "docs" ? "btn-primary" : ""}`}
            onClick={() => setTab("docs")}
          >
            {t("pr.tab.docs")}
          </button>
          <button
            type="button"
            className={`btn ${tab === "new" ? "btn-primary" : ""}`}
            onClick={() => setTab("new")}
          >
            {t("pr.tab.new")}
          </button>
        </div>
      )}
      {error && <div className="error-text">{error}</div>}
      {doc ? (
        <Editor
          t={t}
          doc={doc}
          accLabel={accLabel}
          productName={productName}
          onCancel={() => {
            setDoc(null);
            load();
          }}
          onSaved={async (d) => {
            setDoc(d);
            await load();
          }}
          onDeleted={async () => {
            setDoc(null);
            await load();
          }}
          onError={setError}
        />
      ) : tab === "new" ? (
        <NewReceipt
          t={t}
          onError={setError}
          onCreated={async (id) => {
            await load();
            setTab("docs");
            await open(id);
          }}
        />
      ) : loading ? (
        <div className="content muted">{t("common.loading")}</div>
      ) : (
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
            {filtered.length === 0 ? (
              <div className="content muted">{t("pr.empty")}</div>
            ) : (
              <table className="table">
                <thead>
                  <tr>
                    <th>{t("pr.number")}</th>
                    <th>{t("pr.month")}</th>
                    <th>{t("pr.date")}</th>
                    <th>{t("pr.status")}</th>
                    <th>{t("audit.col_stamp")}</th>
                  </tr>
                </thead>
                <tbody>
                  {paged.map((d) => (
                    <tr key={d.id}>
                      <td>
                        <button type="button" className="btn-ghost" onClick={() => open(d.id)}>
                          {d.number}
                        </button>
                      </td>
                      <td>{d.month}</td>
                      <td>{d.doc_date}</td>
                      <td>
                        <span
                          className={`badge ${d.status === "confirmed" ? "badge-success" : "badge-warning"}`}
                        >
                          {t(`pr.status.${d.status}`)}
                        </span>
                      </td>
                      <td>
                        <AuditStampBadge
                          createdBy={d.created_by}
                          createdAt={d.created_at}
                          updatedBy={d.updated_by}
                          updatedAt={d.updated_at}
                          editCount={d.edit_count}
                        />
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
    </div>
  );
}

function NewReceipt({
  t,
  onError,
  onCreated,
}: {
  t: (key: string) => string;
  onError: (msg: string) => void;
  onCreated: (id: number) => Promise<void>;
}) {
  const [month, setMonth] = useState(monthNow());
  const [preview, setPreview] = useState<Preview | null>(null);
  const [ending, setEnding] = useState<Record<number, string>>({});
  const [busy, setBusy] = useState(false);
  const [wipMode, setWipMode] = useState("amount");
  const [wipValue, setWipValue] = useState("0");

  async function loadPreview(e?: FormEvent) {
    e?.preventDefault();
    setBusy(true);
    onError("");
    try {
      const data = await api.get<Preview>(
        `/v1/production-receipts/preview?month=${encodeURIComponent(month)}`
      );
      setPreview(data);
      setEnding({});
    } catch (err) {
      onError(err instanceof Error ? err.message : String(err));
      setPreview(null);
    } finally {
      setBusy(false);
    }
  }

  async function createDoc() {
    if (!preview) return;
    setBusy(true);
    onError("");
    try {
      const lines = preview.lines.map((l) => ({
        product_id: l.product_id,
        ending_quantity: ending[l.product_id] ?? "0",
      }));
      const created = await api.post<Doc>("/v1/production-receipts", { month, lines, wip_end_mode: wipMode, wip_end_value: wipValue });
      await onCreated(created.id);
    } catch (err) {
      onError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  // Единичната цена и стойността на продаденото се преизчисляват на живо спрямо
  // въведената наличност (произведено = продадено + наличност), както при запис.
  const liveLines = preview?.lines ?? [];
  const totalProduced = liveLines.reduce(
    (s, l) => s + num(l.sold_quantity) + num(ending[l.product_id] ?? "0"),
    0
  );
  const unitLive = totalProduced > 0 ? num(preview?.expense_total) / totalProduced : 0;
  const soldLive = (l: { sold_quantity: string }) => num(l.sold_quantity) * unitLive;
  const totalSold = liveLines.reduce((s, l) => s + soldLive(l), 0);

  return (
    <div className="card card-pad">
      <div className="form-grid">
        <div className="field">
          <label className="label">{t("pr.month")}</label>
          <input
            type="month"
            className="input"
            value={month}
            onChange={(e) => setMonth(e.target.value)}
          />
        </div>
        <div className="field">
          <label className="label">{t("pr.wip_mode")}</label>
          <select className="select" value={wipMode} onChange={(e) => setWipMode(e.target.value)}>
            <option value="amount">{t("pr.wip_amount")}</option>
            <option value="percent">{t("pr.percent")}</option>
          </select>
        </div>
        <div className="field">
          <label className="label">{t("pr.wip_end")}</label>
          <input className="input" value={wipValue} onChange={(e) => setWipValue(e.target.value)} />
        </div>
        <div className="field">
          <label className="label">&nbsp;</label>
          <button type="button" className="btn" disabled={busy || !month} onClick={loadPreview}>
            {t("pr.show_preview")}
          </button>
        </div>
      </div>
      {preview && (
        <>
          <div className="content" style={{ marginTop: 8 }}>
            {t("pr.expense_turnover")}:{" "}
            {preview.expense_turnover.length === 0
              ? "—"
              : preview.expense_turnover
                  .map((r) => `${r.number} ${r.name}: ${r.amount}`)
                  .join("; ")}
          </div>
          <div className="content">
            {t("pr.indirect")}:{" "}
            {preview.indirect.length === 0
              ? "—"
              : preview.indirect.map((r) => `${r.number} ${r.amount}`).join("; ")}
          </div>
          {preview.lines.length === 0 ? (
            <div className="content muted" style={{ marginTop: 8 }}>
              {t("pr.no_sales")}
            </div>
          ) : (
            <>
              <table className="table" style={{ marginTop: 8 }}>
                <thead>
                  <tr>
                    <th>{t("pr.product")}</th>
                    <th>{t("pr.sold_qty")}</th>
                    <th>{t("pr.sold_revenue")}</th>
                    <th>{t("pr.sold_amount")}</th>
                    <th>{t("pr.unit_cost")}</th>
                    <th>{t("pr.ending")}</th>
                    <th>{t("pr.produced_qty")}</th>
                  </tr>
                </thead>
                <tbody>
                  {preview.lines.map((l) => {
                    const end = num(ending[l.product_id] ?? "0");
                    const produced = num(l.sold_quantity) + end;
                    return (
                      <tr key={l.product_id}>
                        <td>{l.code ? `${l.code} ` : ""}{l.product_name}</td>
                        <td>{l.sold_quantity}</td>
                        <td>{l.sold_revenue}</td>
                        <td>{fmtMoney(soldLive(l))}</td>
                        <td>{unitLive.toFixed(6)}</td>
                        <td>
                          <input
                            className="input"
                            style={{ maxWidth: 110 }}
                            value={ending[l.product_id] ?? "0"}
                            onChange={(e) =>
                              setEnding((prev) => ({ ...prev, [l.product_id]: e.target.value }))
                            }
                          />
                        </td>
                        <td>{fmtQty(produced)}</td>
                      </tr>
                    );
                  })}
                  <tr>
                    <td className="muted">{t("pr.total")}</td>
                    <td />
                    <td />
                    <td>{fmtMoney(totalSold)}</td>
                    <td />
                    <td />
                    <td />
                  </tr>
                </tbody>
              </table>
              <div className="form-actions">
                <button
                  type="button"
                  className="btn btn-primary"
                  disabled={busy}
                  onClick={createDoc}
                >
                  {t("pr.create_doc")}
                </button>
              </div>
            </>
          )}
        </>
      )}
    </div>
  );
}

function Editor({
  t,
  doc,
  accLabel,
  productName,
  onCancel,
  onSaved,
  onDeleted,
  onError,
}: {
  t: (key: string) => string;
  doc: Doc;
  accLabel: (id: number) => string;
  productName: (id: number) => string;
  onCancel: () => void;
  onSaved: (d: Doc) => Promise<void>;
  onDeleted: () => Promise<void>;
  onError: (msg: string) => void;
}) {
  const [notes, setNotes] = useState(doc.notes || "");
  const [wipMode, setWipMode] = useState(doc.wip_end_mode || "amount");
  const [wipValue, setWipValue] = useState(doc.wip_end_value || "0");
  const [lines, setLines] = useState<Line[]>(doc.lines ?? []);
  const [dtab, setDtab] = useState<"made" | "alloc" | "entries">("made");
  const [busy, setBusy] = useState(false);
  const [entry, setEntry] = useState<Entry | null>(null);
  const [planned, setPlanned] = useState<Preview | null>(null);
  const locked = doc.status === "confirmed";

  useEffect(() => {
    setNotes(doc.notes || "");
    setWipMode(doc.wip_end_mode || "amount");
    setWipValue(doc.wip_end_value || "0");
    setLines(doc.lines ?? []);
    setEntry(null);
    setPlanned(null);
  }, [doc]);

  useEffect(() => {
    if (dtab === "entries" && doc.journal_entry_id > 0 && !entry) {
      api
        .get<Entry>(`/v1/journal/${doc.journal_entry_id}`)
        .then(setEntry)
        .catch(() => setEntry(null));
    }
    if (dtab === "alloc" && !doc.allocations?.length && !planned) {
      api
        .get<Preview>(`/v1/production-receipts/preview?month=${encodeURIComponent(doc.month)}`)
        .then(setPlanned)
        .catch(() => setPlanned(null));
    }
  }, [dtab, doc, entry, planned]);

  function setEnding(productId: number, value: string) {
    setLines((prev) =>
      prev.map((l) =>
        l.product_id === productId
          ? { ...l, ending_quantity: value }
          : l
      )
    );
  }

  function setLineField(productId: number, patch: Partial<Line>) {
    setLines((prev) => prev.map((l) => (l.product_id === productId ? { ...l, ...patch } : l)));
  }

  function draftBody() {
    return {
      notes,
      wip_end_mode: wipMode,
      wip_end_value: wipValue,
      lines: lines.map((l) => ({
        product_id: l.product_id,
        ending_quantity: l.ending_quantity,
        coefficient: l.coefficient ?? "1",
        manual_amount: l.manual_amount ?? "",
      })),
    };
  }

  async function save(e?: FormEvent) {
    e?.preventDefault();
    setBusy(true);
    onError("");
    try {
      const updated = await api.patch<Doc>(`/v1/production-receipts/${doc.id}`, draftBody());
      await onSaved(updated);
    } catch (err) {
      onError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  async function act(path: string) {
    setBusy(true);
    onError("");
    try {
      // Потвърждаването чете редовете от базата — първо се записва черновата,
      // иначе нова наличност на екрана не влиза в записа.
      if (!locked && path.endsWith("/confirm")) {
        const saved = await api.patch<Doc>(`/v1/production-receipts/${doc.id}`, draftBody());
        try {
          const updated = await api.post<Doc>(path, {});
          await onSaved(updated);
        } catch (err) {
          await onSaved(saved);
          throw err;
        }
      } else {
        const updated = await api.post<Doc>(path, {});
        await onSaved(updated);
      }
    } catch (err) {
      onError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (!window.confirm(t("common.confirmDelete"))) return;
    setBusy(true);
    onError("");
    try {
      await api.del(`/v1/production-receipts/${doc.id}`);
      await onDeleted();
    } catch (err) {
      onError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  // 611 не се мени от наличността: единичната цена е оборотът / новото произведено.
  // Запазените amount/unit_cost важат само докато наличността не е пипана.
  const endingDirty = lines.some(
    (l) => Math.abs(num(l.ending_quantity) - (num(l.quantity) - num(l.sold_quantity))) > 1e-6
  );
  const expenseBase = lines.reduce((s, l) => s + num(l.unit_cost) * num(l.quantity), 0);
  const producedNow = lines.reduce(
    (s, l) => s + num(l.sold_quantity) + num(l.ending_quantity),
    0
  );
  const unitLive = producedNow > 0 ? expenseBase / producedNow : 0;

  function shownSold(l: Line): string {
    if (locked || !endingDirty) return l.sold_amount;
    return fmtMoney(num(l.sold_quantity) * unitLive);
  }

  function shownUnit(l: Line): string {
    if (locked || !endingDirty) return l.unit_cost;
    return unitLive.toFixed(6);
  }

  function shownAmount(l: Line): string {
    if (locked || !endingDirty) return l.amount;
    return fmtMoney((num(l.sold_quantity) + num(l.ending_quantity)) * unitLive);
  }

  const totalAmount = lines.reduce((s, l) => s + num(shownAmount(l)), 0);
  const totalSoldAmount = lines.reduce((s, l) => s + num(shownSold(l)), 0);
  const totalAlloc = lines.reduce((s, l) => s + num(l.allocated_amount), 0);
  const totalWriteoff = lines.reduce((s, l) => s + num(l.writeoff_amount), 0);
  const allocs = doc.allocations ?? [];
  const allocTotal = allocs.reduce((s, a) => s + num(a.amount), 0);

  return (
    <div>
      <div className="page-head">
        <button type="button" className="btn" onClick={onCancel}>
          ← {t("pr.back")}
        </button>
        <h1 className="page-title">
          {doc.number} · {doc.month}
        </h1>
        <span className={`badge ${locked ? "badge-success" : "badge-warning"}`}>
          {t(`pr.status.${doc.status}`)}
        </span>
        <AuditStampBadge
          createdBy={doc.created_by}
          createdAt={doc.created_at}
          updatedBy={doc.updated_by}
          updatedAt={doc.updated_at}
          editCount={doc.edit_count}
        />
      </div>

      <DocExtras docType="production_receipt" docId={doc.id} pdfPath={`/v1/production-receipts/${doc.id}/pdf`} />

      <div className="card card-pad" style={{ marginBottom: 12 }}>
        <div className="form-grid">
          <div className="field">
            <label className="label">{t("pr.date")}</label>
            <span className="content">{doc.doc_date}</span>
          </div>
          <div className="field">
            <label className="label">{t("pr.notes")}</label>
            <input
              className="input"
              value={notes}
              disabled={locked}
              onChange={(e) => setNotes(e.target.value)}
            />
          </div>
          <div className="field">
            <label className="label">{t("pr.wip_mode")}</label>
            <select className="select" value={wipMode} disabled={locked} onChange={(e) => setWipMode(e.target.value)}>
              <option value="amount">{t("pr.wip_amount")}</option>
              <option value="percent">{t("pr.percent")}</option>
            </select>
          </div>
          <div className="field">
            <label className="label">{t("pr.wip_end")}</label>
            <input className="input" value={wipValue} disabled={locked} onChange={(e) => setWipValue(e.target.value)} />
          </div>
        </div>
        <div className="form-actions">
          {!locked && (
            <>
              <button type="button" className="btn" disabled={busy} onClick={save}>
                {t("pr.save")}
              </button>
              <button
                type="button"
                className="btn btn-primary"
                disabled={busy || lines.length === 0}
                onClick={() => act(`/v1/production-receipts/${doc.id}/confirm`)}
              >
                {t("pr.confirm")}
              </button>
              <button
                type="button"
                className="btn btn-danger"
                disabled={busy}
                onClick={remove}
              >
                {t("pr.delete")}
              </button>
            </>
          )}
          {locked && (
            <button
              type="button"
              className="btn"
              disabled={busy}
              onClick={() => act(`/v1/production-receipts/${doc.id}/unpost`)}
            >
              {t("pr.unpost")}
            </button>
          )}
        </div>
      </div>

      <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
        {(["made", "alloc", "entries"] as const).map((k) => (
          <button
            key={k}
            type="button"
            className={`btn ${dtab === k ? "btn-primary" : ""}`}
            onClick={() => setDtab(k)}
          >
            {t(`pr.tab.${k}`)}
          </button>
        ))}
      </div>

      {dtab === "made" && (
        <div className="card">
          <table className="table">
            <thead>
              <tr>
                <th>{t("pr.product")}</th>
                <th>{t("pr.sold_qty")}</th>
                <th>{t("pr.sold_amount")}</th>
                <th>{t("pr.ending")}</th>
                {!locked && <th>{t("pr.coef")}</th>}
                {!locked && <th>{t("pr.manual")}</th>}
                <th>{t("pr.produced_qty")}</th>
                <th>{t("pr.unit_cost")}</th>
                <th>{t("pr.amount")}</th>
                {locked && <th>{t("pr.allocated")}</th>}
                {locked && <th>{t("pr.writeoff")}</th>}
              </tr>
            </thead>
            <tbody>
              {lines.length === 0 ? (
                <tr>
                  <td colSpan={9} className="muted">
                    {t("common.empty")}
                  </td>
                </tr>
              ) : (
                lines.map((l) => {
                  const end = num(l.ending_quantity);
                  const produced = num(l.sold_quantity) + end;
                  return (
                    <tr key={l.product_id}>
                      <td>{productName(l.product_id)}</td>
                      <td>{l.sold_quantity}</td>
                      <td>{shownSold(l)}</td>
                      <td>
                        {locked ? (
                          l.ending_quantity
                        ) : (
                          <input
                            className="input"
                            style={{ maxWidth: 110 }}
                            value={l.ending_quantity}
                            onChange={(e) => setEnding(l.product_id, e.target.value)}
                          />
                        )}
                      </td>
                      {!locked && (
                        <td><input className="input" style={{ maxWidth: 70 }} value={l.coefficient ?? "1"} onChange={(e) => setLineField(l.product_id, { coefficient: e.target.value })} /></td>
                      )}
                      {!locked && (
                        <td><input className="input" style={{ maxWidth: 90 }} value={l.manual_amount ?? ""} onChange={(e) => setLineField(l.product_id, { manual_amount: e.target.value })} /></td>
                      )}
                      <td>{locked ? l.quantity : fmtQty(produced)}</td>
                      <td>{shownUnit(l)}</td>
                      <td>{shownAmount(l)}</td>
                      {locked && <td>{l.allocated_amount}</td>}
                      {locked && <td>{l.writeoff_amount}</td>}
                    </tr>
                  );
                })
              )}
              {lines.length > 0 && (
                <tr>
                  <td className="muted">{t("pr.total")}</td>
                  <td />
                  <td>{fmtMoney(totalSoldAmount)}</td>
                  <td />
                  <td />
                  <td />
                  <td>{fmtMoney(totalAmount)}</td>
                  {locked && <td>{fmtMoney(totalAlloc)}</td>}
                  {locked && <td>{fmtMoney(totalWriteoff)}</td>}
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {dtab === "alloc" && (
        <div className="card">
          {allocs.length > 0 ? (
            <table className="table">
              <thead>
                <tr>
                  <th>{t("pr.account")}</th>
                  <th>{t("pr.product")}</th>
                  <th>{t("pr.base")}</th>
                  <th>{t("pr.total")}</th>
                </tr>
              </thead>
              <tbody>
                {allocs.map((a, i) => (
                  <tr key={a.id ?? i}>
                    <td>{accLabel(a.account_id)}</td>
                    <td>{productName(a.product_id)}</td>
                    <td>{a.base_amount}</td>
                    <td>{a.amount}</td>
                  </tr>
                ))}
                <tr>
                  <td className="muted" colSpan={3}>{t("pr.total")}</td>
                  <td>{fmtMoney(allocTotal)}</td>
                </tr>
              </tbody>
            </table>
          ) : (
            <div className="content">
              <div className="muted">{t("pr.planned_hint")}</div>
              {planned && planned.indirect.length > 0 && (
                <table className="table" style={{ marginTop: 8 }}>
                  <thead>
                    <tr>
                      <th>{t("pr.account")}</th>
                      <th>{t("pr.total")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {planned.indirect.map((r) => (
                      <tr key={r.account_id}>
                        <td>{r.number} {r.name}</td>
                        <td>{r.amount}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          )}
        </div>
      )}

      {dtab === "entries" && (
        <div className="card">
          {doc.journal_entry_id > 0 && entry ? (
            <>
              <div className="content" style={{ marginBottom: 8 }}>
                {t("pr.journal_entry")} #{entry.id} · {entry.entry_date} · {entry.description}
              </div>
              <table className="table">
                <thead>
                  <tr>
                    <th>{t("pr.account")}</th>
                    <th>{t("pr.debit")}</th>
                    <th>{t("pr.credit")}</th>
                  </tr>
                </thead>
                <tbody>
                  {entry.lines.map((l, i) => (
                    <tr key={i}>
                      <td>{l.account_number} {l.account_name}</td>
                      <td>{l.direction === "debit" ? l.amount : ""}</td>
                      <td>{l.direction === "credit" ? l.amount : ""}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </>
          ) : (
            <div className="content muted">{t("pr.no_entry")}</div>
          )}
        </div>
      )}

      {doc.audit_history && doc.audit_history.length > 0 && (
        <AuditHistoryPanel
          history={doc.audit_history}
          createdBy={doc.created_by}
          createdAt={doc.created_at}
          updatedBy={doc.updated_by}
          updatedAt={doc.updated_at}
          editCount={doc.edit_count}
        />
      )}
    </div>
  );
}

export default function ProductionReceiptsPage() {
  return (
    <RequireAuth>
      <Inner />
    </RequireAuth>
  );
}
