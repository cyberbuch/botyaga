"use client";

// Банкови транзакции: импорт от файл (преглед + дубликати), ръчно
// осчетоводяване (модал като „Нов запис“ в дневника — редове с валута и курс,
// напр. USD→EUR по курс ЕЦБ + ред за банковата комисионна), разнасяне и
// връщане в чернова. Сумите остават десимални низове.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { RequireAuth } from "../../components/RequireAuth";
import { useI18n } from "../../components/I18nProvider";
import { api, fetchAll, getActiveCompany, ACTIVE_COMPANY_EVENT } from "../../lib/api";
import {
  Account,
  BankAccount,
  BankTransaction,
  BookLineDraft,
  BookPreview,
  Counterpart,
  JeLine,
  Preview,
  emptyBookLine,
} from "./types";
import { fmtAmount, isPositive, matchCounterpart } from "./helpers";
import { BankBookModal } from "./BankBookModal";
import { BankTxModals } from "./BankTxModals";
import { BankRulesPanel } from "./BankRulesPanel";
import { Pagination } from "../../components/Pagination";

interface ProcDetail {
  id: number;
  status: string;
  rule?: string;
  account?: string;
  counterpart?: string;
  amount?: string;
  text?: string;
  error?: string;
}
interface ProcResult {
  matched: number;
  unmatched: number;
  errors: number;
  details: ProcDetail[];
}

const PAGE_SIZE = 50;

