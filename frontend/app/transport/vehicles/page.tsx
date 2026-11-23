"use client";

import { RequireAuth } from "../../../components/RequireAuth";
import { CrudPage, CrudConfig } from "../../../components/CrudPage";

const config: CrudConfig = {
  endpoint: "/vehicles",
  titleKey: "transport.vehicles",
  fields: [
    { name: "name", labelKey: "transport.name", type: "text", required: true },
    { name: "plate", labelKey: "transport.plate", type: "text" },
    {
      name: "fuel",
      labelKey: "transport.fuel",
      type: "select",
      default: "Дизел",
      options: [
        { value: "Дизел", labelKey: "transport.fuel.diesel" },
        { value: "Бензин", labelKey: "transport.fuel.petrol" },
        { value: "Газ", labelKey: "transport.fuel.lpg" },
        { value: "Електро", labelKey: "transport.fuel.electric" },
        { value: "Хибрид", labelKey: "transport.fuel.hybrid" },
      ],
    },
    { name: "norm", labelKey: "transport.norm", type: "text", default: "0" },
    { name: "winter_surcharge", labelKey: "transport.winter_surcharge", type: "number", default: "0" },
    { name: "tank_volume", labelKey: "transport.tank_volume", type: "text" },
    { name: "active", labelKey: "transport.active", type: "checkbox", default: "1" },
    { name: "note", labelKey: "transport.note", type: "textarea" },
  ],
  columns: ["name", "plate", "fuel", "norm", "winter_surcharge", "active"],
};

export default function VehiclesPage() {
  return (
    <RequireAuth>
      <CrudPage config={config} transport />
    </RequireAuth>
  );
}
