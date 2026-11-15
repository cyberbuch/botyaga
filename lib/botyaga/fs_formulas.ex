defmodule Botyaga.FsFormulas do
  @moduledoc """
  Формули за финансовите отчети. Каталогът е в кода (`Reports.Nom`), записът е по
  фирма. Порт на `fsform.rs`: lines/index/put/defaults/clear/validate.
  """

  import Ecto.Query

  alias Botyaga.{Params, Repo}
  alias Botyaga.FsFormulas.Formula
  alias Botyaga.Reports.{FS, Nom}

  @bad_statement "statement трябва да е balance/pl/cashflow/equity"

  @doc "Карта код → формула за диспечера на справките."
  def map(company_id, statement) do
    company_id
    |> rows_of(statement)
    |> Map.new(&{&1.line_code, &1.formula})
  end

  def lines(statement) do
    statement = String.trim(statement || "")

    cond do
      statement == "" ->
        items = Enum.map(Nom.statements(), fn {id, name} -> %{id: id, name: name} end)
        {:ok, %{items: items, count: length(items)}}

      not Nom.known(statement) ->
        {:error, {400, @bad_statement}}

      true ->
        items =
          statement
          |> Nom.lines()
          |> Enum.map(
            &%{code: &1.code, parent: &1.parent, kind: &1.kind, side: &1.side, name: &1.name}
          )

        {:ok, %{statement: statement, items: items, count: length(items)}}
    end
  end

  def index(company_id, statement) do
    with {:ok, st} <- known_get(statement) do
      rows = rows_of(company_id, st)
      {:ok, %{statement: st, items: Enum.map(rows, &row_json/1), count: length(rows)}}
    end
  end

  def put(company_id, params) do
    with {:ok, raw} <- req(params, "statement"),
         {:ok, st} <- known_write(raw),
         {:ok, code} <- req(params, "line_code"),
         :ok <- known_code(st, code),
         {:ok, formula} <- present(params, "formula"),
         :ok <- check_formula(formula) do
      row =
        company_id
        |> rows_of(st)
        |> Enum.find(&(&1.line_code == code))

      row =
        if row do
          Repo.update!(Ecto.Changeset.change(row, formula: formula))
        else
          Repo.insert!(%Formula{
            company_id: company_id,
            statement: st,
            line_code: code,
            formula: formula
          })
        end

      {:ok, row_json(row)}
    end
  end

  def defaults(company_id, params) do
    with {:ok, raw} <- req(params, "statement"),
         {:ok, st} <- known_write(raw) do
      rows = rows_of(company_id, st)

      if rows != [] do
        {:error, {422, "вече има формули за този отчет. Изтрийте ги първо."}}
      else
        defs = Nom.defaults(st)

        Enum.each(defs, fn {code, formula} ->
          Repo.insert!(%Formula{
            company_id: company_id,
            statement: st,
            line_code: code,
            formula: formula
          })
        end)

        {:ok, %{statement: st, count: length(defs)}}
      end
    end
  end

  def clear(company_id, params) do
    with {:ok, raw} <- req(params, "statement"),
         {:ok, st} <- known_write(raw) do
      n = company_id |> rows_of(st) |> length()

      Repo.delete_all(
        from(f in Formula, where: f.company_id == ^company_id and f.statement == ^st)
      )

      {:ok, %{statement: st, count: n}}
    end
  end

  def validate(params) do
    with {:ok, formula} <- present(params, "formula") do
      case FS.check(formula) do
        {:ok, tokens} -> {:ok, %{ok: 1, error: "", tokens: tokens}}
        {:error, e} -> {:ok, %{ok: 0, error: e, tokens: 0}}
      end
    end
  end

  ## Вътрешни

  defp rows_of(company_id, statement) do
    Repo.all(
      from(f in Formula,
        where: f.company_id == ^company_id and f.statement == ^statement,
        order_by: [asc: f.id]
      )
    )
  end

  defp row_json(f) do
    %{
      id: f.id,
      company_id: f.company_id,
      statement: f.statement,
      line_code: f.line_code,
      formula: f.formula
    }
  end

  defp known_get(raw) do
    statement = String.trim(raw || "")
    if Nom.known(statement), do: {:ok, statement}, else: {:error, {400, @bad_statement}}
  end

  defp known_write(statement) do
    if Nom.known(statement), do: {:ok, statement}, else: {:error, {422, @bad_statement}}
  end

  defp known_code(statement, code) do
    if code == "" or not Nom.has_code(statement, code),
      do: {:error, {422, "непозната статия"}},
      else: :ok
  end

  defp check_formula(formula) do
    case FS.check(formula) do
      {:ok, _} -> :ok
      {:error, e} -> {:error, {422, e}}
    end
  end

  defp req(params, key) do
    case Params.str(params, key) do
      {:present, value} ->
        trimmed = String.trim(value)
        if trimmed == "", do: {:error, {422, "#{key} е задължително"}}, else: {:ok, trimmed}

      _ ->
        {:error, {422, "#{key} е задължително"}}
    end
  end

  defp present(params, key) do
    case Params.str(params, key) do
      {:present, value} -> {:ok, String.trim(value)}
      _ -> {:error, {422, "#{key} е задължително"}}
    end
  end
end
