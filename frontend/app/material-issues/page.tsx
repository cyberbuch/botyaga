"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { RequireAuth } from "../../components/RequireAuth";
import { useI18n } from "../../components/I18nProvider";
import { ACTIVE_COMPANY_EVENT, api, fetchAll, ListResponse } from "../../lib/api";
import { CompanyLocation, fetchCompanyLocations, mainLocationId } from "../../lib/locations";
import { Pagination } from "../../components/Pagination";
import { AuditHistoryPanel, AuditStampBadge } from "../../components/AuditHistory";
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
  is_inventory: number;
  inventory_account_id: number;
  expense_account_id?: number;
  auto_write_off?: number;
}

interface Rule {
  id: number;
  kind: string;
  inventory_account_id: number;
  offset_account_id: number;
}

interface Line {
  product_id: number;
  quantity: string;
  account_id: number;
  inventory_account_id: number;
  unit_cost?: string;
  amount?: string;
}

interface Doc {
  id: number;
  number: string;
  doc_date: string;
  location_id: number;
  status: string;
  notes: string;
  lines?: Line[];
  created_by?: string;
  created_at?: string;
  updated_by?: string;
  updated_at?: string;
  edit_count?: number;
  audit_history?: AuditEntry[];
}

function isoDay(): string {
  const d = new Date();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${m}-${day}`;
}

function Inner() {
  const { t } = useI18n();
  const [rows, setRows] = useState<Doc[]>([]);
  const [locations, setLocations] = useState<CompanyLocation[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [rules, setRules] = useState<Rule[]>([]);
  const [doc, setDoc] = useState<Doc | null>(null);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState("");
  const [offset, setOffset] = useState(0);
  const [tab, setTab] = useState<"bulk" | "docs">("bulk");

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [list, locs, prods, acc, rulePack] = await Promise.all([
        fetchAll<Doc>("/v1/material-issues"),
        fetchCompanyLocations(),
        fetchAll<Product>("/v1/products"),
        fetchAll<Account>("/v1/accounts"),
        api.get<ListResponse<Rule>>("/v1/stock/rules"),
      ]);
      setRows(list);
      setLocations(locs);
      setProducts(prods.filter((p) => Number(p.is_inventory) === 1 && Number(p.auto_write_off) !== 1));
      setAccounts(acc);
      setRules((rulePack.items ?? []).filter((r) => r.kind === "material"));
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
      setCreating(false);
      load();
    };
    window.addEventListener(ACTIVE_COMPANY_EVENT, onChange);
    return () => window.removeEventListener(ACTIVE_COMPANY_EVENT, onChange);
  }, [load]);

  const locName = useCallback(
    (id: number) => locations.find((l) => l.id === id)?.name ?? "",
    [locations]
  );
  const accLabel = (id: number) => {
    const a = accounts.find((x) => x.id === id);
    return a ? `${a.number} ${a.name}` : "";
  };

  const filtered = useMemo(() => {
    const s = q.trim().toLowerCase();
    if (!s) return rows;
    return rows.filter((d) =>
      `${d.number} ${d.doc_date} ${locName(d.location_id)} ${d.status} ${d.notes}`
        .toLowerCase()
        .includes(s)
    );
  }, [rows, q, locName]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const page = Math.min(Math.floor(offset / PAGE_SIZE), pageCount - 1);
  const start = page * PAGE_SIZE;
  const paged = filtered.slice(start, start + PAGE_SIZE);

  async function open(id: number) {
    setError("");
    try {
      const full = await api.get<Doc>(`/v1/material-issues/${id}`);
      setDoc(full);
      setCreating(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }

  function startNew() {
    setDoc({
      id: 0,
      number: "",
      doc_date: isoDay(),
      location_id: locations[0]?.id ?? 0,
      status: "draft",
      notes: "",
      lines: [{ product_id: 0, quantity: "1", account_id: 0, inventory_account_id: 0 }],
    });
    setCreating(true);
  }

  return (
    <div>
      <div className="page-head">
        <h1 className="page-title">{t("mat.title")}</h1>
        {!doc && tab === "docs" && (
          <button type="button" className="btn btn-primary" onClick={startNew}>
            {t("mat.new")}
          </button>
        )}
      </div>
      {!doc && (
        <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
          <button
            type="button"
            className={`btn ${tab === "bulk" ? "btn-primary" : ""}`}
            onClick={() => setTab("bulk")}
          >
            {t("mat.tab.bulk")}
          </button>
          <button
            type="button"
            className={`btn ${tab === "docs" ? "btn-primary" : ""}`}
            onClick={() => setTab("docs")}
          >
            {t("mat.tab.docs")}
          </button>
        </div>
      )}
      {error && <div className="error-text">{error}</div>}
      {doc ? (
        <Editor
          t={t}
          doc={doc}
          creating={creating}
          products={products}
          rules={rules}
          locations={locations}
          accLabel={accLabel}
          onCancel={() => {
            setDoc(null);
            setCreating(false);
          }}
          onSaved={async (id) => {
            await load();
            await open(id);
          }}
          onDeleted={async () => {
            setDoc(null);
            setCreating(false);
            await load();
          }}
          onError={setError}
        />
      ) : tab === "bulk" ? (
        loading ? (
          <div className="content muted">{t("common.loading")}</div>
        ) : (
          <BulkWriteoff
            t={t}
            products={products}
            accounts={accounts}
            rules={rules}
            locations={locations}
            accLabel={accLabel}
            onError={setError}
            onPosted={async () => {
              await load();
              setTab("docs");
            }}
          />
        )
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
              <div className="content muted">{t("common.empty")}</div>
            ) : (
              <table className="table">
                <thead>
                  <tr>
                    <th>{t("mat.number")}</th>
                    <th>{t("mat.date")}</th>
                    <th>{t("mat.location")}</th>
                    <th>{t("mat.status")}</th>
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
                      <td>{d.doc_date}</td>
                      <td>{locName(d.location_id)}</td>
                      <td>
                        <span className={`badge ${d.status === "confirmed" ? "badge-success" : "badge-warning"}`}>
                          {t(`mat.status.${d.status}`)}
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

interface BalRow {
  product_id: number;
  product_name: string;
  location_id: number;
  quantity: string;
  value: string;
}

interface StockReport {
  balances: BalRow[];
  warnings?: string[];
}

function num(s: string | undefined | null): number {
  const n = parseFloat(String(s ?? "").replace(",", "."));
  return Number.isFinite(n) ? n : 0;
}

function fmtQty(n: number): string {
  return String(Math.round(n * 1e6) / 1e6);
}

function BulkWriteoff({
  t,
  products,
  accounts,
  rules,
  locations,
  accLabel,
  onError,
  onPosted,
}: {
  t: (key: string) => string;
  products: Product[];
  accounts: Account[];
  rules: Rule[];
  locations: CompanyLocation[];
  accLabel: (id: number) => string;
  onError: (msg: string) => void;
  onPosted: () => Promise<void>;
}) {
  const [locationId, setLocationId] = useState(0);
  const [invAcc, setInvAcc] = useState(0);
  const [expenseAcc, setExpenseAcc] = useState(0);
  const [q, setQ] = useState("");
  const [stock, setStock] = useState<Record<number, number>>({});
  const [rem, setRem] = useState<Record<number, string>>({});
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState("");

  // Главният складов обект по подразбиране
  useEffect(() => {
    if (locationId === 0 && locations.length > 0) setLocationId(mainLocationId(locations));
  }, [locations, locationId]);

  // Първата налична сметка за материали (напр. 302) по подразбиране
  useEffect(() => {
    if (invAcc === 0) {
      const ids = [...new Set(products.map((p) => p.inventory_account_id).filter((id) => id > 0))].sort(
        (a, b) => a - b
      );
      if (ids.length > 0) setInvAcc(ids[0]);
    }
  }, [products, invAcc]);

  // При смяна на сметката за материали — разходната сметка се занулява
  useEffect(() => {
    setExpenseAcc(0);
  }, [invAcc]);

  // Наличностите са сборно за фирмата (себестойността е по артикул, не по обект),
  // за да се виждат всички материали по сметката с количество различно от 0.
  const loadStock = useCallback(async () => {
    setNote("");
    try {
      const data = await api.get<StockReport>("/v1/stock/report");
      const map: Record<number, number> = {};
      for (const b of data.balances ?? []) {
        map[b.product_id] = (map[b.product_id] ?? 0) + num(b.quantity);
      }
      setStock(map);
    } catch (e) {
      onError(e instanceof Error ? e.message : String(e));
    }
  }, [onError]);

  useEffect(() => {
    loadStock();
  }, [loadStock]);

  const inventoryAccounts = useMemo(() => {
    const ids = [...new Set(products.map((p) => p.inventory_account_id).filter((id) => id > 0))];
    return ids.sort((a, b) => accLabel(a).localeCompare(accLabel(b)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [products, accounts]);

  // Разходни сметки: от правилата за сметката плюс зададените в артикулите (60101, 60102…)
  const expenseChoices = useMemo(() => {
    const fromProducts = [
      ...new Set(
        products
          .filter((p) => p.inventory_account_id === invAcc)
          .map((p) => p.expense_account_id ?? 0)
          .filter((id) => id > 0)
      ),
    ];
    return [...new Set([...offsets(rules, invAcc, 0), ...fromProducts])];
  }, [rules, invAcc, products]);

  // Само материали с количество различно от 0, с търсене по код/име
  const rows = useMemo(() => {
    const s = q.trim().toLowerCase();
    return products
      .filter((p) => p.inventory_account_id === invAcc)
      .map((p) => ({ product: p, available: stock[p.id] ?? 0 }))
      .filter((r) => Math.abs(r.available) > 1e-9)
      .filter((r) => !s || `${r.product.code} ${r.product.name}`.toLowerCase().includes(s))
      .sort((a, b) =>
        `${a.product.code} ${a.product.name}`.localeCompare(`${b.product.code} ${b.product.name}`)
      );
  }, [products, invAcc, stock, q]);

  // Сметка на изписване: избраната горе има предност, иначе дефинираната за материала
  function lineAccount(product: Product): number {
    if (expenseAcc > 0) return expenseAcc;
    return product.expense_account_id && product.expense_account_id > 0
      ? product.expense_account_id
      : 0;
  }

  // За изписване = налично - остатък (при остатък 0 се изписва всичко)
  function issueQty(available: number, productId: number): number {
    const raw = rem[productId];
    const r = raw === undefined || raw.trim() === "" ? 0 : num(raw);
    return Math.max(0, Math.round((available - r) * 1e6) / 1e6);
  }

  async function post() {
    setBusy(true);
    onError("");
    setNote("");
    try {
      if (locationId <= 0) throw new Error(t("mat.bulk.no_location"));
      const lines = rows
        .map((r) => ({
          product_id: r.product.id,
          quantity: fmtQty(issueQty(r.available, r.product.id)),
          account_id: lineAccount(r.product),
          inventory_account_id: invAcc,
        }))
        .filter((l) => num(l.quantity) > 0);
      if (lines.length === 0) throw new Error(t("mat.bulk.no_lines"));
      if (lines.some((l) => l.account_id <= 0)) throw new Error(t("mat.bulk.pick_expense"));
      const created = await api.post<Doc>("/v1/material-issues", {
        doc_date: isoDay(),
        location_id: locationId,
        notes: `${t("mat.bulk.notes")} ${accLabel(invAcc)}`,
        lines,
      });
      await api.post(`/v1/material-issues/${created.id}/confirm`, {});
      setNote(`${t("mat.bulk.posted")}: ${created.number}`);
      setRem({});
      await loadStock();
      await onPosted();
    } catch (e) {
      onError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card card-pad">
      <div className="form-grid">
        <div className="field">
          <label className="label">{t("mat.location")}</label>
          <select
            className="select"
            value={String(locationId)}
            onChange={(e) => setLocationId(Number(e.target.value) || 0)}
          >
            <option value="0">{t("stock.rules.pick")}</option>
            {locations.map((l) => (
              <option key={l.id} value={l.id}>{l.name}</option>
            ))}
          </select>
        </div>
        <div className="field">
          <label className="label">{t("mat.bulk.inventory")}</label>
          <select
            className="select"
            value={String(invAcc)}
            onChange={(e) => setInvAcc(Number(e.target.value) || 0)}
          >
            <option value="0">{t("mat.bulk.pick_inventory")}</option>
            {inventoryAccounts.map((id) => (
              <option key={id} value={id}>{accLabel(id)}</option>
            ))}
          </select>
        </div>
        <div className="field">
          <label className="label">{t("mat.bulk.expense")}</label>
          {expenseChoices.length === 0 ? (
            <span className="muted">{t("mat.no_rule")}</span>
          ) : (
            <select
              className="select"
              value={String(expenseAcc)}
              onChange={(e) => setExpenseAcc(Number(e.target.value) || 0)}
            >
              <option value="0">{t("mat.bulk.pick_expense")}</option>
              {expenseChoices.map((id) => (
                <option key={id} value={id}>{accLabel(id)}</option>
              ))}
            </select>
          )}
        </div>
        <div className="field">
          <label className="label">{t("common.search")}</label>
          <input
            className="input"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder={t("mat.bulk.search")}
          />
        </div>
      </div>
      {note && <div className="content">{note}</div>}
      <table className="table">
        <thead>
          <tr>
            <th>{t("mat.product")}</th>
            <th>{t("mat.bulk.available")}</th>
            <th>{t("mat.bulk.remainder")}</th>
            <th>{t("mat.bulk.issue")}</th>
            <th>{t("mat.account")}</th>
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 ? (
            <tr>
              <td colSpan={5} className="muted">{t("mat.bulk.empty")}</td>
            </tr>
          ) : (
            rows.map(({ product, available }) => {
              const acc = lineAccount(product);
              return (
                <tr key={product.id}>
                  <td>{product.code ? `${product.code} ` : ""}{product.name}</td>
                  <td>{fmtQty(available)}</td>
                  <td>
                    <input
                      className="input"
                      style={{ maxWidth: 110 }}
                      value={rem[product.id] ?? "0"}
                      onChange={(e) =>
                        setRem((prev) => ({ ...prev, [product.id]: e.target.value }))
                      }
                    />
                  </td>
                  <td>{fmtQty(issueQty(available, product.id))}</td>
                  <td className={acc > 0 ? "" : "muted"}>{acc > 0 ? accLabel(acc) : "—"}</td>
                </tr>
              );
            })
          )}
        </tbody>
      </table>
      <div className="form-actions">
        <button
          type="button"
          className="btn btn-primary"
          disabled={busy || locationId <= 0 || rows.length === 0}
          onClick={post}
        >
          {t("mat.bulk.journal")}
        </button>
      </div>
    </div>
  );
}

function offsets(rules: Rule[], inventory: number, expense = 0): number[] {
  const ids = rules.filter((r) => r.inventory_account_id === inventory).map((r) => r.offset_account_id);
  if (expense > 0) ids.unshift(expense);
  return [...new Set(ids)];
}

function Editor({
  t,
  doc,
  creating,
  products,
  rules,
  locations,
  accLabel,
  onCancel,
  onSaved,
  onDeleted,
  onError,
}: {
  t: (key: string) => string;
  doc: Doc;
  creating: boolean;
  products: Product[];
  rules: Rule[];
  locations: CompanyLocation[];
  accLabel: (id: number) => string;
  onCancel: () => void;
  onSaved: (id: number) => Promise<void>;
  onDeleted: () => Promise<void>;
  onError: (msg: string) => void;
}) {
  const [date, setDate] = useState(doc.doc_date);
  const [locationId, setLocationId] = useState(doc.location_id);
  const [notes, setNotes] = useState(doc.notes || "");
  const [lines, setLines] = useState<Line[]>(doc.lines ?? []);
  const [busy, setBusy] = useState(false);
  const locked = doc.status === "confirmed";

  useEffect(() => {
    setDate(doc.doc_date);
    setLocationId(doc.location_id);
    setNotes(doc.notes || "");
    setLines(doc.lines ?? []);
  }, [doc]);

  function setLine(i: number, patch: Partial<Line>) {
    setLines((prev) => prev.map((line, n) => (n === i ? { ...line, ...patch } : line)));
  }

  function pickProduct(i: number, productId: number) {
    const product = products.find((p) => p.id === productId);
    const inventory = product?.inventory_account_id ?? 0;
    const choices = offsets(rules, inventory, product?.expense_account_id ?? 0);
    setLine(i, {
      product_id: productId,
      inventory_account_id: inventory,
      account_id: product?.expense_account_id || (choices.length === 1 ? choices[0] : 0),
    });
  }

  function draftBody() {
    return {
      doc_date: date,
      location_id: locationId,
      notes,
      lines: lines.map((l) => ({
        product_id: l.product_id,
        quantity: l.quantity,
        account_id: l.account_id,
        inventory_account_id: l.inventory_account_id,
      })),
    };
  }

  async function save(e?: FormEvent) {
    e?.preventDefault();
    setBusy(true);
    onError("");
    try {
      await persist();
    } catch (err) {
      onError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  async function persist() {
    const body = draftBody();
    if (creating) {
      const created = await api.post<Doc>("/v1/material-issues", body);
      await onSaved(created.id);
    } else {
      await api.patch(`/v1/material-issues/${doc.id}`, body);
      await onSaved(doc.id);
    }
  }

  async function act(path: string) {
    setBusy(true);
    onError("");
    try {
      if (!creating && !locked) await persist();
      await api.post(path, {});
      await onSaved(doc.id);
    } catch (err) {
      onError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    setBusy(true);
    onError("");
    try {
      await api.del(`/v1/material-issues/${doc.id}`);
      await onDeleted();
    } catch (err) {
      onError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="card card-pad" onSubmit={save}>
      <div className="page-head">
        <h2 style={{ margin: 0 }}>{creating ? t("mat.new") : doc.number}</h2>
        <button type="button" className="btn" onClick={onCancel}>
          {t("mat.back")}
        </button>
      </div>
      <div className="form-grid">
        <div className="field">
          <label className="label">{t("mat.date")}</label>
          <input className="input" type="date" value={date} disabled={locked} onChange={(e) => setDate(e.target.value)} />
        </div>
        <div className="field">
          <label className="label">{t("mat.location")}</label>
          <select className="select" value={String(locationId)} disabled={locked} onChange={(e) => setLocationId(Number(e.target.value) || 0)}>
            <option value="0">{t("stock.rules.pick")}</option>
            {locations.map((l) => (
              <option key={l.id} value={l.id}>{l.name}</option>
            ))}
          </select>
        </div>
        <div className="field">
          <label className="label">{t("mat.notes")}</label>
          <input className="input" value={notes} disabled={locked} onChange={(e) => setNotes(e.target.value)} />
        </div>
      </div>
      <table className="table">
        <thead>
          <tr>
            <th>{t("mat.product")}</th>
            <th>{t("mat.quantity")}</th>
            <th>{t("mat.account")}</th>
            <th>{t("mat.cost")}</th>
          </tr>
        </thead>
        <tbody>
          {lines.map((line, i) => {
            const product = products.find((p) => p.id === line.product_id);
            const choices = offsets(rules, line.inventory_account_id, product?.expense_account_id ?? 0);
            return (
              <tr key={i}>
                <td>
                  <select className="select" value={String(line.product_id)} disabled={locked} onChange={(e) => pickProduct(i, Number(e.target.value) || 0)}>
                    <option value="0">{t("stock.rules.pick")}</option>
                    {products.map((p) => (
                      <option key={p.id} value={p.id}>{p.code ? `${p.code} ` : ""}{p.name}</option>
                    ))}
                  </select>
                </td>
                <td>
                  <input className="input" value={line.quantity} disabled={locked} onChange={(e) => setLine(i, { quantity: e.target.value })} />
                </td>
                <td>
                  {choices.length === 0 ? (
                    <span className="muted">{t("mat.no_rule")}</span>
                  ) : (
                    <select className="select" value={String(line.account_id)} disabled={locked} onChange={(e) => setLine(i, { account_id: Number(e.target.value) || 0 })}>
                      <option value="0">{t("mat.pick_account")}</option>
                      {choices.map((id) => (
                        <option key={id} value={id}>{accLabel(id)}</option>
                      ))}
                    </select>
                  )}
                </td>
                <td>{line.amount || ""}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {!locked && (
        <button
          type="button"
          className="btn"
          onClick={() => setLines((prev) => [...prev, { product_id: 0, quantity: "1", account_id: 0, inventory_account_id: 0 }])}
        >
          {t("mat.add_line")}
        </button>
      )}
      <div className="form-actions">
        {!locked && (
          <button className="btn btn-primary" disabled={busy || locationId <= 0}>
            {t("mat.save")}
          </button>
        )}
        {!creating && !locked && (
          <button type="button" className="btn btn-primary" disabled={busy || locationId <= 0} onClick={() => act(`/v1/material-issues/${doc.id}/confirm`)}>
            {t("mat.confirm")}
          </button>
        )}
        {!creating && locked && (
          <button type="button" className="btn" disabled={busy} onClick={() => act(`/v1/material-issues/${doc.id}/unpost`)}>
            {t("mat.unpost")}
          </button>
        )}
        {!creating && !locked && (
          <button type="button" className="btn" disabled={busy} onClick={remove}>
            {t("mat.delete")}
          </button>
        )}
      </div>
      {!creating && (
        <AuditHistoryPanel
          history={doc.audit_history}
          createdBy={doc.created_by}
          createdAt={doc.created_at}
          updatedBy={doc.updated_by}
          updatedAt={doc.updated_at}
          editCount={doc.edit_count}
        />
      )}
    </form>
  );
}

export default function MaterialIssuesPage() {
  return (
    <RequireAuth>
      <Inner />
    </RequireAuth>
  );
}
