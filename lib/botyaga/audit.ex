defmodule Botyaga.Audit do
  @moduledoc "Одитна следа: кой, кога и какво е променил по документите и статиите."

  import Ecto.Query

  alias Botyaga.{Accounts, Repo, Stamp}
  alias Botyaga.Audit.Log

  def record(
        company_id,
        sub,
        entity_type,
        entity_id,
        entity_number,
        action,
        summary,
        old_amount,
        new_amount,
        old_data,
        new_data
      ) do
    actor = actor(sub)
    entity_id = to_id(entity_id)

    Repo.insert!(%Log{
      company_id: company_id,
      user_id: actor.id,
      user_login: actor.login,
      user_name: actor.name,
      entity_type: entity_type,
      entity_id: entity_id,
      entity_number: entity_number,
      action: action,
      summary: summary,
      old_amount: old_amount,
      new_amount: new_amount,
      old_data: compact(old_data),
      new_data: compact(new_data),
      created_at: Stamp.now()
    })
  end

  defp to_id(value) when is_integer(value), do: value

  defp to_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp to_id(_), do: 0

  defp actor(sub) do
    case Accounts.get_by_login(sub) do
      nil -> %{id: 0, login: sub, name: ""}
      user -> %{id: user.id, login: user.username, name: user.name}
    end
  end

  defp compact(nil), do: ""
  defp compact(value), do: Jason.encode!(value)

  @doc "Печатите за списък: първи запис = създаване, последен = редакция."
  def stamps_for(company_id, entity_type) do
    logs =
      Repo.all(
        from(l in Log,
          where: l.company_id == ^company_id and l.entity_type == ^entity_type,
          order_by: [asc: l.id]
        )
      )

    Enum.reduce(logs, %{}, fn log, acc ->
      who = if String.trim(log.user_name || "") != "", do: log.user_name, else: log.user_login

      stamp =
        Map.get(acc, log.entity_id, %{
          created_by: "",
          created_at: "",
          updated_by: "",
          updated_at: "",
          edit_count: 0
        })

      stamp =
        if stamp.created_at == "" do
          %{stamp | created_by: who, created_at: Stamp.to_stamp(log.created_at)}
        else
          stamp
        end

      stamp = %{stamp | updated_by: who, updated_at: Stamp.to_stamp(log.created_at)}

      stamp =
        if log.action != "create", do: %{stamp | edit_count: stamp.edit_count + 1}, else: stamp

      Map.put(acc, log.entity_id, stamp)
    end)
  end

  def attach_stamp(value, nil) do
    Map.merge(value, %{
      created_by: "",
      created_at: "",
      updated_by: "",
      updated_at: "",
      edit_count: 0
    })
  end

  def attach_stamp(value, stamp), do: Map.merge(value, stamp)

  def history_for(company_id, entity_type, entity_id) do
    Repo.all(
      from(l in Log,
        where:
          l.company_id == ^company_id and l.entity_type == ^entity_type and
            l.entity_id == ^entity_id,
        order_by: [desc: l.id]
      )
    )
    |> Enum.map(&row_json(&1, true))
  end

  @doc "Одитен списък с филтри (entity_type/id, action, user, from/to, changed_only, q)."
  def index(company_id, params) do
    et = params |> str("entity_type") |> String.trim()
    eid = Botyaga.Params.integer(params, "entity_id") || 0
    act = params |> str("action") |> String.trim()
    user = params |> str("user") |> String.trim() |> String.downcase()
    from = params |> str("from") |> String.trim()
    to = params |> str("to") |> String.trim()
    changed_only = String.trim(str(params, "changed_only")) in ["1", "true", "yes"]
    search = params |> str("q") |> String.trim() |> String.downcase()

    Repo.all(from(l in Log, where: l.company_id == ^company_id, order_by: [desc: l.id]))
    |> Enum.filter(fn log ->
      keep?(log, et, eid, act, user, from, to, changed_only, search)
    end)
    |> Enum.map(&row_json(&1, true))
  end

  def entity_history(company_id, entity_type, entity_id) do
    items = history_for(company_id, String.trim(entity_type), Botyaga.Params.id(entity_id))
    %{items: items, count: length(items)}
  end

  defp keep?(log, et, eid, act, user, from, to, changed_only, search) do
    day = String.slice(Stamp.to_stamp(log.created_at), 0, 10)
    old_amt = log.old_amount || ""
    new_amt = log.new_amount || ""
    ulogin = log.user_login || ""
    uname = log.user_name || ""

    cond do
      et != "" and log.entity_type != et ->
        false

      eid > 0 and log.entity_id != eid ->
        false

      act != "" and log.action != act ->
        false

      user != "" and not String.contains?(String.downcase(ulogin), user) and
          not String.contains?(String.downcase(uname), user) ->
        false

      from != "" and day < from ->
        false

      to != "" and day > to ->
        false

      changed_only and not changed?(log, old_amt, new_amt) ->
        false

      search != "" and not String.contains?(haystack(log, old_amt, new_amt), search) ->
        false

      true ->
        true
    end
  end

  defp changed?(log, old_amt, new_amt) do
    diff = old_amt != "" and new_amt != "" and old_amt != new_amt
    risky = log.action in ["update", "delete", "unpost"]
    diff or risky
  end

  defp haystack(log, old_amt, new_amt) do
    ("#{log.user_login} #{log.user_name} #{log.entity_type} #{log.entity_id} " <>
       "#{log.entity_number} #{log.action} #{log.summary} #{old_amt} #{new_amt}")
    |> String.downcase()
  end

  defp str(params, key) do
    case Botyaga.Params.str(params, key) do
      {:present, value} -> value
      _ -> ""
    end
  end

  defp row_json(log, with_snapshots) do
    amount_changed =
      (log.old_amount || "") != "" and (log.new_amount || "") != "" and
        log.old_amount != log.new_amount

    value = %{
      id: log.id,
      company_id: log.company_id,
      user_id: log.user_id,
      user_login: log.user_login,
      user_name: log.user_name,
      entity_type: log.entity_type,
      entity_id: log.entity_id,
      entity_number: log.entity_number,
      action: log.action,
      summary: log.summary,
      old_amount: log.old_amount,
      new_amount: log.new_amount,
      amount_changed: amount_changed,
      created_at: Stamp.to_stamp(log.created_at)
    }

    if with_snapshots do
      Map.merge(value, %{old_data: parse_json(log.old_data), new_data: parse_json(log.new_data)})
    else
      value
    end
  end

  defp parse_json(nil), do: nil
  defp parse_json(""), do: nil

  defp parse_json(raw) do
    case Jason.decode(raw) do
      {:ok, value} -> value
      _ -> nil
    end
  end
end