function BankTransactionsInner() {
  const { t } = useI18n();
  const [accounts, setAccounts] = useState<BankAccount[]>([]);
  const [chartAccounts, setChartAccounts] = useState<Account[]>([]);
  const [counterparts, setCounterparts] = useState<Counterpart[]>([]);
  const [rows, setRows] = useState<BankTransaction[]>([]);
  const [selectedAccount, setSelectedAccount] = useState("");
  const [filterStatus, setFilterStatus] = useState("");
  const [q, setQ] = useState("");
  const [tab, setTab] = useState<"tx" | "rules">("tx");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [selected, setSelected] = useState<number[]>([]);
  const [bulkBusy, setBulkBusy] = useState(false);
  const [procPreview, setProcPreview] = useState<ProcResult | null>(null);
  const [procBusy, setProcBusy] = useState(false);
  const [offset, setOffset] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  const [preview, setPreview] = useState<Preview | null>(null);
  const [previewOpen, setPreviewOpen] = useState(false);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [pendingContent, setPendingContent] = useState("");
  const [importing, setImporting] = useState(false);

  const [bookTx, setBookTx] = useState<BankTransaction | null>(null);
  const [bookCpId, setBookCpId] = useState(0);
  const [bookCpSearch, setBookCpSearch] = useState("");
  const [bookDate, setBookDate] = useState("");
  const [bookDesc, setBookDesc] = useState("");
  const [bookLines, setBookLines] = useState<BookLineDraft[]>([emptyBookLine()]);
  const [bookLoading, setBookLoading] = useState(false);
  const [bookPreview, setBookPreview] = useState<BookPreview | null>(null);
  const [bookFormError, setBookFormError] = useState("");
  const [accountModalFor, setAccountModalFor] = useState<number | null>(null);
  const [accountQuery, setAccountQuery] = useState("");
  // базова валута на активната фирма — за нея курсът е 1
  const [baseCurrency, setBaseCurrency] = useState("EUR");

  useEffect(() => {
    const readBase = () => {
      getActiveCompany()
        .then((c) => {
          const cur = (c as { currency?: unknown }).currency;
          if (typeof cur === "string" && cur) setBaseCurrency(cur.toUpperCase());
        })
        .catch(() => {});
    };
    readBase();
    window.addEventListener(ACTIVE_COMPANY_EVENT, readBase);
    return () => window.removeEventListener(ACTIVE_COMPANY_EVENT, readBase);
  }, []);

  const [reallocTx, setReallocTx] = useState<BankTransaction | null>(null);
  const [reallocAccount, setReallocAccount] = useState(0);
  const [reallocCpId, setReallocCpId] = useState(0);
  const [reallocCpSearch, setReallocCpSearch] = useState("");
  const [reallocAccSearch, setReallocAccSearch] = useState("");
  const [reallocLines, setReallocLines] = useState<JeLine[]>([]);
  const [reallocLoading, setReallocLoading] = useState(false);

  const fileInputRef = useRef<HTMLInputElement>(null);

  const loadMeta = useCallback(async () => {
    try {
      const [b, a, c] = await Promise.all([
        fetchAll<BankAccount>("/v1/bank-accounts"),
        fetchAll<Account>("/v1/accounts"),
        fetchAll<Counterpart>("/v1/counterparts"),
      ]);
      setAccounts(b);
      setChartAccounts(a);
      setCounterparts(c);
    } catch {
      /* silent */
    }
  }, []);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const extra: Record<string, string | undefined> = {};
      if (selectedAccount) extra.bank_account_id = selectedAccount;
      if (filterStatus) extra.status = filterStatus;
      setRows(await fetchAll<BankTransaction>("/v1/bank-transactions", extra));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [selectedAccount, filterStatus]);

  useEffect(() => {
    loadMeta();
  }, [loadMeta]);

  useEffect(() => {
    load();
  }, [load]);

  const filteredRows = useMemo(() => {
    const s = q.trim().toLowerCase();
    return rows.filter((tx) => {
      if (dateFrom && tx.transaction_date < dateFrom) return false;
      if (dateTo && tx.transaction_date > dateTo) return false;
      if (!s) return true;
      return [tx.description, tx.counterpart_name, tx.reference, tx.amount, tx.transaction_date]
        .join(" ")
        .toLowerCase()
        .includes(s);
    });
  }, [rows, q, dateFrom, dateTo]);

  const pageCount = Math.max(1, Math.ceil(filteredRows.length / PAGE_SIZE));
  const page = Math.min(Math.floor(offset / PAGE_SIZE), pageCount - 1);
  const start = page * PAGE_SIZE;
  const pagedRows = filteredRows.slice(start, start + PAGE_SIZE);

  const statusCounts = useMemo(() => ({
    pending: rows.filter((tx) => !tx.is_booked).length,
    processed: rows.filter((tx) => tx.is_booked && !tx.is_allocated).length,
    booked: rows.filter((tx) => tx.is_allocated).length,
  }), [rows]);

  const toggleSel = (id: number, on: boolean) =>
    setSelected((p) => (on ? [...p, id] : p.filter((x) => x !== id)));
  const allSelected = pagedRows.length > 0 && pagedRows.every((tx) => selected.includes(tx.id));
  const toggleAll = (on: boolean) =>
    setSelected((p) =>
      on
        ? Array.from(new Set([...p, ...pagedRows.map((tx) => tx.id)]))
        : p.filter((id) => !pagedRows.some((tx) => tx.id === id))
    );

  const handleBulkDelete = async () => {
    if (selected.length === 0) return;
    if (!window.confirm(t("bank_tx.bulk_confirm"))) return;
    setBulkBusy(true);
    setError("");
    try {
      const r = await api.post<{ deleted: number; failed: number }>("/v1/bank-transactions/bulk/delete", { ids: selected });
      setSuccess(`${t("bank_tx.bulk_deleted")}: ${r.deleted}, ${t("bank_tx.bulk_failed")}: ${r.failed}`);
      setSelected([]);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBulkBusy(false);
    }
  };

  const openProcess = async () => {
    setProcBusy(true);
    setError("");
    try {
      const r = await api.post<ProcResult>("/v1/bank-transactions/auto-allocate/preview", {});
      setProcPreview(r);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setProcBusy(false);
    }
  };

  const handleFile = async (file: File) => {
    if (!selectedAccount) {
      setError(t("bank_tx.select_account"));
      return;
    }
    setError("");
    setSuccess("");
    const content = await file.text();
    setPendingContent(content);
    setPreview(null);
    setPreviewOpen(true);
    setPreviewLoading(true);
    try {
      const data = await api.post<Preview>("/v1/bank-transactions/preview", {
        bank_account_id: Number(selectedAccount),
        file_content: content,
      });
      setPreview(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setPreviewOpen(false);
    } finally {
      setPreviewLoading(false);
    }
  };

  const handleImport = async () => {
    setImporting(true);
    try {
      const r = await api.post<{ imported: number }>("/v1/bank-transactions/import", {
        bank_account_id: Number(selectedAccount),
        file_content: pendingContent,
      });
      const msg = t("bank_tx.imported_pending").replace("{n}", String(r.imported));
      setSuccess(msg);
      setError("");
      setPreviewOpen(false);
      setPreview(null);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setImporting(false);
    }
  };

  const bankGlId = useCallback(
    (tx: BankTransaction | null): number => {
      if (!tx) return 0;
      const ba = accounts.find((a) => a.id === tx.bank_account_id);
      return ba?.gl_account_id ?? 0;
    },
    [accounts]
  );

  const openBook = (tx: BankTransaction) => {
    const m = matchCounterpart(tx.counterpart_name || "", counterparts);
    const gl = bankGlId(tx);
    const amt = Math.abs(parseFloat(String(tx.amount).replace(",", ".")) || 0);
    const amtStr = amt.toFixed(2);
    const cur = (tx.currency || "").trim().toUpperCase();
    const foreign = cur !== "" && cur !== baseCurrency;
    // Първият ред е банковата ГЛ сметка с посоката от знака на транзакцията;
    // при валутна транзакция — във валутата на транзакцията (курс по ЕЦБ).
    const first: BookLineDraft = {
      accountId: gl > 0 ? String(gl) : "",
      direction: isPositive(tx.amount) ? "debit" : "credit",
      amount: amtStr,
      currency: foreign ? cur : "",
      fxQuantity: amtStr,
      fxRate: "1",
    };
    setBookTx(tx);
    setBookCpId(m?.id ?? 0);
    setBookCpSearch(tx.counterpart_name || "");
    setBookDate(tx.transaction_date);
    setBookDesc(tx.description || t("bank_tx.book_title"));
    setBookLines(gl > 0 ? [first] : [emptyBookLine(), emptyBookLine()]);
    setBookPreview(null);
    setBookFormError("");
    setAccountModalFor(null);
    setAccountQuery("");

    // При валутна транзакция всичко се равнява по курса на ЕЦБ — курсът на
    // банковия ред се взима веднага, а разликата (такса/валутна разлика) се
    // добавя на ръка като приход/разход от валутни операции.
    if (foreign && gl > 0) {
      api
        .get<{ rate: string; rate_date: string }>(
          `/v1/exchange-rates/cross?from=${encodeURIComponent(cur)}&to=${encodeURIComponent(baseCurrency)}&date=${tx.transaction_date}`
        )
        .then((r) => {
          setBookLines((prev) =>
            prev.map((x, idx) => {
              if (idx !== 0) return x;
              const rr = parseFloat(r.rate);
              const q = parseFloat(x.fxQuantity);
              const next = { ...x, fxRate: r.rate };
              if (!Number.isNaN(q) && !Number.isNaN(rr)) {
                next.amount = (q * rr).toFixed(2);
              }
              return next;
            })
          );
        })
        .catch(() => {
          /* курсът остава 1 — може да се смени ръчно или от бутона ЕЦБ */
        });
    }
  };

  // Редовете на ръчното осчетоводяване — като в дневника: стойността е
  // производна = количество × курс; за базовата валута курсът е 1.
  const setBookLine = (
    i: number,
    f: "accountId" | "direction" | "amount" | "currency" | "fxQuantity" | "fxRate",
    v: string
  ) =>
    setBookLines((prev) =>
      prev.map((l, idx) => {
        if (idx !== i) return l;
        const next = { ...l, [f]: v };
        if (f === "currency") {
          const c = v.trim().toUpperCase();
          if (c === "" || c === baseCurrency) next.fxRate = "1";
        }
        if (f === "fxQuantity" || f === "fxRate" || f === "currency") {
          const q = parseFloat(next.fxQuantity);
          const r = parseFloat(next.fxRate || "1");
          if (!Number.isNaN(q) && !Number.isNaN(r)) next.amount = (q * r).toFixed(2);
        }
        return next;
      })
    );

  const addBookLine = () => setBookLines((prev) => [...prev, emptyBookLine()]);
  const removeBookLine = (i: number) =>
    setBookLines((prev) => prev.filter((_, idx) => idx !== i));

  // Курс от ЕЦБ (кръстосан през базовата валута) as-of датата на записа.
  const fetchFxRate = async (i: number) => {
    const l = bookLines[i];
    const cur = l.currency.trim().toUpperCase();
    if (!cur || !bookDate) return;
    try {
      const r = await api.get<{ rate: string; rate_date: string }>(
        `/v1/exchange-rates/cross?from=${encodeURIComponent(cur)}&to=${encodeURIComponent(baseCurrency)}&date=${bookDate}`
      );
      setBookLines((prev) =>
        prev.map((x, idx) => {
          if (idx !== i) return x;
          const next = { ...x, fxRate: r.rate };
          const q = parseFloat(x.fxQuantity);
          const rr = parseFloat(r.rate);
          if (!Number.isNaN(q) && !Number.isNaN(rr)) next.amount = (q * rr).toFixed(2);
          return next;
        })
      );
    } catch (err) {
      setBookFormError(err instanceof Error ? err.message : String(err));
    }
  };

  const bookDebitSum = bookLines
    .filter((l) => l.direction === "debit")
    .reduce((acc, l) => acc + (parseFloat(l.amount) || 0), 0);
  const bookCreditSum = bookLines
    .filter((l) => l.direction === "credit")
    .reduce((acc, l) => acc + (parseFloat(l.amount) || 0), 0);
  const bookBalanced = Math.abs(bookDebitSum - bookCreditSum) < 0.0001;

  const bookPayload = useCallback(() => {
    const payload: Record<string, unknown> = {
      entry_date: bookDate,
      description: bookDesc,
      lines: bookLines.map((l) => {
        const cur = l.currency.trim().toUpperCase();
        const foreign = cur !== "" && cur !== baseCurrency;
        // За основната валута количеството съвпада със стойността (курс=1).
        const quantity = l.fxQuantity !== "" ? l.fxQuantity : l.amount;
        return {
          account_id: Number(l.accountId) || 0,
          direction: l.direction,
          amount: l.amount,
          currency: foreign ? cur : "",
          fx_quantity: quantity,
          fx_rate: foreign ? l.fxRate || "1" : "1",
        };
      }),
    };
    if (bookCpId > 0) payload.counterpart_id = bookCpId;
    return payload;
  }, [bookLines, bookDate, bookDesc, bookCpId, baseCurrency]);

  const openReallocate = async (tx: BankTransaction) => {
    const m = matchCounterpart(tx.counterpart_name || "", counterparts);
    setReallocTx(tx);
    setReallocAccount(0);
    setReallocCpId(m?.id ?? 0);
    setReallocCpSearch(tx.counterpart_name || "");
    setReallocAccSearch("");
    setReallocLines([]);
    if (tx.journal_entry_id > 0) {
      try {
        const je = await api.get<{ lines?: JeLine[] }>(
          `/v1/journal/${tx.journal_entry_id}`
        );
        setReallocLines(je.lines ?? []);
      } catch {
        setReallocLines([]);
      }
    }
  };

  // Преглед на ръчния запис (редове + баланс) без да се пише в базата.
  useEffect(() => {
    if (!bookTx) {
      setBookPreview(null);
      return;
    }
    const ready =
      bookDate !== "" &&
      bookLines.length > 0 &&
      bookLines.every((l) => l.accountId && l.amount && l.fxQuantity !== "");
    if (!ready) {
      setBookPreview(null);
      return;
    }
    let cancelled = false;
    api
      .post<BookPreview>(
        `/v1/bank-transactions/${bookTx.id}/book/preview`,
        bookPayload()
      )
      .then((p) => {
        if (!cancelled) setBookPreview(p);
      })
      .catch(() => {
        if (!cancelled) setBookPreview(null);
      });
    return () => {
      cancelled = true;
    };
  }, [bookTx, bookPayload, bookDate, bookLines]);

  const handleBook = async () => {
    if (!bookTx) return;
    if (!bookDate || bookLines.some((l) => !l.accountId || !l.amount)) {
      setBookFormError(t("bank_tx.book_incomplete"));
      return;
    }
    setBookLoading(true);
    setBookFormError("");
    try {
      await api.post(`/v1/bank-transactions/${bookTx.id}/book`, {
        ...bookPayload(),
        confirm: true,
      });
      setSuccess(t("bank_tx.booked"));
      setBookTx(null);
      await load();
    } catch (e) {
      setBookFormError(e instanceof Error ? e.message : String(e));
    } finally {
      setBookLoading(false);
    }
  };

  // Връщане на осчетоводена транзакция в чернова — само в чернова банковите
  // транзакции могат да се редактират (преосчетоводяват) отново.
  const handleUnbook = async (tx: BankTransaction) => {
    if (!window.confirm(t("bank_tx.unbook_confirm"))) return;
    try {
      await api.post(`/v1/bank-transactions/${tx.id}/unbook`, {});
      setSuccess(t("bank_tx.unbooked"));
      setError("");
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const handleReallocate = async () => {
    if (!reallocTx) return;
    if (!reallocAccount) {
      setError(t("bank_tx.pick_account"));
      return;
    }
    const payload: Record<string, number> = { account_id: reallocAccount };
    if (reallocCpId > 0) payload.counterpart_id = reallocCpId;
    setReallocLoading(true);
    try {
      const r = await api.post<{ message: string }>(
        `/v1/bank-transactions/${reallocTx.id}/reallocate`,
        payload
      );
      setSuccess(r.message || t("bank_tx.reallocated"));
      setReallocTx(null);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setReallocLoading(false);
    }
  };

  const handleDelete = async (tx: BankTransaction) => {
    if (!window.confirm(t("common.confirmDelete"))) return;
    try {
      await api.del(`/v1/bank-transactions/${tx.id}`);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const statusBadge = (tx: BankTransaction) => {
    if (tx.is_allocated)
      return (
        <span className="badge badge-success">{t("bank_tx.status.allocated")}</span>
      );
    if (tx.is_booked)
      return (
        <span className="badge badge-warning">{t("bank_tx.status.booked")}</span>
      );
    return <span className="badge badge-danger">{t("bank_tx.status.new")}</span>;
  };

  return (
    <div>
      <div className="page-head">
        <h1 className="page-title">{t("bank_tx.title")}</h1>
        <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
          <select
            className="select"
            value={selectedAccount}
            onChange={(e) => setSelectedAccount(e.target.value)}
          >
            <option value="">{t("bank_tx.all_accounts")}</option>
            {accounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name} ({a.iban})
              </option>
            ))}
          </select>
          <select
            className="select"
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value)}
          >
            <option value="">{t("bank_tx.all_statuses")}</option>
            <option value="new">{t("bank_tx.status.new")}</option>
            <option value="booked">{t("bank_tx.status.booked")}</option>
            <option value="allocated">{t("bank_tx.status.allocated")}</option>
          </select>
          <input
            ref={fileInputRef}
            type="file"
            accept=".xml,.sta,.mt940,.txt,.STA,.csv,.CSV"
            style={{ display: "none" }}
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) handleFile(f);
              e.target.value = "";
            }}
          />
          <button
            className="btn btn-primary"
            onClick={() => fileInputRef.current?.click()}
            type="button"
          >
            {t("bank_tx.import_file")}
          </button>
        </div>
      </div>

      <div className="btn-row" style={{ marginBottom: 12 }}>
        <button
          className={`btn btn-sm${tab === "tx" ? " btn-primary" : ""}`}
          type="button"
          onClick={() => setTab("tx")}
        >
          {t("bank_tx.tab_tx")}
        </button>
        <button
          className={`btn btn-sm${tab === "rules" ? " btn-primary" : ""}`}
          type="button"
          onClick={() => setTab("rules")}
        >
          {t("brules.title")}
        </button>
      </div>

      {error && <div className="error-text">{error}</div>}
      {success && (
        <div className="muted" style={{ color: "var(--success)", marginBottom: 12 }}>
          {success}
        </div>
      )}

      {tab === "tx" && (
        <>
      <div className="card" style={{ marginBottom: 12 }}>
        <input
          className="input"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={t("bank_tx.search_placeholder")}
        />
        <div className="btn-row" style={{ marginTop: 8, flexWrap: "wrap", alignItems: "center" }}>
          <label className="muted" style={{ fontSize: 13 }}>{t("bank_tx.date_from")}</label>
          <input className="input" type="date" style={{ width: 160 }} value={dateFrom} onChange={(e) => { setDateFrom(e.target.value); setOffset(0); }} />
          <label className="muted" style={{ fontSize: 13 }}>{t("bank_tx.date_to")}</label>
          <input className="input" type="date" style={{ width: 160 }} value={dateTo} onChange={(e) => { setDateTo(e.target.value); setOffset(0); }} />
          <button className="btn btn-sm" type="button" disabled={procBusy} onClick={() => void openProcess()}>
            {t("bank_tx.process")}
          </button>
          {selected.length > 0 && (
            <button className="btn btn-sm btn-danger" type="button" disabled={bulkBusy} onClick={() => void handleBulkDelete()}>
              {t("bank_tx.bulk_delete")} ({selected.length})
            </button>
          )}
        </div>
        <div className="btn-row" style={{ marginTop: 8, gap: 16 }}>
          <span className="badge badge-danger">{t("bank_tx.status.new")}: {statusCounts.pending}</span>
          <span className="badge badge-warning">{t("bank_tx.status.booked")}: {statusCounts.processed}</span>
          <span className="badge badge-success">{t("bank_tx.status.allocated")}: {statusCounts.booked}</span>
        </div>
      </div>

      <div className="card">
        {loading ? (
          <div className="content muted">{t("common.loading")}</div>
        ) : filteredRows.length === 0 ? (
          <div className="content muted">{t("bank_tx.empty")}</div>
        ) : (
          <table className="table">
            <thead>
              <tr>
                <th style={{ width: 32 }}>
                  <input type="checkbox" checked={allSelected} onChange={(e) => toggleAll(e.target.checked)} />
                </th>
                <th>{t("bank_tx.date")}</th>
                <th>{t("bank_tx.description")}</th>
                <th>{t("bank_tx.counterpart")}</th>
                <th style={{ textAlign: "right" }}>{t("bank_tx.amount")}</th>
                <th style={{ textAlign: "center" }}>{t("bank_tx.status")}</th>
                <th style={{ textAlign: "right" }}>{t("common.actions")}</th>
              </tr>
            </thead>
            <tbody>
              {pagedRows.map((tx) => (
                <tr key={tx.id}>
                  <td>
                    <input type="checkbox" checked={selected.includes(tx.id)} onChange={(e) => toggleSel(tx.id, e.target.checked)} />
                  </td>
                  <td style={{ whiteSpace: "nowrap" }}>{tx.transaction_date}</td>
                  <td
                    style={{ maxWidth: 300, overflow: "hidden", textOverflow: "ellipsis" }}
                    title={tx.description}
                  >
                    {tx.description}
                  </td>
                  <td>{tx.counterpart_name}</td>
                  <td
                    style={{
                      textAlign: "right",
                      whiteSpace: "nowrap",
                      fontWeight: 500,
                      color: isPositive(tx.amount)
                        ? "var(--success)"
                        : "var(--danger)",
                    }}
                  >
                    {fmtAmount(tx.amount)} {tx.currency}
                  </td>
                  <td style={{ textAlign: "center" }}>{statusBadge(tx)}</td>
                  <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
                    <div className="icon-actions" style={{ justifyContent: "flex-end" }}>
                      {!tx.is_booked && (
                        <>
                          <button className="btn btn-sm" onClick={() => openBook(tx)}>
                            {t("bank_tx.book")}
                          </button>
                          <button
                            className="btn btn-sm btn-danger"
                            onClick={() => handleDelete(tx)}
                          >
                            {t("common.delete")}
                          </button>
                        </>
                      )}
                      {tx.is_booked && !tx.is_allocated && (
                        <button
                          className="btn btn-sm"
                          onClick={() => {
                            void openReallocate(tx);
                          }}
                        >
                          {t("bank_tx.reallocate")}
                        </button>
                      )}
                      {tx.is_booked && (
                        <button
                          className="btn btn-sm"
                          onClick={() => void handleUnbook(tx)}
                          title={t("bank_tx.unbook_hint")}
                        >
                          {t("bank_tx.unbook")}
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        <Pagination
          total={filteredRows.length}
          limit={PAGE_SIZE}
          offset={start}
          onPageChange={setOffset}
        />
      </div>
        </>
      )}

      {tab === "rules" && (
        <BankRulesPanel accounts={chartAccounts} onChanged={() => void load()} />
      )}

      {procPreview && (
        <div className="modal-backdrop" onClick={() => setProcPreview(null)}>
          <div className="card modal picker-modal" style={{ maxWidth: 720 }} onClick={(e) => e.stopPropagation()}>
            <h2 className="modal-title">{t("bank_tx.process")}</h2>
            <p className="muted" style={{ fontSize: 13 }}>
              {t("brules.preview_hint")}: {procPreview.matched} · {procPreview.unmatched} {t("brules.unmatched")}
            </p>
            <div className="picker-list">
              {procPreview.details.filter((d) => d.status === "matched").map((d) => (
                <div key={d.id} className="picker-item">
                  <b>#{d.id} · {d.rule}</b>
                  <span className="muted">
                    {d.account}
                    {d.counterpart ? ` · ${d.counterpart}` : ""} · {d.amount}
                  </span>
                </div>
              ))}
              {procPreview.matched === 0 && <div className="muted">{t("brules.empty")}</div>}
            </div>
            <p className="muted" style={{ fontSize: 13 }}>
              {t("bank_tx.process_manual_hint")}
            </p>
            <div className="form-actions">
              <button className="btn" type="button" onClick={() => setProcPreview(null)}>
                {t("common.close")}
              </button>
            </div>
          </div>
        </div>
      )}

      <BankBookModal
        t={t}
        bookTx={bookTx}
        setBookTx={setBookTx}
        counterparts={counterparts}
        chartAccounts={chartAccounts}
        bookCpId={bookCpId}
        bookCpSearch={bookCpSearch}
        setBookCpSearch={setBookCpSearch}
        setBookCpId={setBookCpId}
        bookDate={bookDate}
        setBookDate={setBookDate}
        bookDesc={bookDesc}
        setBookDesc={setBookDesc}
        bookLines={bookLines}
        setBookLine={setBookLine}
        addBookLine={addBookLine}
        removeBookLine={removeBookLine}
        fetchFxRate={(i) => void fetchFxRate(i)}
        accountModalFor={accountModalFor}
        setAccountModalFor={setAccountModalFor}
        accountQuery={accountQuery}
        setAccountQuery={setAccountQuery}
        baseCurrency={baseCurrency}
        balanced={bookBalanced}
        debitSum={bookDebitSum}
        creditSum={bookCreditSum}
        bookLoading={bookLoading}
        bookPreview={bookPreview}
        formError={bookFormError}
        handleBook={() => void handleBook()}
      />

      <BankTxModals
        t={t}
        counterparts={counterparts}
        chartAccounts={chartAccounts}
        previewOpen={previewOpen}
        setPreviewOpen={setPreviewOpen}
        previewLoading={previewLoading}
        preview={preview}
        importing={importing}
        handleImport={handleImport}
        reallocTx={reallocTx}
        setReallocTx={setReallocTx}
        reallocLines={reallocLines}
        reallocCpId={reallocCpId}
        reallocCpSearch={reallocCpSearch}
        setReallocCpSearch={setReallocCpSearch}
        setReallocCpId={setReallocCpId}
        reallocAccount={reallocAccount}
        reallocAccSearch={reallocAccSearch}
        setReallocAccSearch={setReallocAccSearch}
        setReallocAccount={setReallocAccount}
        handleReallocate={handleReallocate}
        reallocLoading={reallocLoading}
      />
    </div>
  );
}

export default function BankTransactionsPage() {
  return (
    <RequireAuth>
      <BankTransactionsInner />
    </RequireAuth>
  );
}
