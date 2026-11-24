"use client";

import { Fragment, useMemo } from "react";
import { formatBgDate } from "../../lib/dates";
import {
  ChronoData,
  CorrAccount,
  FirmHead,
  LedgerData,
  TrialData,
  TrialMode,
  TrialRow,
  firmLine,
} from "./types";

export function Num({ v }: { v: string }) {
  return <td className="num">{v}</td>;
}

export function FirmTableRow({ d, cols }: { d: FirmHead; cols: number }) {
  const line = firmLine(d);
  if (!line) return null;
  return (
    <tr>
      <th colSpan={cols} style={{ textAlign: "left", fontWeight: 700 }}>
        {line}
      </th>
    </tr>
  );
}

export function TrialTable({
  data,
  t,
}: {
  data: TrialData;
  t: (k: string) => string;
}) {
  const tot = data.totals;
  const mode: TrialMode = data.mode ?? "accounts";

  // При избрана сметка: сметката е заглавие, под нея — нейните контрагенти.
  const groups = useMemo(() => {
    if (mode !== "by_account_cp") return [];
    const m = new Map<string, { number: string; name: string; rows: TrialRow[] }>();
    for (const r of data.rows ?? []) {
      const key = r.account_number ?? "";
      const g = m.get(key) ?? { number: key, name: r.account_name ?? "", rows: [] };
      g.rows.push(r);
      m.set(key, g);
    }
    return [...m.values()];
  }, [mode, data.rows]);

  return (
    <div className="table-wrap print-sheet">
      <table className="table">
        <thead>
          <FirmTableRow d={data} cols={mode === "accounts" ? 8 : 9} />
          <tr>
            {mode === "accounts" && (
              <>
                <th>{t("reports.col.account")}</th>
                <th>{t("reports.col.name")}</th>
              </>
            )}
            {mode === "by_account_cp" && (
              <>
                <th>{t("reports.col.account")}</th>
                <th>{t("reports.col.name")}</th>
                <th>{t("reports.col.counterpart")}</th>
              </>
            )}
            <th className="num">{t("reports.col.od")}</th>
            <th className="num">{t("reports.col.oc")}</th>
            <th className="num">{t("reports.col.td")}</th>
            <th className="num">{t("reports.col.tc")}</th>
            <th className="num">{t("reports.col.cd")}</th>
            <th className="num">{t("reports.col.cc")}</th>
          </tr>
        </thead>
        <tbody>
          {mode === "accounts" &&
            (data.rows ?? []).map((r) => (
              <tr key={`${r.account_number}/${r.counterpart_name}`}>
                <td>{r.account_number}</td>
                <td>{r.account_name}</td>
                <Num v={r.opening_debit} />
                <Num v={r.opening_credit} />
                <Num v={r.turnover_debit} />
                <Num v={r.turnover_credit} />
                <Num v={r.closing_debit} />
                <Num v={r.closing_credit} />
              </tr>
            ))}

          {mode === "by_account_cp" &&
            groups.map((g) => (
              <Fragment key={g.number}>
                <tr className="report-group-head">
                  <td colSpan={9}>
                    {g.number} · {g.name}
                  </td>
                </tr>
                {g.rows.map((r, i) => (
                  <tr key={`${r.counterpart_name}/${i}`}>
                    <td colSpan={2} />
                    <td>{r.counterpart_name}</td>
                    <Num v={r.opening_debit} />
                    <Num v={r.opening_credit} />
                    <Num v={r.turnover_debit} />
                    <Num v={r.turnover_credit} />
                    <Num v={r.closing_debit} />
                    <Num v={r.closing_credit} />
                  </tr>
                ))}
              </Fragment>
            ))}

        </tbody>
        {tot && (
          <tfoot>
            <tr>
              <td colSpan={mode === "accounts" ? 2 : 3}>{t("reports.total")}</td>
              <Num v={tot.opening_debit} />
              <Num v={tot.opening_credit} />
              <Num v={tot.turnover_debit} />
              <Num v={tot.turnover_credit} />
              <Num v={tot.closing_debit} />
              <Num v={tot.closing_credit} />
            </tr>
          </tfoot>
        )}
      </table>
    </div>
  );
}

