defmodule Transport.Auth do
  @moduledoc """
  Споделена автентификация с botyaga: валидира същия HS256 JWT (издател `botyaga`).
  Тайната идва от `BOTYAGA_JWT_SECRET`, или от настройките на botyaga (`auth.jwt_secret`),
  за да работи един вход без допълнителна конфигурация.
  """

  @iss "botyaga"

  def secret do
    case System.get_env("BOTYAGA_JWT_SECRET") do
      s when is_binary(s) and s != "" -> s
      _ -> Application.get_env(:transport, :jwt_secret) || botyaga_secret()
    end
  end

  defp botyaga_secret do
    case :persistent_term.get({__MODULE__, :secret}, nil) do
      nil ->
        value = fetch_botyaga_secret()
        :persistent_term.put({__MODULE__, :secret}, value)
        value

      value ->
        value
    end
  end

  defp fetch_botyaga_secret do
    url =
      Application.get_env(:transport, :botyaga_database_url) ||
        "ecto://postgres:postgres@localhost:5433/botyaga_dev"

    {:ok, pid} = Postgrex.start_link(pg_opts(url))

    try do
      case Postgrex.query!(
             pid,
             "SELECT value FROM settings WHERE setting_key = 'auth.jwt_secret'",
             []
           ) do
        %{rows: [[value]]} when is_binary(value) and value != "" -> value
        _ -> ""
      end
    after
      GenServer.stop(pid)
    end
  end

  defp pg_opts(url) do
    uri = URI.parse(url)
    [user, pass] = String.split(uri.userinfo || "postgres:postgres", ":", parts: 2)

    [
      hostname: uri.host || "localhost",
      port: uri.port || 5432,
      username: user,
      password: pass,
      database: String.trim_leading(uri.path || "/botyaga_dev", "/")
    ]
  end

  @doc "Връща `{:ok, claims}` само за валиден подпис, издател и срок."
  def decode(token) when is_binary(token) do
    secret = secret()

    case String.split(token, ".") do
      [header_b64, payload_b64, signature] ->
        with {:ok, header} <- segment_json(header_b64),
             %{"alg" => "HS256"} <- header,
             {:ok, payload} <- segment_json(payload_b64),
             true <- verify_signature(secret, "#{header_b64}.#{payload_b64}", signature) do
          build_claims(payload)
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def decode(_token), do: :error

  defp build_claims(payload) do
    claims = %{
      "sub" => Map.get(payload, "sub", ""),
      "exp" => Map.get(payload, "exp", 0),
      "iss" => Map.get(payload, "iss", ""),
      "mfa" => Map.get(payload, "mfa", 0),
      "ver" => Map.get(payload, "ver", 0)
    }

    if claims["iss"] == @iss and claims["sub"] != "" and claims["mfa"] != 1 and
         claims["exp"] > System.system_time(:second),
       do: {:ok, claims},
       else: :error
  end

  defp segment_json(segment) do
    with {:ok, json} <- Base.url_decode64(segment, padding: false),
         {:ok, value} <- Jason.decode(json) do
      {:ok, value}
    else
      _ -> :error
    end
  end

  defp verify_signature(secret, signing_input, signature) do
    expected =
      :crypto.mac(:hmac, :sha256, secret, signing_input) |> Base.url_encode64(padding: false)

    Plug.Crypto.secure_compare(expected, signature)
  end
end
