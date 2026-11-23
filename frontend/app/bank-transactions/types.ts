export interface BankAccount {
  id: number;
  name: string;
  iban: string;
  currency: string;
  gl_account_id?: number;
}

export interface Account {
  id: number;
  number: string;
  name: string;
  is_currency?: boolean;
}

export interface Counterpart {
  id: number;
  name: string;
  eik: string;
  vat_number: string;
}

export interface ParsedTx {
  date: string;
  amount: string;
  currency: string;
  description: string;
  contra_name: string;
  contra_iban: string;
  reference: string;
  is_duplicate: boolean;
}

export interface Preview {
  format_name: string;
  account_iban: string;
  account_currency: string;
  transactions: ParsedTx[];
  total_count: number;
  duplicate_count: number;
  new_count: number;
}

export interface BankTransaction {
  id: number;
  bank_account_id: number;
  bank_account_name?: string;
  transaction_date: string;
  amount: string;
  currency: string;
  counterpart_name: string;
  counterpart_iban: string;
  description: string;
  reference: string;
  transaction_type: string;
  is_booked: boolean;
  is_allocated: boolean;
  journal_entry_id: number;
}

export interface JeLine {
  id: number;
  account_id: number;
  direction: string;
  amount: string;
  account_number?: string;
  account_name?: string;
  currency?: string;
  fx_quantity?: string;
  fx_rate?: string;
}

export interface BookPreviewLine {
  account_id: number;
  account_number: string;
  account_name: string;
  direction: string;
  amount: string;
  currency?: string;
  fx_quantity?: string;
  fx_rate?: string;
}

export interface BookPreview {
  transaction_id: number;
  date: string;
  amount: string;
  currency: string;
  description: string;
  requires_confirm: boolean;
  balanced?: boolean;
  debit_total?: string;
  credit_total?: string;
  lines: BookPreviewLine[];
}

// Ред от ръчното осчетоводяване — като LineDraft в дневника: стойността в
// базова валута е производна = количество × курс.
export interface BookLineDraft {
  accountId: string;
  direction: "debit" | "credit";
  amount: string;
  currency: string;
  fxQuantity: string;
  fxRate: string;
}

export const emptyBookLine = (): BookLineDraft => ({
  accountId: "",
  direction: "debit",
  amount: "",
  currency: "",
  fxQuantity: "",
  fxRate: "1",
});
