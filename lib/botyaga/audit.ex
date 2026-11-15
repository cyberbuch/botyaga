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
