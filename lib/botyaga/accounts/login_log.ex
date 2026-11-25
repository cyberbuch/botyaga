defmodule Botyaga.Accounts.LoginLog do
  @moduledoc "Лог за сесиите: кой влиза/излиза, кога и откъде (IP, user-agent)."

  import Ecto.Query

  alias Botyaga.{Repo, Stamp}
  alias Botyaga.Accounts.LoginEvent
  alias BotyagaWeb.Plugs.ClientKey

  # Логът за влизания не расте безкрайно: пази се само последните 20 дни.
  @retention_days 20

  @doc "Записва събитие. `conn` носи IP-то и user-agent-а на клиента."
  def record(conn, event, user_login, user_id \\ 0, detail \\ "") do
    # Логът не бива да събаря входа: дълъг вход се отрязва, грешката при запис се преглъща.
    result =
      Repo.insert(%LoginEvent{
        user_id: user_id,
        user_login: (user_login || "") |> to_string() |> String.slice(0, 255),
        event: event,
        ip: ClientKey.client_ip(conn),
        user_agent: user_agent(conn),
        detail: detail,
        created_at: Stamp.now()
      })

    _ = safe_prune()
    result
  end

  @doc "Изтрива събития по-стари от #{@retention_days} дни."
  def prune do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@retention_days * 86_400, :second)
      |> DateTime.truncate(:second)

    Repo.delete_all(from(e in LoginEvent, where: e.created_at < ^cutoff))
  end

  # Почистването не бива да събаря входа, ако базата временно откаже.
  defp safe_prune do
    prune()
  rescue
    _ -> :error
  end

  @doc "Списък с филтър по потребител и събитие, най-новите първо."
  def index(params) do
    user = params |> Map.get("user", "") |> to_string() |> String.trim() |> String.downcase()
    event = params |> Map.get("event", "") |> to_string() |> String.trim()

    Repo.all(from(e in LoginEvent, order_by: [desc: e.id]))
    |> Enum.filter(fn e ->
      (user == "" or String.contains?(String.downcase(e.user_login), user)) and
        (event == "" or e.event == event)
    end)
  end

  defp user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [value | _] -> String.slice(value, 0, 255)
      [] -> ""
    end
  end
end
