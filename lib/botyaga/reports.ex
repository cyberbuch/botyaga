defmodule Botyaga.Reports do
  @moduledoc """
  Справки от дневника и началните салда. JSON тялото се връща от `/v1/reports`;
  мрежата (`grid`) е за експорта на файлове (PDF/XLSX/ODS — фаза 9). Порт на `reports.rs`.
  """

  alias Botyaga.{FsFormulas, Params}
  alias Botyaga.Reports.{Book, Corr, Data, FS, Stock, Trial}

  def index(company_id, params) do
    with {:ok, built} <- prepare(company_id, params), do: {:ok, built.body}
  end

  def prepare(company_id, params) do
    kind = params |> str("kind") |> String.trim()
    kind = if kind == "", do: "trial_balance", else: kind
    account = params |> str("account") |> String.trim()

    with :ok <- check_kind(kind),
         {:ok, from, to} <- check_dates(params),
         {:ok, cpid} <- counterpart(params, kind) do
      wants_cp = kind in ["counterpart_trial", "counterpart_chrono"]
      filter_cp = if wants_cp, do: cpid, else: 0

      if kind == "stock" do
        loc = params |> str("location_id") |> String.trim() |> to_int(0)
        Stock.sheet(company_id, from, to, loc)
      else
        books = Data.load(company_id, from, to, account, filter_cp)
        built = dispatch(company_id, kind, books)
        line = Data.firm_line(books.firm_name, books.firm_eik)
        grid = if line != "", do: [[line] | built.grid], else: built.grid
        {:ok, %{built | grid: grid}}
      end
    end
  end

  defp dispatch(company_id, kind, books) do
    case Data.fs_statement(kind) do
      nil ->
        case kind do
          k when k in ["chronological", "counterpart_chrono"] -> Book.chrono(kind, books)
          "general_ledger" -> Book.ledger(kind, books)
          "correspondence_ledger" -> Corr.build(kind, books)
          _ -> Trial.build(kind, books)
        end

      statement ->
        FS.build(kind, books, FsFormulas.map(company_id, statement))
    end
  end

  defp check_kind(kind) do
    if Data.kind_ok(kind), do: :ok, else: {:error, {400, "непознат kind"}}
  end

  defp check_dates(params) do
    from = params |> str("from") |> String.trim()
    to = params |> str("to") |> String.trim()

    cond do
      not Data.day_ok(from) or not Data.day_ok(to) ->
        {:error, {400, "from и to са задължителни (YYYY-MM-DD)"}}

      from > to ->
        {:error, {400, "from трябва да е преди to"}}

      true ->
        {:ok, from, to}
    end
  end

  defp counterpart(params, kind) do
    cpid = params |> str("counterpart_id") |> String.trim() |> to_cp()
    wants_cp = kind in ["counterpart_trial", "counterpart_chrono"]

    if wants_cp and cpid <= 0,
      do: {:error, {400, "counterpart_id е задължителен"}},
      else: {:ok, cpid}
  end

  defp to_cp(""), do: 0

  defp to_cp(raw) do
    case Integer.parse(raw) do
      {n, ""} -> n
      _ -> -1
    end
  end

  defp to_int(raw, default) do
    case Integer.parse(raw) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp str(params, key) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end
end
