defmodule Botyaga.Saft.Mappings do
  @moduledoc "Дт/Кт кореспонденции към тип движение в SAF-T. По активната фирма. Порт на `smap.rs`."

  import Ecto.Query

  alias Botyaga.{Catalog, Params, Repo}
  alias Botyaga.Saft.{Mapping, MappingsDef}

  @bad_kind "непознат вид кореспонденция (kind=stock|asset|cash)"

  def index(company_id, kind) do
    kind = String.trim(kind || "")

    if not kind_ok(kind) do
      {:error, {400, @bad_kind}}
    else
      items = company_id |> rows_of(kind) |> Enum.map(&row_json/1)
      {:ok, %{kind: kind, items: items, count: length(items), types: types_json(kind)}}
    end
  end

  def create(company_id, params) do
    with {:ok, kind} <- required(params, "kind"),
         kind = String.trim(kind),
         :ok <- check_kind(kind),
         {:ok, code} <- required(params, "type_code"),
         code = String.trim(code),
         :ok <- check_type(kind, code),
         {:ok, debit} <- required(params, "debit_account"),
         {:ok, credit} <- required(params, "credit_account") do
      mapping =
        Repo.insert!(%Mapping{
          company_id: company_id,
          kind: kind,
          type_code: code,
          debit_account: String.trim(debit),
          credit_account: String.trim(credit),
          debit_analytical: trimmed(params, "debit_analytical"),
          credit_analytical: trimmed(params, "credit_analytical"),
          description: trimmed(params, "description"),
          is_active: 1
        })

      {:ok, row_json(mapping)}
    end
  end

  def update(company_id, id, params) do
    with {:ok, mapping} <- fetch(company_id, id),
         :ok <- maybe_type(mapping.kind, params),
         {:ok, changes} <- field_changes(params),
         {:ok, changes} <- maybe_active(changes, params) do
      changes = maybe_type_code_change(changes, params)
      mapping = Repo.update!(Ecto.Changeset.change(mapping, changes))
      {:ok, row_json(mapping)}
    end
  end

  def delete(company_id, id) do
    with {:ok, mapping} <- fetch(company_id, id) do
      Repo.delete!(mapping)
      {:ok, nil}
    end
  end

  def defaults(company_id, params) do
    with {:ok, kind} <- required(params, "kind"),
         kind = String.trim(kind),
         :ok <- check_kind(kind) do
      if rows_of(company_id, kind) != [] do
        {:error, {422, "вече има кореспонденции за този вид. Изтрийте ги първо."}}
      else
        n =
          kind
          |> MappingsDef.rows()
          |> Enum.map(&String.split(&1, "|", parts: 4))
          |> Enum.reject(fn parts -> Enum.at(parts, 0, "") == "" end)
          |> Enum.map(fn [code, debit, credit, desc] ->
            Repo.insert!(%Mapping{
              company_id: company_id,
              kind: kind,
              type_code: code,
              debit_account: debit,
              credit_account: credit,
              debit_analytical: "",
              credit_analytical: "",
              description: desc,
              is_active: 1
            })
          end)
          |> length()

        {:ok, %{kind: kind, count: n}}
      end
    end
  end

  ## Вътрешни

  defp kind_ok(kind), do: kind in ["stock", "asset", "cash"]

  defp check_kind(kind), do: if(kind_ok(kind), do: :ok, else: {:error, {422, @bad_kind}})

  defp type_rows("cash"), do: MappingsDef.cash_types()
  defp type_rows("asset"), do: Catalog.catalog()["asset_movements"] || []
  defp type_rows(_), do: Catalog.catalog()["stock_movements"] || []

  defp type_known(kind, code),
    do: Enum.any?(type_rows(kind), &(Enum.at(String.split(&1, "|"), 0) == code))

  defp check_type(kind, code),
    do:
      if(type_known(kind, code),
        do: :ok,
        else: {:error, {422, "непознат тип движение за този вид"}}
      )

  defp type_name(kind, code) do
    Enum.find_value(type_rows(kind), code, fn line ->
      parts = String.split(line, "|", parts: 3)
      if Enum.at(parts, 0, "") == code, do: Enum.at(parts, 1, "")
    end)
  end

  defp types_json(kind) do
    Enum.map(type_rows(kind), fn line ->
      parts = String.split(line, "|", parts: 3)
      %{code: Enum.at(parts, 0, ""), name: Enum.at(parts, 1, ""), name_en: Enum.at(parts, 2, "")}
    end)
  end

  defp rows_of(company_id, kind) do
    Repo.all(
      from(m in Mapping,
        where: m.company_id == ^company_id and m.kind == ^kind,
        order_by: [asc: m.id]
      )
    )
  end

  defp fetch(company_id, id) do
    case Repo.get_by(Mapping, id: Params.id(id), company_id: company_id) do
      nil -> {:error, {404, "кореспонденцията не е намерена"}}
      mapping -> {:ok, mapping}
    end
  end

  defp row_json(m) do
    %{
      id: m.id,
      kind: m.kind,
      type_code: m.type_code,
      type_name: type_name(m.kind, m.type_code),
      debit_account: m.debit_account,
      credit_account: m.credit_account,
      debit_analytical: m.debit_analytical,
      credit_analytical: m.credit_analytical,
      description: m.description,
      is_active: m.is_active
    }
  end

  defp maybe_type(kind, params) do
    case Params.str(params, "type_code") do
      {:present, code} -> check_type(kind, String.trim(code))
      _ -> :ok
    end
  end

  defp field_changes(params) do
    fields = ~w(debit_account credit_account debit_analytical credit_analytical description)

    Enum.reduce_while(fields, {:ok, []}, fn field, {:ok, acc} ->
      case Params.str(params, field) do
        {:present, value} ->
          trimmed = String.trim(value)

          if field in ["debit_account", "credit_account"] and trimmed == "" do
            {:halt, {:error, {422, "дебит и кредит сметките са задължителни"}}}
          else
            {:cont, {:ok, acc ++ [{String.to_existing_atom(field), trimmed}]}}
          end

        _ ->
          {:cont, {:ok, acc}}
      end
    end)
  end

  defp maybe_active(changes, params) do
    case Params.flag(params, "is_active") do
      nil -> {:ok, changes}
      {:error, _} -> {:ok, changes}
      flag -> {:ok, changes ++ [{:is_active, flag}]}
    end
  end

  defp maybe_type_code_change(changes, params) do
    case Params.str(params, "type_code") do
      {:present, code} -> changes ++ [{:type_code, String.trim(code)}]
      _ -> changes
    end
  end

  defp required(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        if String.trim(value) == "",
          do: {:error, {422, "#{key} е задължително"}},
          else: {:ok, value}

      _ ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp trimmed(params, key) do
    case Params.str(params, key) do
      {:present, value} -> String.trim(value)
      _ -> ""
    end
  end
end
