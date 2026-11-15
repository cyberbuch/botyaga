defmodule Botyaga.Catalog do
  @moduledoc """
  Каталози на НАП: сметкоплан, мерни единици, данъчни кодове и останалите
  номенклатури. Данните са статични и се зареждат веднъж при първия достъп.
  """

  import Ecto.Query

  alias Botyaga.Stamp
  alias Botyaga.Repo
  alias Botyaga.Catalog.Account

  @data_path "priv/catalog/saft_noms.json"

  def catalog do
    case :persistent_term.get(:botyaga_catalog, nil) do
      nil -> load()
      data -> data
    end
  end

  defp load do
    @data_path
    |> then(&Application.app_dir(:botyaga, &1))
    |> File.read!()
    |> Jason.decode!()
    |> tap(&:persistent_term.put(:botyaga_catalog, &1))
  end

  @doc "Сее сметкоплана на фирма от каталога. Съществуващ номер се пропуска."
  def seed_chart(company_id) do
    existing =
      Repo.all(from(a in Account, where: a.company_id == ^company_id, select: a.number))
      |> MapSet.new()

    lines =
      (catalog()["accounts"] || [])
      |> Enum.map(&String.split(&1, "|"))
      |> Enum.reject(fn parts -> parts == [] or (hd(parts) || "") == "" end)

    missing = Enum.reject(lines, fn parts -> MapSet.member?(existing, hd(parts)) end)
    created = length(missing)
    skipped = length(lines) - created

    missing
    |> Enum.map(fn [code | _] = parts ->
      %{
        company_id: company_id,
        number: code,
        name: Enum.at(parts, 1, ""),
        saft_account_type: code,
        analytic_type: "none",
        is_currency: 0,
        inserted_at: Stamp.now(),
        updated_at: Stamp.now()
      }
    end)
    |> Enum.chunk_every(200)
    |> Enum.each(&Repo.insert_all(Account, &1))

    {created, skipped}
  end

  @doc "Име на сметка от каталога на НАП, или nil."
  def account_name(number) do
    (catalog()["accounts"] || [])
    |> Enum.find_value(fn line ->
      case String.split(line, "|") do
        [^number, name | _] -> String.trim(name)
        _ -> nil
      end
    end)
  end

  @kinds [
    {"stock_movements", "Движения запаси"},
    {"asset_movements", "Движения активи"},
    {"tax_regimes", "Данъчни режими"},
    {"payment_methods", "Начини на плащане"},
    {"invoice_types", "Видове фактури"},
    {"tax_types", "Видове данъци"},
    {"tax_codes", "Данъчни кодове"},
    {"product_types", "Видове запаси"},
    {"cn8", "КН8 (продукти)"},
    {"units", "Мерни единици"},
    {"regions", "Области"},
    {"accounts", "Сметки НАП"}
  ]

  def kinds, do: @kinds

  @doc "Номенклатури: без kind — списъкът с видове; с kind — редовете."
  def nomenclatures(kind, search \\ "") do
    kind = String.trim(kind || "")

    cond do
      kind == "" ->
        kinds = Enum.map(@kinds, fn {id, name} -> %{id: id, name: name} end)
        {:ok, %{kinds: kinds, count: length(kinds)}}

      kind == "cn8" ->
        {:ok, :cn8}

      rows = catalog()[kind] ->
        needle = String.downcase(String.trim(search || ""))

        items =
          rows
          |> Enum.filter(fn line ->
            needle == "" or String.contains?(String.downcase(line), needle)
          end)
          |> Enum.map(&parse_line(kind, &1))

        {:ok, %{kind: kind, items: items, count: length(items)}}

      true ->
        {:error, {400, "непозната номенклатура (kind)"}}
    end
  end

  @doc "Мерни единици от каталога, с търсене."
  def units(search \\ "") do
    needle = String.downcase(String.trim(search || ""))

    items =
      (catalog()["units"] || [])
      |> Enum.filter(fn line ->
        needle == "" or String.contains?(String.downcase(line), needle)
      end)
      |> Enum.map(&parse_line("units", &1))

    %{items: items, count: length(items), limit: 50, offset: 0}
  end

  @doc "Код на област: BG код или име от каталога; чужда държава пази текст до 35 знака."
  def region_code(raw, country) do
    text = String.trim(raw || "")

    if text == "" do
      {:ok, ""}
    else
      key = region_key(text)

      case find_region(key, text) do
        {:ok, code} ->
          {:ok, code}

        :error ->
          cond do
            String.starts_with?(key, "BG-") -> {:error, :invalid}
            String.trim(country || "") in ["", "BG"] -> {:error, :invalid}
            true -> {:ok, String.slice(text, 0, 35)}
          end
      end
    end
  end

  defp find_region(key, text) do
    (catalog()["regions"] || [])
    |> Enum.find_value(:error, fn line ->
      case String.split(line, "|", parts: 2) do
        [code, name] -> if key == code or text == name, do: {:ok, code}
        _ -> nil
      end
    end)
  end

  defp region_key(raw) do
    up = raw |> String.trim() |> String.upcase()

    if String.length(up) == 4 and String.starts_with?(up, "BG") and
         String.slice(up, 2, 2) |> String.match?(~r/^\d{2}$/) do
      "BG-" <> String.slice(up, 2, 2)
    else
      up
    end
  end

  defp parse_line(kind, line) do
    parts = String.split(line, "|")

    kind
    |> fields()
    |> Enum.with_index()
    |> Map.new(fn {field, index} -> {field, Enum.at(parts, index, "")} end)
  end

  defp fields("payment_methods"), do: ~w(method_code mechanism_code name name_en)
  defp fields("tax_codes"), do: ~w(tax_type code description rate note)
  defp fields("accounts"), do: ~w(code name section section_name group group_name)
  defp fields("units"), do: ~w(code name name_en symbol category source)
  defp fields(kind) when kind in ["regions", "tax_types"], do: ~w(code name)
  defp fields(_kind), do: ~w(code name name_en)
end
