// lib/transport.ts — HTTP клиент към transport микросървиза (изолиран, същия JWT).
// Next проксира /transport/v1 към :8096; праща активната фирма като x-company-id.

import { getToken, setToken, ACTIVE_COMPANY_EVENT, ApiError } from "./api";

const BASE = "/transport/v1";

let cachedCompany = 0;
let cachedToken: string | null = null;
let companyPromise: Promise<number> | null = null;

if (typeof window !== "undefined") {
  window.addEventListener(ACTIVE_COMPANY_EVENT, () => {
    cachedCompany = 0;
    companyPromise = null;
  });
}

// Кешът е вързан с токена: при смяна на потребител в същия таб не бива
// новият потребител да изпрати фирмата на предишния.
async function companyId(): Promise<number> {
  const token = getToken();
  if (cachedCompany > 0 && cachedToken === token) return cachedCompany;
  cachedCompany = 0;
  if (!companyPromise) {
    companyPromise = fetch("/v1/active-company", {
      headers: { Authorization: `Bearer ${token ?? ""}` },
      cache: "no-store",
    })
      .then((r) => (r.ok ? r.json() : {}))
      .then((c: { id?: number }) => {
        cachedCompany = Number(c.id) || 0;
        cachedToken = token;
        return cachedCompany;
      })
      .catch(() => 0)
      .finally(() => {
        companyPromise = null;
      });
  }
  return companyPromise;
}

async function request<T>(path: string, method: string, body?: unknown): Promise<T> {
  const cid = await companyId();
  const headers: Record<string, string> = {
    Authorization: `Bearer ${getToken() ?? ""}`,
    "x-company-id": String(cid),
  };
  if (body !== undefined) headers["Content-Type"] = "application/json";

  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    cache: "no-store",
  });

  if (res.status === 204) return undefined as T;
  const text = await res.text();
  let data: unknown = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }
  if (!res.ok) {
    if (res.status === 401) setToken(null);
    const detail =
      data && typeof data === "object" && typeof (data as { detail?: unknown }).detail === "string"
        ? (data as { detail: string }).detail
        : res.statusText;
    throw new ApiError(res.status, detail);
  }
  return data as T;
}

export const transport = {
  get: <T>(path: string, query?: Record<string, string | number | undefined>) => {
    let url = path;
    if (query) {
      const params = new URLSearchParams();
      for (const [k, v] of Object.entries(query)) if (v !== undefined) params.set(k, String(v));
      const qs = params.toString();
      if (qs) url = `${path}?${qs}`;
    }
    return request<T>(url, "GET");
  },
  post: <T>(path: string, body?: unknown) => request<T>(path, "POST", body),
  patch: <T>(path: string, body?: unknown) => request<T>(path, "PATCH", body),
  del: <T>(path: string) => request<T>(path, "DELETE"),
};

export async function transportFetchAll<T>(path: string): Promise<T[]> {
  const data = await transport.get<{ items?: T[] }>(path);
  return data.items ?? [];
}
