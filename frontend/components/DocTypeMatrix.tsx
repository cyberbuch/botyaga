"use client";

// Справочна таблица: кой вид документ в кой дневник влиза (покупки/продажби).
// Маркировка по ППЗДС Приложение № 12; подсветка на избрания вид и посока.

import { DOC_TYPE_REGISTRY } from "../lib/invoice";

export function DocTypeMatrix({ t, direction }: { t: (k: string) => string; direction: string }) {
  return (
    <table className="table" style={{ marginTop: 8 }}>
      <thead>
        <tr>
          <th>{t("invoices.doc_code")}</th>
          <th>{t("invoices.document_type")}</th>
          <th>{t("invoices.direction.in")}</th>
          <th>{t("invoices.direction.out")}</th>
        </tr>
      </thead>
      <tbody>
        {DOC_TYPE_REGISTRY.map((d) => {
          const applies = direction === "in" ? d.in : d.out;
          return (
            <tr key={d.code} style={applies ? undefined : { opacity: 0.45 }}>
              <td>{d.code}</td>
              <td>{t(`invoices.document_type.${d.code}`)}</td>
              <td>{d.in ? "✓" : "—"}</td>
              <td>{d.out ? "✓" : "—"}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
