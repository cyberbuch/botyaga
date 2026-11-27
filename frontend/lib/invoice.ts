// Споделени типове и изчисления за фактури.

// Видове данъчни документи — кодове по ППЗДС (Приложение № 12).
// Маркировка в кой дневник влиза: in = покупки (входяща), out = продажби (изходяща).
export interface DocType { code: string; in: boolean; out: boolean }
export const DOC_TYPE_REGISTRY: DocType[] = [
  { code: "01", in: true, out: true },   // Фактура
  { code: "02", in: true, out: true },   // Дебитно известие
  { code: "03", in: true, out: true },   // Кредитно известие
  { code: "07", in: true, out: false },  // Митническа декларация (внос)
  { code: "09", in: true, out: true },   // Протокол (чл.117 и др.)
  { code: "11", in: true, out: true },   // Фактура - касова отчетност
  { code: "12", in: true, out: true },   // Дебитно - касова
  { code: "13", in: true, out: true },   // Кредитно - касова
  { code: "04", in: false, out: true },  // Регистър изпратени стоки / получени плащания
  { code: "05", in: true, out: false },  // Регистър получени стоки / извършени плащания
  { code: "23", in: false, out: true },  // Кредитно по чл.126б ал.1
  { code: "29", in: false, out: true },  // Протокол по чл.126б ал.2
  { code: "81", in: false, out: true },  // Отчет продажби
  { code: "82", in: false, out: true },  // Отчет спец. режим
  { code: "95", in: false, out: true },  // Протокол безвъзмездни хранителни стоки
  { code: "91", in: false, out: true },  // Протокол чл.151в ал.3
  { code: "92", in: true, out: false },  // Протокол чл.151г ал.8
  { code: "93", in: true, out: true },   // Протокол чл.151в ал.7
  { code: "94", in: true, out: false },  // Протокол чл.151в ал.7 (получател спец. режим)
  { code: "50", in: false, out: true },  // Протокол горива с компенсации
  { code: "83", in: false, out: true },  // Отчет горива
  { code: "84", in: false, out: true },  // Отчет хляб
  { code: "85", in: false, out: true },  // Отчет брашно
];
export const DOC_TYPES_COMMON = DOC_TYPE_REGISTRY.filter((d) => d.in && d.out).map((d) => d.code);
export const DOC_TYPES_OUT = DOC_TYPE_REGISTRY.filter((d) => d.out).map((d) => d.code);
export const DOC_TYPES_IN = DOC_TYPE_REGISTRY.filter((d) => d.in).map((d) => d.code);
export const DOC_TYPE_PROFORMA = "proforma";

export function docTypesFor(direction: string): string[] {
  const base = direction === "in" ? DOC_TYPES_IN : DOC_TYPES_OUT;
  return [DOC_TYPE_PROFORMA, ...base];
}

export function docTypeRequiresOriginal(t: string): boolean {
  return t === "02" || t === "03" || t === "12" || t === "13" || t === "23";
}

export function docTypeIsCredit(t: string): boolean {
  return t === "03" || t === "13" || t === "23";
}

export function docTypeIsProforma(t: string): boolean {
  return t === DOC_TYPE_PROFORMA;
}

export const UNITS = ["C62", "H87", "KGM", "LTR", "MTR", "MTK", "MTQ", "HUR", "DAY", "SET", "PK", "E48"];
export const VAT_RATES = ["20", "9", "0"];

// OSS: държавата на потребление и нейните ставки (стандартна/намалена/0).
export const OSS_COUNTRIES = ["DE","FR","IT","ES","NL","BE","AT","PL","CZ","GR","RO","HU","PT","SE","DK","FI","IE","HR","SK","SI","BG"];
export const OSS_RATES: Record<string, string[]> = {
  DE: ["19","7","0"], FR: ["20","5.5","0"], IT: ["22","4","0"], ES: ["21","10","0"],
  NL: ["21","9","0"], BE: ["21","6","0"], AT: ["20","10","0"], PL: ["23","8","0"],
  CZ: ["21","12","0"], GR: ["24","13","0"], RO: ["19","9","0"], HU: ["27","5","0"],
  PT: ["23","6","0"], SE: ["25","6","0"], DK: ["25","0"], FI: ["25.5","10","0"],
  IE: ["23","13.5","0"], HR: ["25","5","0"], SK: ["23","19","0"], SI: ["22","9.5","0"],
  BG: ["20","9","0"],
};
export function ossRates(country: string): string[] {
  return OSS_RATES[country] ?? ["20","9","0"];
}
export const PAY_METHODS = ["банков превод", "в брой", "карта", "компенсация", "друго"];
export const CURRENCIES = ["EUR", "USD", "GBP", "CHF", "BGN", "RON", "PLN", "TRY", "JPY", "CNY"];