export function ChronoTable({
  data,
  t,
}: {
  data: ChronoData;
  t: (k: string) => string;
}) {
  return (
    <div className="table-wrap print-sheet">
      <table className="table">
        <thead>
          <FirmTableRow d={data} cols={9} />
          <tr>
            <th>{t("reports.col.n")}</th>
            <th>{t("reports.col.date")}</th>
            <th>{t("reports.col.document")}</th>
            <th>{t("reports.col.description")}</th>
            <th>{t("reports.col.counterpart")}</th>
            <th>{t("reports.col.debit_acc")}</th>
            <th>{t("reports.col.credit_acc")}</th>
            <th className="num">{t("reports.col.debit")}</th>
            <th className="num">{t("reports.col.credit")}</th>
          </tr>
        </thead>
        <tbody>
          {(data.rows ?? []).map((r) => (
            <tr key={r.row_number}>
              <td>{r.row_number}</td>
              <td>{formatBgDate(r.date)}</td>
              <td>{r.document_number}</td>
              <td>{r.description}</td>
              <td>{r.counterpart_name}</td>
              <td>{r.debit_account}</td>
              <td>{r.credit_account}</td>
              <Num v={r.debit_amount} />
              <Num v={r.credit_amount} />
            </tr>
          ))}
        </tbody>
        {data.totals && (
          <tfoot>
            <tr>
              <td colSpan={7}>{t("reports.total")}</td>
              <Num v={data.totals.debit_amount} />
              <Num v={data.totals.credit_amount} />
            </tr>
          </tfoot>
        )}
      </table>
    </div>
  );
}

export function LedgerTables({
  data,
  t,
}: {
  data: LedgerData;
  t: (k: string) => string;
}) {
  return (
    <div className="print-sheet">
      {(data.accounts ?? []).map((acc, idx) => (
        <div key={acc.account_number} style={{ marginBottom: 28 }}>
          <h3 className="report-account" style={{ padding: "8px 12px", margin: "0 0 8px" }}>
            {acc.account_number} {acc.account_name}
          </h3>
          <div className="table-wrap">
            <table className="table">
              <thead>
                {idx === 0 ? <FirmTableRow d={data} cols={5} /> : null}
                <tr>
                  <th>{t("reports.col.date")}</th>
                  <th>{t("reports.col.document")}</th>
                  <th>{t("reports.col.description")}</th>
                  <th className="num">{t("reports.col.debit")}</th>
                  <th className="num">{t("reports.col.credit")}</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td colSpan={3}>{t("reports.opening")}</td>
                  <Num v={acc.opening_debit} />
                  <Num v={acc.opening_credit} />
                </tr>
                {(acc.transactions ?? []).map((tx, i) => (
                  <tr key={`${acc.account_number}-${i}`}>
                    <td>{formatBgDate(tx.date)}</td>
                    <td>{tx.document_number}</td>
                    <td>{tx.description}</td>
                    <Num v={tx.debit} />
                    <Num v={tx.credit} />
                  </tr>
                ))}
                <tr>
                  <td colSpan={3}>{t("reports.turnover")}</td>
                  <Num v={acc.turnover_debit} />
                  <Num v={acc.turnover_credit} />
                </tr>
                <tr>
                  <td colSpan={3}>{t("reports.closing")}</td>
                  <Num v={acc.closing_debit} />
                  <Num v={acc.closing_credit} />
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      ))}
    </div>
  );
}

export function CorrSide({
  title,
  accounts,
  t,
  firm,
  lead,
}: {
  title: string;
  accounts: CorrAccount[];
  t: (k: string) => string;
  firm: FirmHead;
  lead: "debit" | "credit";
}) {
  return (
    <div style={{ marginBottom: 32 }}>
      <h3 style={{ margin: "0 0 12px" }}>{title}</h3>
      {accounts.length === 0 ? (
        <div className="muted">{t("common.empty")}</div>
      ) : (
        accounts.map((acc, idx) => (
          <div key={`${title}-${acc.account_number}`} style={{ marginBottom: 28 }}>
            <h3 className="report-account" style={{ padding: "8px 12px", margin: "0 0 8px" }}>
              {acc.account_number} {acc.account_name}
            </h3>
            <div className="table-wrap">
              <table className="table">
                <thead>
                  {idx === 0 ? <FirmTableRow d={firm} cols={3} /> : null}
                  <tr>
                    <th>{t("reports.col.correspondent")}</th>
                    <th className="num">{t("reports.col.debit")}</th>
                    <th className="num">{t("reports.col.credit")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>{t("reports.opening")}</td>
                    <Num v={acc.opening_debit} />
                    <Num v={acc.opening_credit} />
                  </tr>
                  {(acc.rows ?? []).map((row, i) => (
                    <tr key={`${acc.account_number}-${row.correspondent}-${i}`}>
                      <td>
                        {lead === "debit" ? "Кт " : "Дт "}
                        {row.correspondent}
                        {row.correspondent_name ? ` ${row.correspondent_name}` : ""}
                      </td>
                      <Num v={row.debit} />
                      <Num v={row.credit} />
                    </tr>
                  ))}
                  <tr>
                    <td>{t("reports.turnover")}</td>
                    <Num v={acc.turnover_debit} />
                    <Num v={acc.turnover_credit} />
                  </tr>
                  <tr>
                    <td>{t("reports.closing")}</td>
                    <Num v={acc.closing_debit} />
                    <Num v={acc.closing_credit} />
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        ))
      )}
    </div>
  );
}
