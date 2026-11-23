"use client";

import { RequireAuth } from "../../../components/RequireAuth";
import { CrudPage, CrudConfig } from "../../../components/CrudPage";

const config: CrudConfig = {
  endpoint: "/destinations",
  titleKey: "transport.destinations",
  fields: [
    { name: "country", labelKey: "transport.country", type: "text", required: true },
    { name: "city", labelKey: "transport.city", type: "text" },
    {
      name: "kind",
      labelKey: "transport.kind",
      type: "select",
      default: "abroad",
      options: [
        { value: "domestic", labelKey: "transport.kind.domestic" },
        { value: "abroad", labelKey: "transport.kind.abroad" },
      ],
    },
    { name: "per_diem", labelKey: "transport.per_diem", type: "text", default: "0" },
    { name: "per_diem_no_overnight", labelKey: "transport.per_diem_no_overnight", type: "text", default: "0" },
    { name: "lodging_limit", labelKey: "transport.lodging_limit", type: "text", default: "0" },
    { name: "active", labelKey: "transport.active", type: "checkbox", default: "1" },
  ],
  columns: ["country", "city", "kind", "per_diem", "per_diem_no_overnight", "lodging_limit"],
};

export default function DestinationsPage() {
  return (
    <RequireAuth>
      <CrudPage config={config} transport />
    </RequireAuth>
  );
}