export interface InvoiceLine {
  id?: number;
  product_id?: number;
  code: string;
  description: string;
  quantity: string;
  unit: string;
  unit_price: string;
  vat_rate: string;
  net_amount: string;
  vat_amount: string;
  total_amount: string;
  seller_code?: string;
  keep_amounts?: boolean;
}

export interface InvoiceParty {
  id?: number;
  name?: string;
  eik?: string;
  vat_number?: string;
  address?: string;
  city?: string;
  mol?: string;
  iban?: string;
  bic?: string;
  contact_person?: string;
}

export interface AuditEntry {
  id: number;
  company_id: number;
  user_id: number;
  user_login: string;
  user_name: string;
  entity_type: string;
  entity_id: number;
  entity_number: string;
  action: string;
  summary: string;
  old_amount: string;
  new_amount: string;
  amount_changed?: boolean;
  old_data?: unknown;
  new_data?: unknown;
  created_at: string;
}

export interface Invoice {
  id: number;
  direction: string;
  document_type: string;
  number: string;
  issue_date: string;
  due_date?: string;
  tax_event_date?: string;
  accounting_month?: string;
  counterpart_id: number;
  counterpart_name?: string;
  currency: string;
  currency_rate?: string;
  net_amount: string;
  vat_amount: string;
  total_amount: string;
  status: string;
  payment_method?: string;
  notes?: string;
  discount_percent?: string;
  discount_amount?: string;
  vat_exemption_reason?: string;
  original_invoice_id?: number;
  journal_entry_id?: number;
  is_paid?: boolean;
  payment_entry_id?: number;
  bank_account_id?: number;
  location_id?: number;
  exclude_vat?: number;
  is_oss?: number;
  is_margin?: number;
  margin_export?: number;
  oss_country?: string;
  vat_article?: string;
  customs_statistical?: string;
  customs_duty?: string;
  customs_vat?: string;
  lines?: InvoiceLine[];
  counterpart?: InvoiceParty;
  company?: InvoiceParty;
  created_by?: string;
  created_at?: string;
  updated_by?: string;
  updated_at?: string;
  edit_count?: number;
  audit_history?: AuditEntry[];
}

export function emptyLine(): InvoiceLine {
  return {
    code: "",
    description: "",
    quantity: "1",
    unit: "C62",
    unit_price: "0",
    vat_rate: "20",
    net_amount: "0.00",
    vat_amount: "0.00",
    total_amount: "0.00",
  };
}

export { todayIso, formatBgDate, formatBgDateTime, toDateInput } from "./dates";

export function isCompanyVatRegistered(co: unknown): boolean {
  if (!co || typeof co !== "object") return true;
  const rec = co as { is_vat_registered?: unknown; vat_number?: unknown };
  const flag = Number(rec.is_vat_registered ?? 0) === 1 || rec.is_vat_registered === true;
  const vat = String(rec.vat_number ?? "").trim();
  return flag && vat.length > 0;
}

export function normVatRate(s: string | undefined | null): string {
  const n = num(String(s ?? ""));
  const asStr = String(n);
  if ((VAT_RATES as readonly string[]).includes(asStr)) return asStr;
  return s && String(s).trim() ? String(s) : "20";
}

export function round2(n: number): string {
  return (Math.round(n * 100) / 100).toFixed(2);
}

export function num(s: string): number {
  return parseFloat(String(s).replace(",", ".")) || 0;
}

export function signedMoney(n: number, negative: boolean): string {
  if (!n) return round2(0);
  const abs = Math.abs(n);
  return round2(negative ? -abs : abs);
}

