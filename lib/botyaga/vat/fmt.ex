defmodule Botyaga.Vat.Fmt do
  @moduledoc "ППДДС: период, вид документ, Windows-1251 и фиксирана ширина."

  alias Botyaga.Invoicing.Money

  def parse_period(raw) do
    t = String.trim(raw || "")

    cond do
      t == "" ->
        {:error, :empty}

      String.length(t) == 7 and String.at(t, 4) == "-" ->
        period_parts(String.slice(t, 0, 4), String.slice(t, 5, 2))

      String.length(t) == 6 and String.match?(t, ~r/^[0-9]{6}$/) ->
        period_parts(String.slice(t, 0, 4), String.slice(t, 4, 2))

      true ->
        {:error, :format}
    end
  end

  defp period_parts(ys, ms) do
    with true <- String.match?(ys, ~r/^[0-9]+$/) and String.match?(ms, ~r/^[0-9]+$/),
         {y, ""} <- Integer.parse(ys),
         {m, ""} <- Integer.parse(ms),
         true <- y in 1..9999 and m in 1..12 do
      {:ok, %{iso: "#{pad4(y)}-#{pad2(m)}", nap: "#{pad4(y)}#{pad2(m)}"}}
    else
      _ -> {:error, :format}
    end
  end

  def doc_type("invoice"), do: "01"
  def doc_type("debit_note"), do: "02"
  def doc_type("credit_note"), do: "03"
  def doc_type("proforma"), do: "01"

  # Ръчна статия без изричен код: НАП иска валиден вид документ, не „ma“.
  def doc_type("manual"), do: "01"

  def doc_type(t) do
    cond do
      String.length(t) == 1 and String.match?(t, ~r/^[0-9]$/) -> "0#{t}"
      String.length(t) >= 2 -> String.slice(t, 0, 2)
      true -> "01"
    end
  end

  def is_credit_doc(t), do: t in ["03", "13", "23", "29"]
  def sales_excluded(t), do: t in ["04", "11", "12", "13"]
  def purch_excluded(t), do: t in ["05", "11", "12", "13", "94"]

  def rate_kind(raw) do
    case Money.cents(raw) do
      nil -> "20"
      0 -> "0"
      900 -> "9"
      _ -> "20"
    end
  end

  def nap_date(iso) do
    if String.length(iso) >= 10 do
      "#{String.slice(iso, 8, 2)}/#{String.slice(iso, 5, 2)}/#{String.slice(iso, 0, 4)}"
    else
      "          "
    end
  end

  def with_bg(v) do
    t = String.trim(v || "")

    cond do
      t == "" -> ""
      String.starts_with?(t, "BG") -> t
      String.starts_with?(t, "bg") -> "BG" <> String.slice(t, 2..-1//1)
      true -> "BG" <> t
    end
  end

  def cp_vat(v) do
    t = v |> to_string() |> String.trim() |> String.upcase()

    cond do
      t == "" -> ""
      String.starts_with?(t, "BG") -> t
      String.match?(t, ~r/^[0-9]+$/) -> "BG" <> t
      true -> t
    end
  end

  def cp_ident(vat, eik) do
    v = cp_vat(vat)

    if v != "" do
      v
    else
      e = eik |> to_string() |> String.trim() |> String.upcase()

      # 9 деветки са ЕИК-заглушка, не ДДС идентификатор: spec (ДВ 59/2022) иска 15.
      if e != "" and e != "999999999", do: e, else: "999999999999999"
    end
  end

  @doc "Windows-1251: кирилицата е еднобайтова, непознатите символи стават '?'."
  def cp1251(s) do
    s
    |> String.to_charlist()
    |> Enum.map(fn u ->
      cond do
        # Контролните знаци чупят фиксираната ширина на реда.
        u < 0x20 or u == 0x7F -> 32
        u < 128 -> u
        u in 0x0410..0x044F -> u - 848
        true -> Map.get(cp1251_special(), u, 63)
      end
    end)
    |> :binary.list_to_bin()
  end

  defp cp1251_special do
    %{
      0x0401 => 168,
      0x0451 => 184,
      0x201C => 147,
      0x201D => 148,
      0x201E => 132,
      0x2013 => 150,
      0x2014 => 151,
      0x2116 => 185
    }
  end

  def pad_right(src, n) do
    m = min(byte_size(src), n)
    binary_part(src, 0, m) <> String.duplicate(" ", n - m)
  end

  def pad_left(src, n) do
    size = byte_size(src)

    if size >= n do
      binary_part(src, size - n, n)
    else
      String.duplicate(" ", n - size) <> src
    end
  end

  def sym(s, n), do: pad_right(cp1251(s), n)
  def num_str(s, n), do: pad_left(cp1251(s), n)
  def amt(cents), do: num_str(Money.money(cents), 15)

  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")
  defp pad4(n), do: n |> Integer.to_string() |> String.pad_leading(4, "0")
end
