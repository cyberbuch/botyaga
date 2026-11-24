defmodule Transport.Auth do
  @moduledoc """
  Споделена автентикация с botyaga: валидира същия HS256 JWT (издател `botyaga`).
  Тайната идва от `BOTYAGA_JWT_SECRET`, или от настройките на botyaga (`auth.jwt_secret`),
  за да работи един вход без допълнителна конфигурация.
  """

  @iss "botyaga"

  # env → config → базата на botyaga. Празна тайна не е тайна: с нея не се подписва.
  def secret do
    case System.get_env("BOTYAGA_JWT_SECRET") do
      s when is_binary(s) and s != "" -> {:ok, s}
      _ -> configured(Application.get_env(:transport, :jwt_secret))
    end
  end

  defp configured(s) when is_binary(s) and s != "", do: {:ok, s}
  defp configured(_), do: Transport.Botyaga.secret()

  @doc "`{:ok, claims}`, `:error`, или `{:error, :unavailable}` когато няма откъде тайна."
  def decode(token) when is_binary(token) do
    case secret() do
      {:ok, secret} -> verify(token, secret)
      {:error, _} -> {:error, :unavailable}
    end
  end

  def decode(_token), do: :error

  defp verify(token, secret) do
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
