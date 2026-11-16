defmodule Botyaga.Accounts.JWT do
  @moduledoc """
  JWT HS256 с твърденията `sub`, `iat`, `exp`, `iss`, `mfa`, `ver` (форматът на
  ytbuch). Издателят е `botyaga`.
  """

  @iss "botyaga"
  @ttl 604_800
  @mfa_ttl 300

  def ttl, do: @ttl
  def mfa_ttl, do: @mfa_ttl

  def issue(secret, sub, ver, mfa \\ 0) do
    now = System.system_time(:second)
    ttl = if mfa == 1, do: @mfa_ttl, else: @ttl

    claims = %{
      "sub" => sub,
      "iat" => now,
      "exp" => now + ttl,
      "iss" => @iss,
      "mfa" => mfa,
      "ver" => ver
    }

    encode(secret, claims)
  end

  @doc "Връща `{:ok, claims}` само за валиден подпис, издател и срок."
  def decode(secret, token) when is_binary(token) do
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

  def decode(_secret, _token), do: :error

  defp build_claims(payload) do
    claims = %{
      "sub" => Map.get(payload, "sub", ""),
      "iat" => Map.get(payload, "iat", 0),
      "exp" => Map.get(payload, "exp", 0),
      "iss" => Map.get(payload, "iss", ""),
      "mfa" => Map.get(payload, "mfa", 0),
      "ver" => Map.get(payload, "ver", 0)
    }

    if claims["iss"] == @iss and claims["sub"] != "" and
         claims["exp"] > System.system_time(:second),
       do: {:ok, claims},
       else: :error
  end

  defp encode(secret, claims) do
    header = %{"alg" => "HS256", "typ" => "JWT"}

    signing_input =
      "#{encode_segment(Jason.encode!(header))}.#{encode_segment(Jason.encode!(claims))}"

    signature = :crypto.mac(:hmac, :sha256, secret, signing_input) |> encode_segment()
    "#{signing_input}.#{signature}"
  end

  defp encode_segment(data), do: Base.url_encode64(data, padding: false)

  defp segment_json(segment) when is_binary(segment) do
    with {:ok, json} <- segment_data(segment),
         {:ok, value} <- json_decode(json) do
      {:ok, value}
    else
      _ -> :error
    end
  end

  defp segment_json(_), do: :error

  defp segment_data(segment) do
    case Base.url_decode64(segment, padding: false) do
      {:ok, decoded} when is_binary(decoded) -> {:ok, decoded}
      _ -> :error
    end
  end

  defp json_decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, value} -> {:ok, value}
      _ -> :error
    end
  end

  defp json_decode(_), do: :error

  defp verify_signature(secret, signing_input, signature) do
    expected = :crypto.mac(:hmac, :sha256, secret, signing_input) |> encode_segment()
    Plug.Crypto.secure_compare(expected, signature)
  end
end