function signedText(amount: string, negative: boolean): string {
  const raw = String(amount ?? "").trim().replace(/\s/g, "").replace(",", ".");
  const abs = raw.startsWith("-") ? raw.slice(1) : raw;
  if (!abs || num(abs) === 0) return round2(0);
  return negative ? `-${abs}` : abs;
}

export function calcLine(
  l: InvoiceLine,
  pricesIncludeVat: boolean,
  credit = false
): InvoiceLine {
  if (
    l.keep_amounts &&
    l.net_amount &&
    l.total_amount &&
    (l.vat_amount || num(l.vat_rate) === 0) &&
    !pricesIncludeVat
  ) {
    return {
      ...l,
      net_amount: signedText(l.net_amount, credit),
      vat_amount: signedText(l.vat_amount || "0.00", credit),
      total_amount: signedText(l.total_amount, credit),
    };
  }
  const q = num(l.quantity);
  const rate = num(l.vat_rate) / 100;
  let priceNet = num(l.unit_price);
  if (pricesIncludeVat) {
    priceNet = rate > 0 ? priceNet / (1 + rate) : priceNet;
  }
  const net = q * priceNet;
  const vat = net * rate;
  return {
    ...l,
    net_amount: signedMoney(net, credit),
    vat_amount: signedMoney(vat, credit),
    total_amount: signedMoney(net + vat, credit),
  };
}

export function calcTotals(lines: InvoiceLine[], discountPercent: string) {
  const subtotal = lines.reduce((s, l) => s + num(l.net_amount), 0);
  const discPct = num(discountPercent);
  const discount = (subtotal * discPct) / 100;
  const taxable = subtotal - discount;
  const factor = subtotal === 0 ? 0 : taxable / subtotal;
  const vat = lines.reduce((s, l) => s + num(l.vat_amount) * factor, 0);
  return {
    subtotal: round2(subtotal),
    discount: round2(discount),
    taxable: round2(taxable),
    vat: round2(vat),
    total: round2(taxable + vat),
  };
}

export function absorbVatIntoLines(
  lines: InvoiceLine[],
  targetTotal?: string
): InvoiceLine[] {
  if (!lines.length) return lines;
  const nets: number[] = [];
  const gross: number[] = [];
  for (const l of lines) {
    const q = num(l.quantity) || 1;
    const up = num(l.unit_price);
    const rate = num(l.vat_rate) / 100;
    const netC = l.net_amount && num(l.net_amount) !== 0
      ? Math.round(num(l.net_amount) * 100)
      : Math.round(q * up * 100);
    const vatC = l.vat_amount && num(l.vat_amount) !== 0
      ? Math.round(num(l.vat_amount) * 100)
      : Math.round(netC * rate);
    const totC = l.total_amount && num(l.total_amount) !== 0
      ? Math.round(num(l.total_amount) * 100)
      : netC + vatC;
    nets.push(netC);
    gross.push(totC);
  }
  const sumNet = nets.reduce((a, b) => a + b, 0);
  let sumGross = gross.reduce((a, b) => a + b, 0);
  const targetC = targetTotal && num(targetTotal) !== 0 ? Math.round(num(targetTotal) * 100) : sumGross;
  if (sumGross === sumNet && targetC > sumNet && sumNet !== 0) {
    const extra = targetC - sumNet;
    let acc = 0;
    for (let i = 0; i < gross.length; i++) {
      const share =
        i + 1 === gross.length
          ? extra - acc
          : Math.round((extra * nets[i]) / sumNet);
      if (i + 1 < gross.length) acc += share;
      gross[i] = nets[i] + share;
    }
    sumGross = gross.reduce((a, b) => a + b, 0);
  }
  if (targetC !== 0 && sumGross !== targetC && gross.length > 0) {
    const diff = targetC - sumGross;
    const lastIdx = gross.length - 1;
    if (gross[lastIdx] + diff >= 0) {
      gross[lastIdx] += diff;
    }
  }
  return lines.map((l, i) => {
    const g = gross[i] / 100;
    const gStr = round2(g);
    const q = num(l.quantity);
    const upStr = q > 0 ? round2(g / q) : gStr;
    return {
      ...l,
      unit_price: upStr,
      vat_rate: "0",
      net_amount: gStr,
      vat_amount: "0.00",
      total_amount: gStr,
      keep_amounts: true,
    };
  });
}

