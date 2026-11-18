defmodule Botyaga.Banking.Rules do
  @moduledoc """
  Правила за банкови транзакции: ключови думи → сметка (и контрагент).
  Текстът се нормализира (кирилица → латиница), за да съвпадат „ПОС“/„POS“.
  При няколко съвпадения печели правилото с по-висок приоритет.
  """

  import Ecto.Query

  alias Botyaga.{Catalog, Params, Repo}
  alias Botyaga.Banking.{Rule, Transaction}

  @cyr [
    {"а", "a"},
    {"б", "b"},
    {"в", "v"},
    {"г", "g"},
    {"д", "d"},
    {"е", "e"},
    {"ж", "zh"},
    {"з", "z"},
    {"и", "i"},
    {"й", "y"},
    {"к", "k"},
    {"л", "l"},
    {"м", "m"},
    {"н", "n"},
    {"о", "o"},
    {"п", "p"},
    {"р", "r"},
    {"с", "s"},
    {"т", "t"},
    {"у", "u"},
    {"ф", "f"},
    {"х", "h"},
    {"ц", "ts"},
    {"ч", "ch"},
    {"ш", "sh"},
    {"щ", "sht"},
    {"ъ", "a"},
    {"ь", ""},
    {"ю", "yu"},
    {"я", "ya"},
    {"э", "e"},
    {"ы", "y"},
    {"ё", "e"}
  ]

  @legal_forms ~w(eood ood ad et kd kda ltd llc gmbh inc)

  def fold(text) do
    text
    |> String.downcase()
    |> String.graphemes()
    |> Enum.map(fn ch ->
      case Enum.find(@cyr, fn {cyr, _} -> cyr == ch end) do
        {_, lat} -> lat
        nil -> if String.match?(ch, ~r/[a-z0-9]/), do: ch, else: " "
      end
    end)
    |> Enum.join()
    |> String.split()
    |> Enum.join(" ")
  end

  def company_key(text) do
    fold(text)
    |> String.split()
    |> Enum.reject(&(&1 in @legal_forms))
    |> Enum.join(" ")
  end

  def contains_keyword(haystack, keyword) do
    needle = fold(keyword)
    needle != "" and String.contains?(fold(haystack), needle)
  end

  defp matches_keywords(text, keywords) do
    keywords
    |> String.split(",")
    |> Enum.any?(fn raw ->
      kw = String.trim(raw)
      kw != "" and contains_keyword(text, kw)
    end)
  end

  def direction_matches(direction, amount) do
    v =
      case Float.parse(amount) do
        {f, _} -> f
        :error -> 0.0
      end

    case direction do
      "debit" -> v < 0.0
      "credit" -> v > 0.0
      _ -> true
    end
  end

  def find_rule(rules, text, amount) do
    if String.trim(text) == "" do
      nil
    else
      rules
      |> Enum.filter(&(&1.is_active == 1))
      |> Enum.filter(fn r ->
        direction_matches(r.direction, amount) and matches_keywords(text, r.keywords)
      end)
      |> Enum.max_by(& &1.priority, fn -> nil end)
    end
  end

  def find_counterpart_id(counterparts, contra_name) do
    key = company_key(contra_name)

    if String.length(key) < 3 do
      nil
    else
      Enum.find_value(counterparts, fn {id, name} ->
        cp_key = company_key(name)

        cond do
          cp_key == "" ->
            nil

          cp_key == key ->
            id

          String.length(cp_key) >= 5 and String.length(key) >= 5 and
              (String.contains?(key, cp_key) or String.contains?(cp_key, key)) ->
            id

          true ->
            nil
        end
      end)
    end
  end

  ## CRUD

  def index(company_id) do
    rules_of(company_id) |> Enum.map(&rule_json/1)
  end

  def create(company_id, params) do
    with {:ok, attrs} <- parse_rule(params),
         :ok <- ensure_ref(Catalog.Account, attrs.account_id, company_id, "сметката"),
         :ok <- ensure_counterpart(attrs.counterpart_id, company_id) do
      rule = Repo.insert!(struct(%Rule{company_id: company_id}, attrs))
      {:ok, rule_json(rule)}
    end
  end

  def update(company_id, id, params) do
    with {:ok, attrs} <- parse_rule(params),
         :ok <- ensure_ref(Catalog.Account, attrs.account_id, company_id, "сметката"),
         :ok <- ensure_counterpart(attrs.counterpart_id, company_id) do
      case Repo.get_by(Rule, id: Params.id(id), company_id: company_id) do
        nil -> {:error, {404, "правилото не е намерено"}}
        rule -> {:ok, rule_json(Repo.update!(Ecto.Changeset.change(rule, attrs)))}
      end
    end
  end

  def delete(company_id, id) do
    Repo.delete_all(
      from(r in Rule, where: r.id == ^Params.id(id) and r.company_id == ^company_id)
    )

    {:ok, nil}
  end

  defp rules_of(company_id) do
    Repo.all(
      from(r in Rule, where: r.company_id == ^company_id, order_by: [desc: r.priority, asc: r.id])
    )
  end

  defp rule_json(r) do
    %{
      id: r.id,
      name: r.name,
      keywords: r.keywords,
      direction: r.direction,
      priority: r.priority,
      is_active: r.is_active == 1,
      account_id: r.account_id,
      counterpart_id: r.counterpart_id
    }
  end

  defp parse_rule(params) do
    with {:ok, name} <- required(params, "name"),
         {:ok, keywords} <- required(params, "keywords") do
      direction = params |> string("direction", "any") |> String.trim()

      if direction not in ["any", "debit", "credit"] do
        {:error, {422, "direction е any, debit или credit"}}
      else
        account_id = Params.integer(params, "account_id") || 0

        if account_id <= 0 do
          {:error, {422, "account_id е задължителен"}}
        else
          {:ok,
           %{
             name: String.trim(name),
             keywords: String.trim(keywords),
             direction: direction,
             priority: Params.integer(params, "priority") || 0,
             is_active: if(Map.get(params, "is_active") == false, do: 0, else: 1),
             account_id: account_id,
             counterpart_id: Params.integer(params, "counterpart_id") || 0
           }}
        end
      end
    end
  end

  ## Шаблони

  @defaults [
    {"POS покупки",
     "POS,ПОС,pos трансакция,покупка на пос,pos purchase,card purchase,покупка с карта,покупка с дк",
     "debit", ["447", "446", "50902"], 100},
    {"ATM теглене",
     "ATM,АТМ,atm трансакция,теглене,withdrawal,cash withdrawal,теглене на каса,теглене на пари",
     "debit", ["501"], 90},
    {"Банкови такси",
     "автоматична такса,такса теглене,такса за поддръжка,комисионна,bank fee,commission,месечна такса,мес. такса,monthly fee",
     "debit", ["629"], 80},
    {"Получени преводи от клиенти",
     "получен директен превод,получен превод,sct instant получен,incoming credit,credit transfer received",
     "credit", ["411"], 70},
    {"Издадени преводи към доставчици",
     "издаден превод,sct instant издаден,изходящ превод,outgoing credit,issued transfer", "debit",
     ["401"], 60},
    {"Аванси", "аванс,avans,advance", "debit", ["402"], 50}
  ]

  def defaults(company_id) do
    existing = rules_of(company_id) |> Enum.map(& &1.name)

    created =
      Enum.reduce(@defaults, 0, fn {name, keywords, direction, codes, priority}, count ->
        if name in existing do
          count
        else
          account_id =
            Enum.find_value(codes, 0, fn code ->
              case Repo.get_by(Catalog.Account, company_id: company_id, number: code) do
                nil -> nil
                account -> account.id
              end
            end)

          if account_id <= 0 do
            count
          else
            Repo.insert!(%Rule{
              company_id: company_id,
              name: name,
              keywords: keywords,
              direction: direction,
              priority: priority,
              is_active: 1,
              account_id: account_id,
              counterpart_id: 0
            })

            count + 1
          end
        end
      end)

    {:ok, %{created: created}}
  end

  ## Разнасяне (само преглед — никога не осчетоводява автоматично;
  ## осчетоводяването е поединично през `Tx.book_tx` с потвърждение)

  def preview(company_id, sub), do: allocate(company_id, sub)
  def auto_allocate(company_id, sub), do: allocate(company_id, sub)

  defp allocate(company_id, _sub) do
    rules = rules_of(company_id)

    counterparts =
      Repo.all(
        from(c in Catalog.Counterpart, where: c.company_id == ^company_id, select: {c.id, c.name})
      )

    accounts = Repo.all(from(a in Catalog.Account, where: a.company_id == ^company_id))

    txs =
      Repo.all(
        from(t in Transaction,
          where: t.company_id == ^company_id and t.is_allocated == 0,
          order_by: [asc: t.id]
        )
      )

    {matched, unmatched, errors, hits, details} =
      Enum.reduce(txs, {0, 0, 0, 0, []}, fn tx, {matched, unmatched, errors, hits, details} ->
        text = "#{tx.description} #{tx.counterpart_name} #{tx.reference}"

        case find_rule(rules, text, tx.amount) do
          nil ->
            {matched, unmatched + 1, errors, hits,
             add_detail(details, %{
               id: tx.id,
               status: "unmatched",
               text: String.slice(text, 0, 80)
             })}

          rule ->
            cp =
              if rule.counterpart_id > 0,
                do: rule.counterpart_id,
                else: find_counterpart_id(counterparts, tx.counterpart_name) || 0

            hits = if cp > 0, do: hits + 1, else: hits

            cp_name =
              Enum.find_value(counterparts, "", fn {id, name} -> if id == cp, do: name end)

            detail = %{
              id: tx.id,
              status: "matched",
              rule: rule.name,
              account: account_label(accounts, rule.account_id),
              counterpart: cp_name,
              amount: tx.amount,
              text: String.slice(text, 0, 80)
            }

            {matched + 1, unmatched, errors, hits, add_detail(details, detail)}
        end
      end)

    {:ok,
     %{
       matched: matched,
       unmatched: unmatched,
       errors: errors,
       counterpart_hits: hits,
       details: details
     }}
  end

  defp add_detail(details, detail) when length(details) < 50, do: details ++ [detail]
  defp add_detail(details, _detail), do: details

  defp account_label(accounts, id) do
    case Enum.find(accounts, &(&1.id == id)) do
      nil -> "##{id}"
      account -> "#{account.number} #{account.name}"
    end
  end

  defp ensure_ref(_schema, id, _company_id, _what) when id <= 0, do: :ok

  defp ensure_ref(schema, id, company_id, what) do
    if Repo.get_by(schema, id: id, company_id: company_id) == nil do
      {:error, {404, "#{what} не е намерен"}}
    else
      :ok
    end
  end

  defp ensure_counterpart(id, company_id),
    do: ensure_ref(Catalog.Counterpart, id, company_id, "контрагентът")

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

  defp string(params, key, default) do
    case Params.str(params, key) do
      {:present, value} -> value
      _ -> default
    end
  end
end
