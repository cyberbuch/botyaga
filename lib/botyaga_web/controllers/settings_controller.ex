defmodule BotyagaWeb.SettingsController do
  use BotyagaWeb, :controller

  alias Botyaga.{Access, Emails, Settings}
  alias BotyagaWeb.{Render, Respond}

  def index(conn, params) do
    Settings.index_items() |> Render.page(params) |> then(&Respond.ok(conn, &1))
  end

  def update(conn, params) do
    case Access.require_super_admin(conn.assigns.current_user) do
      :ok ->
        case params do
          %{"items" => items} when is_list(items) ->
            Settings.update_items(items) |> Render.page(params) |> then(&Respond.ok(conn, &1))

          _ ->
            Respond.error(conn, {400, "items е задължителен масив"})
        end

      {:error, :forbidden} ->
        Respond.error(conn, {403, "изисква се супер администратор"})
    end
  end

  def smtp_test(conn, params) do
    case Access.require_super_admin(conn.assigns.current_user) do
      :ok ->
        to = String.trim(params["to"] || "")
        cfg = Settings.smtp_cfg()

        cond do
          cfg.host == "" ->
            Respond.error(conn, {400, "SMTP host е задължителен"})

          to == "" ->
            Respond.error(conn, {422, "Получател е задължителен"})

          true ->
            case Emails.deliver_now(to, "Тест — #{Settings.app_name()}", "<p>Тестово писмо.</p>") do
              :ok -> Respond.ok(conn, %{message: "Имейлът е изпратен"})
              {:error, message} -> Respond.error(conn, {502, message})
            end
        end

      {:error, :forbidden} ->
        Respond.error(conn, {403, "изисква се супер администратор"})
    end
  end
end
