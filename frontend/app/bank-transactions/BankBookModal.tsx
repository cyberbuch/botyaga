"use client";

// Ръчно осчетоводяване на банкова транзакция — модалът е като „Нов запис“ в
// счетоводния дневник: редове със сметка, посока, количество, валута и курс
// (стойността в базова валута е производна = количество × курс), курс от ЕЦБ,
// проверка за баланс. Така валутни операции с ръчна корекция (напр. превод
// USD→EUR по курс ЕЦБ + отделен ред за банковата комисионна) стават с един
// или повече редове.

import { useMemo } from "react";
import {
  Account,
  BankTransaction,
  BookLineDraft,
  BookPreview,
  Counterpart,
} from "./types";
import { fmtAmount, isPositive } from "./helpers";
import { CounterpartSelect } from "./BankTxSelects";

function accountLabel(accounts: Account[], id: string): string {
  const a = accounts.find((x) => String(x.id) === id);
  return a ? `${a.number} ${a.name}` : "";
}

export function BankBookModal(props: {
  t: (k: string) => string;
  bookTx: BankTransaction | null;
  setBookTx: (v: BankTransaction | null) => void;
  counterparts: Counterpart[];
  chartAccounts: Account[];
  bookCpId: number;
  bookCpSearch: string;
  setBookCpSearch: (v: string) => void;
  setBookCpId: (v: number) => void;
  bookDate: string;
  setBookDate: (v: string) => void;
  bookDesc: string;
  setBookDesc: (v: string) => void;
  bookLines: BookLineDraft[];
  setBookLine: (
    i: number,
    f: "accountId" | "direction" | "amount" | "currency" | "fxQuantity" | "fxRate",
    v: string
  ) => void;
  addBookLine: () => void;
  removeBookLine: (i: number) => void;
  fetchFxRate: (i: number) => void;
  accountModalFor: number | null;
  setAccountModalFor: (v: number | null) => void;
  accountQuery: string;
  setAccountQuery: (v: string) => void;
  baseCurrency: string;
  balanced: boolean;
  debitSum: number;
  creditSum: number;
  bookLoading: boolean;
  bookPreview: BookPreview | null;
  formError: string;
  handleBook: () => void;
}) {
  const {
    t,
    bookTx,
    setBookTx,
    counterparts,
    chartAccounts,
    bookCpId,
    bookCpSearch,
    setBookCpSearch,
    setBookCpId,
    bookDate,
    setBookDate,
    bookDesc,
    setBookDesc,
    bookLines,
    setBookLine,
    addBookLine,
    removeBookLine,
    fetchFxRate,
    accountModalFor,
    setAccountModalFor,
    accountQuery,
    setAccountQuery,
    baseCurrency,
    balanced,
    debitSum,
    creditSum,
    bookLoading,
    bookPreview,
    formError,
    handleBook,
  } = props;

  // Всяка сметка може да е валутна — счетоводството се води в базовата
  // валута (EUR), а валутата/курсът на реда са свободни.
  const filteredAccounts = useMemo(() => {
    const s = accountQuery.trim().toLowerCase();
    if (!s) return chartAccounts;
    return chartAccounts.filter((a) =>
      `${a.number} ${a.name}`.toLowerCase().includes(s)
    );
  }, [chartAccounts, accountQuery]);

  if (!bookTx) return null;

  const canSave =
    !bookLoading &&
    balanced &&
    !!bookPreview &&
    bookPreview.balanced !== false &&
    bookLines.every((l) => l.accountId && l.amount);

  return (
    <>
      <div className="modal-backdrop" onClick={() => setBookTx(null)}>
        <div
          className="card modal modal-lg"
          onClick={(e) => e.stopPropagation()}
        >
          <h2 className="modal-title">{t("bank_tx.book_title")}</h2>

          <div className="summary-grid" style={{ marginBottom: 16 }}>
            <div className="summary-box">
              <div className="summary-label">{t("bank_tx.date")}</div>
              <div className="summary-value">{bookTx.transaction_date}</div>
            </div>
            <div className="summary-box">
              <div className="summary-label">{t("bank_tx.amount")}</div>
              <div
                className="summary-value"
                style={{
                  color: isPositive(bookTx.amount)
                    ? "var(--success)"
                    : "var(--danger)",
                }}
              >
                {fmtAmount(bookTx.amount)} {bookTx.currency}
              </div>
            </div>
            {bookTx.reference ? (
              <div className="summary-box">
                <div className="summary-label">{t("bank_tx.reference")}</div>
                <div className="summary-value" style={{ fontSize: 13 }}>
                  {bookTx.reference}
                </div>
              </div>
            ) : null}
            {bookTx.bank_account_id ? (
              <div className="summary-box">
                <div className="summary-label">{t("bank_tx.bank_account")}</div>
                <div className="summary-value" style={{ fontSize: 13 }}>
                  {bookTx.bank_account_name || `#${bookTx.bank_account_id}`}
                </div>
              </div>
            ) : null}
          </div>

          {bookTx.counterpart_name ? (
            <p className="muted" style={{ margin: "0 0 12px" }}>
              {t("bank_tx.bank_counterpart")}: {bookTx.counterpart_name}
            </p>
          ) : null}

          <div className="form-grid">
            <div className="field">
              <label className="label">{t("journal.entry_date")} *</label>
              <input
                className="input"
                type="date"
                value={bookDate}
                onChange={(e) => setBookDate(e.target.value)}
                required
              />
            </div>
            <div className="field">
              <label className="label">{t("journal.description")} *</label>
              <input
                className="input"
                value={bookDesc}
                onChange={(e) => setBookDesc(e.target.value)}
                required
              />
            </div>
            <div className="field">
              <label className="label">{t("bank_tx.counterpart")}</label>
              <CounterpartSelect
                t={t}
                counterparts={counterparts}
                value={bookCpId}
                search={bookCpSearch}
                onSearch={setBookCpSearch}
                onChange={setBookCpId}
              />
            </div>
          </div>

          <h3 style={{ margin: "16px 0 8px" }}>{t("journal.lines")}</h3>
          <p className="muted" style={{ margin: "0 0 8px" }}>
            {t("bank_tx.book_hint")}
          </p>

          <div className="journal-lines-novat">
            <div className="journal-line-head">
              <span>{t("journal.account")}</span>
              <span>
                {t("journal.debit")} / {t("journal.credit")}
              </span>
              <span>{t("journal.quantity")}</span>
              <span />
              <span>{t("journal.currency")}</span>
              <span>{t("journal.fx_rate")}</span>
              <span>{t("journal.amount")}</span>
              <span />
            </div>
            {bookLines.map((l, i) => (
              <div key={i} className="journal-line-row">
                <button
                  type="button"
                  className={`btn picker-trigger${l.accountId ? "" : " picker-empty"}`}
                  onClick={() => setAccountModalFor(i)}
                >
                  {accountLabel(chartAccounts, l.accountId) ||
                    (l.accountId ? l.accountId : `${t("journal.account")}…`)}
                </button>
                <select
                  className="select"
                  value={l.direction}
                  onChange={(e) => setBookLine(i, "direction", e.target.value)}
                >
                  <option value="debit">{t("journal.debit")}</option>
                  <option value="credit">{t("journal.credit")}</option>
                </select>
                <input
                  className="input"
                  inputMode="decimal"
                  placeholder="0.00"
                  title={t("journal.quantity_hint")}
                  value={l.fxQuantity}
                  onChange={(e) => setBookLine(i, "fxQuantity", e.target.value)}
                />
                <button
                  type="button"
                  className="btn btn-danger btn-sm"
                  onClick={() => removeBookLine(i)}
                  disabled={bookLines.length < 2}
                >
                  ✕
                </button>
                <div className="journal-fx-row">
                  <input
                    className="input"
                    placeholder={baseCurrency}
                    title={t("journal.currency")}
                    maxLength={3}
                    value={l.currency}
                    onChange={(e) =>
                      setBookLine(i, "currency", e.target.value.toUpperCase())
                    }
                  />
                  <input
                    className="input"
                    inputMode="decimal"
                    placeholder={t("journal.fx_rate")}
                    title={t("journal.fx_rate")}
                    value={l.fxRate}
                    onChange={(e) => setBookLine(i, "fxRate", e.target.value)}
                  />
                  <input
                    className="input journal-value-derived"
                    inputMode="decimal"
                    placeholder={t("journal.amount")}
                    title={t("journal.value_derived_hint")}
                    value={l.amount}
                    readOnly
                  />
                  <button
                    type="button"
                    className="btn btn-sm"
                    onClick={() => fetchFxRate(i)}
                    disabled={!l.currency || !bookDate}
                    title={t("journal.fx_fetch")}
                  >
                    {t("journal.fx_fetch")}
                  </button>
                </div>
              </div>
            ))}
          </div>

          <button type="button" className="btn btn-sm" onClick={addBookLine}>
            + {t("journal.add_line")}
          </button>

          <div className="muted" style={{ marginTop: 12 }}>
            {t("journal.balance")}: {debitSum.toFixed(2)} / {creditSum.toFixed(2)}{" "}
            {balanced ? "✓" : "✗"}
          </div>

          {formError && <div className="error-text">{formError}</div>}
          <div className="form-actions">
            <button
              className="btn"
              onClick={() => setBookTx(null)}
              type="button"
            >
              {t("common.cancel")}
            </button>
            <button
              className="btn btn-primary"
              onClick={handleBook}
              disabled={!canSave}
              type="button"
            >
              {bookLoading ? t("common.loading") : t("bank_tx.book")}
            </button>
          </div>
        </div>
      </div>

      {accountModalFor !== null && (
        <div
          className="modal-backdrop"
          onClick={() => {
            setAccountModalFor(null);
            setAccountQuery("");
          }}
        >
          <div className="card modal picker-modal" onClick={(e) => e.stopPropagation()}>
            <h2 className="modal-title">{t("journal.pick_account")}</h2>
            <input
              className="input"
              autoFocus
              value={accountQuery}
              onChange={(e) => setAccountQuery(e.target.value)}
              placeholder={t("common.search")}
            />
            <div className="picker-list">
              {filteredAccounts.map((a) => (
                <button
                  type="button"
                  key={a.id}
                  className="picker-item"
                  onClick={() => {
                    setBookLine(accountModalFor, "accountId", String(a.id));
                    setAccountModalFor(null);
                    setAccountQuery("");
                  }}
                >
                  <b>{a.number}</b>
                  <span className="muted">{a.name}</span>
                </button>
              ))}
              {filteredAccounts.length === 0 && (
                <div className="muted">{t("common.empty")}</div>
              )}
            </div>
            <div className="form-actions" style={{ marginTop: 12 }}>
              <button
                type="button"
                className="btn"
                onClick={() => {
                  setAccountModalFor(null);
                  setAccountQuery("");
                }}
              >
                {t("common.cancel")}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
