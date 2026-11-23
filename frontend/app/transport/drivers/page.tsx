"use client";

import { RequireAuth } from "../../../components/RequireAuth";
import { CrudPage, CrudConfig } from "../../../components/CrudPage";

const config: CrudConfig = {
  endpoint: "/drivers",
  titleKey: "transport.drivers",
  fields: [
    { name: "name", labelKey: "transport.name", type: "text", required: true },
    { name: "egn", labelKey: "transport.egn", type: "text" },
    { name: "license_number", labelKey: "transport.license_number", type: "text" },
    { name: "phone", labelKey: "transport.phone", type: "text" },
    { name: "active", labelKey: "transport.active", type: "checkbox", default: "1" },
    { name: "note", labelKey: "transport.note", type: "textarea" },
  ],
  columns: ["name", "egn", "license_number", "phone", "active"],
};

export default function DriversPage() {
  return (
    <RequireAuth>
      <CrudPage config={config} transport />
    </RequireAuth>
  );
}
