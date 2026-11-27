defmodule BotyagaWeb.Plugs.Gate do
  @moduledoc """
  Всичко под `/v1` иска валиден токен, освен шестте входни пътя. Пътят се
  сваля до permission ключ; непознат път се отказва — deny by default.
  """

  import Plug.Conn

  alias Botyaga.{Accounts, Access, Companies}

  @public ~w(/v1/auth/token /v1/auth/mfa /v1/auth/logout /v1/auth/register /v1/auth/forgot-password
              /v1/auth/reset-password /v1/auth/registration-status)

  def init(opts), do: opts

  def call(conn, _opts) do
    path = conn.request_path

    cond do
      not String.starts_with?(path, "/v1/") -> conn
      path in @public -> conn
      true -> authenticate(conn)
    end
  end

  defp authenticate(conn) do
    secret = Application.get_env(:botyaga, :jwt_secret)
    token = bearer_token(conn)

    cond do
      token == "" ->
        halt(conn, 401, "липсва токен")

      match?({:ok, _}, Accounts.JWT.decode(secret, token)) ->
        conn |> verify_token(secret, token)

      true ->
        halt(conn, 401, "невалиден токен")
    end
  end

  defp verify_token(conn, secret, token) do
    {:ok, claims} = Accounts.JWT.decode(secret, token)

    cond do
      claims["mfa"] == 1 ->
        halt(conn, 401, "невалиден токен")

      Accounts.get_by_login(claims["sub"]) == nil ->
        halt(conn, 401, "потребителят не съществува")

      true ->
        user = Accounts.get_by_login(claims["sub"])

        cond do
          user.is_active != 1 ->
            halt(conn, 403, "потребителят е неактивен")

          user.session_version != claims["ver"] ->
            halt(conn, 401, "сесията е приключила — влезте отново")

          true ->
            conn |> assign(:current_user, user) |> authorize(user)
        end
    end
  end

  defp authorize(conn, user) do
    case required_permission(conn.method, conn.request_path) do
      :unknown ->
        halt(conn, 404, "непознат път")

      :any ->
        conn

      {:key, key} ->
        if user.is_super_admin == 1 do
          conn
        else
          authorize_company(conn, user, key)
        end
    end
  end

  defp authorize_company(conn, user, key) do
    case Companies.resolve_active(user.username) do
      {:ok, company_id} ->
        perms = Access.perms_for(user, company_id)

        if Access.allowed?(perms, key, is_super_admin: user.is_super_admin) do
          conn
        else
          halt(conn, 403, "липсва право: #{key}")
        end

      {:error, _} ->
        halt(conn, 403, "нямате достъп до фирма")
    end
  end

  @doc "Кой permission ключ пази даден /v1 път."
  def required_permission(method, path) do
    case String.split(path, "/", trim: true) do
      ["v1", "companies"] ->
        if method == "GET", do: :any, else: {:key, "companies"}

      ["v1", "companies", _id, "users"] ->
        {:key, "users"}

      ["v1", "companies", _id, "users", _user_id] ->
        {:key, "users"}

      ["v1", "companies", _id | _rest] ->
        {:key, "companies"}

      ["v1", segment | rest] ->
        segment_permission(method, segment, rest)

      _ ->
        :any
    end
  end

  defp segment_permission(_method, "company-locations", _), do: {:key, "companies"}
  defp segment_permission(_method, "beneficial-owners", _), do: {:key, "companies"}
  defp segment_permission(_method, "ultimate-parents", _), do: {:key, "companies"}
  defp segment_permission(_method, "document-series", _), do: {:key, "companies"}
  defp segment_permission(_method, "accounts", _), do: {:key, "accounts"}
  defp segment_permission(_method, "counterparts", _), do: {:key, "counterparts"}
  defp segment_permission(_method, "addresses", _), do: {:key, "counterparts"}
  defp segment_permission(_method, "products", _), do: {:key, "products"}
  defp segment_permission(_method, "product-name-mappings", _), do: {:key, "products"}
  defp segment_permission(_method, "invoices", _), do: {:key, "invoices"}
  defp segment_permission(_method, "scans", _), do: {:key, "scans"}
  defp segment_permission(_method, "journal", _), do: {:key, "journal"}
  defp segment_permission(_method, "accounting-periods", _), do: {:key, "periods"}
  defp segment_permission(_method, "opening-balances", _), do: {:key, "periods"}

  # ytbuch пропуска този ключ в gate-а си и връща 404 за приключването; тук е поправено.
  defp segment_permission(_method, "closing-operations", _), do: {:key, "periods"}
  defp segment_permission(_method, "vat", _), do: {:key, "vat"}
  defp segment_permission(_method, "oss", _), do: {:key, "vat"}
  defp segment_permission(_method, "production-cards", _), do: {:key, "production"}
  defp segment_permission(_method, "bank-accounts", _), do: {:key, "banking"}
  defp segment_permission(_method, "bank-formats", _), do: {:key, "banking"}
  defp segment_permission(_method, "bank-transactions", _), do: {:key, "banking"}
  defp segment_permission(_method, "bank-matching-rules", _), do: {:key, "banking"}
  defp segment_permission(_method, "fixed-assets", _), do: {:key, "assets"}
  defp segment_permission(_method, "fixed-asset-categories", _), do: {:key, "assets"}
  defp segment_permission(_method, "inventory", _), do: {:key, "stock"}
  defp segment_permission(_method, "internal-docs", _), do: {:key, "stock"}
  defp segment_permission(_method, "material-issues", _), do: {:key, "stock"}

  defp segment_permission(_method, "stock", ["rules" | _]), do: {:key, "companies"}
  defp segment_permission(_method, "stock", _), do: {:key, "stock"}

  defp segment_permission(_method, "recipes", _), do: {:key, "production"}
  defp segment_permission(_method, "production-orders", _), do: {:key, "production"}
  defp segment_permission(_method, "production-receipts", _), do: {:key, "production"}
  defp segment_permission(_method, "dividend-distributions", _), do: {:key, "dividends"}
  defp segment_permission(_method, "dividends", _), do: {:key, "dividends"}
  defp segment_permission(_method, "reports", _), do: {:key, "reports"}
  defp segment_permission(_method, "fs", _), do: {:key, "reports"}

  defp segment_permission(_method, "audit-logs", ["invoice" | _]), do: {:key, "invoices"}
  defp segment_permission(_method, "audit-logs", ["journal" | _]), do: {:key, "journal"}
  defp segment_permission(_method, "audit-logs", ["internal_doc" | _]), do: {:key, "stock"}
  defp segment_permission(_method, "audit-logs", ["material_issue" | _]), do: {:key, "stock"}

  defp segment_permission(_method, "audit-logs", ["production_order" | _]),
    do: {:key, "production"}

  defp segment_permission(_method, "audit-logs", ["production_receipt" | _]),
    do: {:key, "production"}

  defp segment_permission(_method, "audit-logs", ["bank_tx" | _]), do: {:key, "banking"}
  defp segment_permission(_method, "audit-logs", _), do: {:key, "reports"}

  defp segment_permission(_method, "saft", ["export" | _]), do: {:key, "saft"}
  defp segment_permission(_method, "saft", ["movement-mappings" | _]), do: {:key, "saft"}
  defp segment_permission(_method, "saft", _), do: :any

  defp segment_permission(_method, "users", _), do: {:key, "users"}
  defp segment_permission(_method, "roles", _), do: {:key, "users"}
  defp segment_permission(_method, "admin", _), do: {:key, "users"}
  defp segment_permission(_method, "system-settings", _), do: {:key, "settings"}
  defp segment_permission(_method, "exchange-rates", _), do: {:key, "rates"}

  defp segment_permission(_method, "me", _), do: :any
  defp segment_permission(_method, "dashboard", _), do: :any
  defp segment_permission(_method, "active-company", _), do: :any
  defp segment_permission(_method, "units", _), do: :any
  defp segment_permission(_method, "vat-exemptions", _), do: :any

  defp segment_permission(_method, _segment, _rest), do: :unknown

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [value | _] ->
        value
        |> String.trim()
        |> case do
          "Bearer " <> token -> String.trim(token)
          "bearer " <> token -> String.trim(token)
          _ -> ""
        end

      [] ->
        ""
    end
  end

  defp halt(conn, status, detail) do
    BotyagaWeb.Respond.error(conn, {status, detail}) |> halt()
  end
end
