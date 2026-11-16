defmodule Botyaga.S3.Sign do
  @moduledoc """
  AWS Signature V4 за S3 (path-style), без външни зависимости — `:crypto` + `Req`.
  Чистата част (канонична заявка, подпис) се тества с фиксирани входове.
  """

  @algorithm "AWS4-HMAC-SHA256"

  def sha256hex(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)
  defp hmac_hex(key, data), do: hmac(key, data) |> Base.encode16(case: :lower)

  def signing_key(secret, date, region) do
    ("AWS4" <> secret)
    |> hmac(date)
    |> hmac(region)
    |> hmac("s3")
    |> hmac("aws4_request")
  end

  @doc "RFC3986 кодиране; `keep_slash` пази `/` за пътища."
  def uri_encode(str, keep_slash \\ false) do
    str
    |> :binary.bin_to_list()
    |> Enum.map_join(fn b ->
      cond do
        b in ?A..?Z or b in ?a..?z or b in ?0..?9 or b in [?-, ?_, ?., ?~] -> <<b>>
        b == ?/ and keep_slash -> "/"
        true -> "%" <> Base.encode16(<<b>>, case: :upper)
      end
    end)
  end

  def canonical_query(params) do
    params
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join("&", fn {k, v} -> "#{uri_encode(k)}=#{uri_encode(v)}" end)
  end

  @doc "Authorization хедър за заявката. `headers` са {име, стойност} с малки имена."
  def authorization(method, path, query, headers, payload_hash, cfg, amzdate) do
    date = String.slice(amzdate, 0, 8)
    scope = "#{date}/#{cfg.region}/s3/aws4_request"

    sorted = Enum.sort_by(headers, fn {k, _} -> k end)
    canonical_headers = Enum.map_join(sorted, fn {k, v} -> "#{k}:#{String.trim(v)}\n" end)
    signed_headers = sorted |> Enum.map(fn {k, _} -> k end) |> Enum.join(";")

    canonical_request =
      Enum.join(
        [method, uri_encode(path, true), query, canonical_headers, signed_headers, payload_hash],
        "\n"
      )

    string_to_sign =
      Enum.join([@algorithm, amzdate, scope, sha256hex(canonical_request)], "\n")

    signature = hmac_hex(signing_key(cfg.secret_key, date, cfg.region), string_to_sign)

    "#{@algorithm} Credential=#{cfg.access_key}/#{scope}, SignedHeaders=#{signed_headers}, Signature=#{signature}"
  end

  @doc "Подписва заявка: връща {url, headers} с host/x-amz-date/x-amz-content-sha256/authorization."
  def sign_request(method, bucket, key, query_params, body, cfg, now) do
    amzdate = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    path = "/" <> bucket <> if(key == "", do: "", else: "/" <> key)
    query = canonical_query(query_params)
    payload_hash = sha256hex(body)
    host = host_of(cfg)

    headers = [
      {"host", host},
      {"x-amz-content-sha256", payload_hash},
      {"x-amz-date", amzdate}
    ]

    auth = authorization(method, path, query, headers, payload_hash, cfg, amzdate)
    url = "https://" <> host <> path <> if(query == "", do: "", else: "?" <> query)

    {url,
     [
       {"authorization", auth},
       {"x-amz-content-sha256", payload_hash},
       {"x-amz-date", amzdate}
     ]}
  end

  def host_of(cfg) do
    case cfg.endpoint do
      "" -> "s3.#{cfg.region}.amazonaws.com"
      endpoint -> endpoint |> String.replace(~r/^https?:\/\//, "") |> String.trim_trailing("/")
    end
  end
end
