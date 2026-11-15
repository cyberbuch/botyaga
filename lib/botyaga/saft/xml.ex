defmodule Botyaga.Saft.Xml do
  @moduledoc """
  SAF-T XML помощници по BG_SAFT_Schema V1.0.1. Дължините са в знаци: улица 70,
  град и област 35, номер и пощенски код 18. Порт на `saft_xml.rs`.
  """

  alias Botyaga.{Catalog, Dec}

  def open(name), do: "<nsSAFT:#{name}>"
  def close(name), do: "</nsSAFT:#{name}>"

  def text(name, value), do: "<nsSAFT:#{name}>#{xml_escape(value)}</nsSAFT:#{name}>"

  def opt(name, value) do
    t = String.trim(value || "")
    if t == "", do: "", else: text(name, t)
  end

  def clip(s, n) do
    t = String.trim(s || "")
    if n == 0 or t == "", do: "", else: String.slice(t, 0, n)
  end

  def amount(name, value, currency) do
    t = Dec.money(value)

    open(name) <>
      text("Amount", t) <>
      text("CurrencyCode", currency) <>
      text("CurrencyAmount", t) <>
      close(name)
  end

  def money_of(raw), do: Dec.or0(raw)

  @doc "Дебит, когато дебитът е >= кредита. Равни страни, и нулата, са дебит 0.00."
  def bal(debit_tag, credit_tag, debit, credit) do
    if debit >= credit,
      do: text(debit_tag, Dec.money(debit - credit)),
      else: text(credit_tag, Dec.money(credit - debit))
  end

  def nra_ok(s) do
    t = String.trim(s || "")
    len = String.length(t)

    len in 3..5 and String.match?(t, ~r/^[1-9][0-9]*$/)
  end

  @doc "{код на НАП, номер във фирмата}. `nil` пропуска сметката."
  def pack(saft_type, number) do
    firm = String.trim(number || "")
    st = String.trim(saft_type || "")

    nra =
      cond do
        nra_ok(st) -> st
        nra_ok(firm) -> firm
        true -> nil
      end

    if nra == nil do
      nil
    else
      tax = if firm == "", do: nra, else: clip(firm, 35)
      {nra, tax}
    end
  end

  def pref(nra, p),
    do: nra == p or (String.starts_with?(nra, p) and String.length(nra) > String.length(p))

  def same_co(_row, cid) when cid <= 0, do: true
  def same_co(row, cid), do: row == cid

  def country(raw) do
    u = raw |> String.trim() |> String.upcase()
    if String.length(u) == 2 and String.match?(u, ~r/^[A-Z]{2}$/), do: u, else: "BG"
  end

  def cyr(s), do: String.graphemes(s || "") |> Enum.any?(&(byte_size(&1) > 1))

  @doc "Код BG-01…BG-28. Празна или непозната област за BG се пропуска."
  def region_code(raw, country) do
    case Catalog.region_code(raw, country) do
      {:ok, ""} -> nil
      {:ok, code} -> code
      {:error, :invalid} -> nil
    end
  end

  def addr_type(raw) do
    case raw |> String.trim() |> String.upcase() do
      "STREETADDRESS" -> "StreetAddress"
      "POSTALADDRESS" -> "PostalAddress"
      "BILLINGADDRESS" -> "BillingAddress"
      "SHIPTOADDRESS" -> "ShipToAddress"
      "SHIPFROMADDRESS" -> "ShipFromAddress"
      _ -> nil
    end
  end

  def address(tag, a) do
    cc = country(a.country)

    out =
      open(tag) <>
        opt("StreetName", clip(a.street, 70)) <>
        opt("Number", clip(a.number, 18)) <>
        opt("AdditionalAddressDetail", clip(a.extra, 70)) <>
        opt("Building", clip(a.building, 35)) <>
        text("City", clip(a.city, 35)) <>
        opt("PostalCode", clip(a.post, 18))

    out =
      case region_code(a.region, cc) do
        nil -> out
        code -> out <> text("Region", code)
      end

    out = out <> text("Country", cc)

    out =
      case addr_type(a.kind) do
        nil -> out
        kind -> out <> text("AddressType", kind)
      end

    out <> close(tag)
  end

  def ymd(y, m, d) do
    "#{pad(y, 4)}-#{pad(m, 2)}-#{pad(d, 2)}"
  end

  defp pad(v, n), do: v |> Integer.to_string() |> String.pad_leading(n, "0")

  def window(year, month, fys) do
    start_m = if fys in 1..12, do: fys, else: 1
    fy = if month < start_m, do: year - 1, else: year
    {ny, nm} = if month >= 12, do: {year + 1, 1}, else: {year, month + 1}

    %{
      fy_start: ymd(fy, start_m, 1),
      start: ymd(year, month, 1),
      next: ymd(ny, nm, 1),
      prefix: "#{pad(year, 4)}-#{pad(month, 2)}"
    }
  end

  @doc "`:o` е движение преди месеца, `:p` е месецът. Датата е YYYY-MM-DD."
  def bucket(date, w) do
    date = String.slice(date || "", 0, 10)

    cond do
      String.length(date) < 10 -> nil
      date >= w.fy_start and date < w.start -> :o
      date >= w.start and date < w.next -> :p
      true -> nil
    end
  end

  def unit_name(code) do
    found =
      (Catalog.catalog()["units"] || [])
      |> Enum.find_value(fn line ->
        parts = String.split(line, "|")
        c = Enum.at(parts, 0, "")
        name = Enum.at(parts, 1, "")
        if c == code and name != "", do: clip(name, 256)
      end)

    cond do
      found != nil -> found
      code == "" -> "Единица"
      true -> clip(code, 256)
    end
  end

  def stock_moves do
    (Catalog.catalog()["stock_movements"] || [])
    |> Enum.map(fn line ->
      parts = String.split(line, "|")
      {String.trim(Enum.at(parts, 0, "")), String.trim(Enum.at(parts, 1, ""))}
    end)
    |> Enum.reject(fn {code, _} -> code == "" end)
    |> Enum.map(fn {code, name} -> {clip(code, 9), clip(name, 256)} end)
  end

  def or_text(value, fallback) do
    t = String.trim(value || "")
    if t == "", do: fallback, else: t
  end

  def shown_name(name, n) do
    t = clip(name, n)
    if t == "", do: "—", else: t
  end

  def cn8_code(raw, is_service) do
    t = clip(raw, 18)

    cond do
      t != "" -> t
      is_service -> "00000000"
      true -> "0"
    end
  end

  def product_type(raw) do
    t = String.trim(raw || "")
    if t in ["10", "20", "30", "40", "50"], do: t, else: "10"
  end

  def xml_escape(s) do
    (s || "")
    |> String.replace(~r/[\x00-\x08\x0A-\x1F\x7F-\x9F]/u, "")
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