export function applyDiscountToLines(lines: InvoiceLine[], discountPercent: string): InvoiceLine[] {
  const discPct = num(discountPercent);
  if (discPct === 0) return lines;
  const factor = 1 - discPct / 100;
  return lines.map((l) => {
    const net = num(l.net_amount) * factor;
    const vat = num(l.vat_amount) * factor;
    return {
      ...l,
      net_amount: round2(net),
      vat_amount: round2(vat),
      total_amount: round2(net + vat),
    };
  });
}

export function docTypeTitle(t: string): string {
  switch (t) {
    case "02":
      return "ДЕБИТНО ИЗВЕСТИЕ";
    case "03":
      return "КРЕДИТНО ИЗВЕСТИЕ";
    case "04":
    case "05":
      return "РЕГИСТЪР НА СТОКИ ПОД РЕЖИМ СКЛАДИРАНЕ ДО ПОИСКВАНЕ";
    case "07":
      return "МИТНИЧЕСКА ДЕКЛАРАЦИЯ";
    case "09":
      return "ПРОТОКОЛ ПО ЧЛ. 117 ОТ ЗДДС";
    case "11":
      return "ФАКТУРА - КАСОВА ОТЧЕТНОСТ";
    case "12":
      return "ДЕБИТНО ИЗВЕСТИЕ - КАСОВА ОТЧЕТНОСТ";
    case "13":
      return "КРЕДИТНО ИЗВЕСТИЕ - КАСОВА ОТЧЕТНОСТ";
    case "23":
      return "КРЕДИТНО ИЗВЕСТИЕ ПО ЧЛ. 126Б, АЛ. 1 ОТ ЗДДС";
    case "29":
      return "ПРОТОКОЛ ПО ЧЛ. 126Б, АЛ. 2 И 7 ОТ ЗДДС";
    case "81":
    case "83":
    case "84":
    case "85":
      return "ОТЧЕТ ЗА ИЗВЪРШЕНИТЕ ПРОДАЖБИ";
    case "82":
      return "ОТЧЕТ ЗА ПРОДАЖБИ ПРИ СПЕЦИАЛЕН РЕД НА ОБЛАГАНЕ";
    case "proforma":
      return "ПРОФОРМА ФАКТУРА";
    default:
      return "ФАКТУРА";
  }
}

export function docTypePrefix(t: string): string {
  switch (t) {
    case "02":
    case "12":
      return "ДИ-";
    case "03":
    case "13":
    case "23":
      return "КИ-";
    case "proforma":
      return "ПФ-";
    default:
      return "";
  }
}

export function docTypeFileSlug(t: string): string {
  switch (t) {
    case "02":
      return "debit_note";
    case "03":
      return "credit_note";
    case "04":
      return "call_off_dispatch";
    case "05":
      return "call_off_receipt";
    case "07":
      return "customs_declaration";
    case "09":
      return "protocol";
    case "11":
      return "invoice_cash";
    case "12":
      return "debit_note_cash";
    case "13":
      return "credit_note_cash";
    case "23":
      return "credit_note_126b";
    case "29":
      return "protocol_126b";
    case "50":
      return "fuel_protocol";
    case "81":
      return "sales_report";
    case "82":
      return "sales_report_special";
    case "83":
      return "sales_report_fuel";
    case "84":
      return "sales_report_bread";
    case "85":
      return "sales_report_flour";
    case "91":
      return "vat_protocol";
    case "92":
      return "vat_protocol_credit";
    case "93":
      return "vat_protocol_151v";
    case "94":
      return "vat_protocol_151v_scheme";
    case "95":
      return "food_protocol";
    case "proforma":
      return "proforma";
    default:
      return "invoice";
  }
}

export function invoiceDownloadName(number: string, documentType: string, ext: string): string {
  const n = (number || "document").replace(/["\\/:*?<>|]/g, "_").trim() || "document";
  return `${n}_${docTypeFileSlug(documentType)}.${ext}`;
}
