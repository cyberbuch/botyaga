defmodule Botyaga.S3 do
  @moduledoc """
  S3 (path-style, свой endpoint) през подписани заявки — без aws-sdk. Тест/бекъп/
  списък/триене на архиви. Порт на `s3store.rs` (SigV4 е в `S3.Sign`).
  """

  alias Botyaga.S3.Sign

  def validate(cfg) do
    cond do
      cfg.bucket == "" -> {:error, {422, "S3 bucket е задължителен"}}
      cfg.access_key == "" or cfg.secret_key == "" -> {:error, {400, "Невалидни credentials"}}
      true -> :ok
    end
  end

  def test(cfg) do
    with :ok <- validate(cfg),
         {:ok, _} <-
           request("GET", cfg.bucket, "", [{"list-type", "2"}, {"max-keys", "1"}], "", cfg) do
      {:ok, %{message: "Връзката с S3 е успешна. Bucket: #{cfg.bucket}"}}
    end
  end

  def list(cfg) do
    with :ok <- validate(cfg), do: list_page(cfg, nil, [])
  end

  defp list_page(cfg, token, acc) do
    params = [{"list-type", "2"}, {"prefix", cfg.prefix}, {"max-keys", "1000"}]
    params = if token, do: params ++ [{"continuation-token", token}], else: params

    case request("GET", cfg.bucket, "", params, "", cfg) do
      {:ok, xml} ->
        acc = acc ++ parse_contents(xml, cfg.prefix)

        if truncated?(xml) do
          case next_token(xml) do
            nil -> {:ok, finish(acc)}
            t -> list_page(cfg, t, acc)
          end
        else
          {:ok, finish(acc)}
        end

      error ->
        error
    end
  end

  defp finish(items) do
    items = Enum.sort_by(items, & &1.last_modified, :desc)
    %{items: items, count: length(items)}
  end

  def put(cfg, key, body, content_type) do
    with :ok <- validate(cfg),
         {:ok, _} <-
           request("PUT", cfg.bucket, key, [], body, cfg, [{"content-type", content_type}]) do
      :ok
    end
  end

  def delete(cfg, key) do
    with :ok <- validate(cfg),
         {:ok, _} <- request("DELETE", cfg.bucket, key, [], "", cfg) do
      {:ok, %{message: "Бекъпът е изтрит"}}
    end
  end

  defp request(method, bucket, key, params, body, cfg, extra_headers \\ []) do
    now = DateTime.utc_now()
    {url, headers} = Sign.sign_request(method, bucket, key, params, body, cfg, now)

    case Req.request(
           method: method,
           url: url,
           headers: headers ++ extra_headers,
           body: body,
           decode_body: false,
           retry: false,
           receive_timeout: 60_000
         ) do
      {:ok, %{status: status, body: resp}} when status in 200..299 ->
        {:ok, resp}

      {:ok, %{status: _status, body: resp}} ->
        {:error, {400, explain(resp, bucket)}}

      {:error, reason} ->
        {:error, {400, "S3: #{Exception.message(reason)}"}}
    end
  end

  defp explain(resp, bucket) do
    case tag(resp, "Code") do
      "NoSuchBucket" -> "Bucket '#{bucket}' не съществува"
      "InvalidAccessKeyId" -> "Невалиден Access Key"
      "SignatureDoesNotMatch" -> "Невалиден Secret Key"
      "AccessDenied" -> "Достъпът е отказан"
      "" -> tag(resp, "Message") || "S3 грешка"
      code -> tag(resp, "Message") || code
    end
  end

  defp parse_contents(xml, prefix) do
    ~r/<Contents>(.*?)<\/Contents>/s
    |> Regex.scan(xml)
    |> Enum.map(fn [_, block] ->
      key = tag(block, "Key") || ""
      filename = String.replace_prefix(key, prefix, "")
      size = String.to_integer(tag(block, "Size") || "0")

      %{
        key: key,
        filename: filename,
        size: size,
        size_human: human(size),
        last_modified: tag(block, "LastModified") || ""
      }
    end)
    |> Enum.filter(&is_backup_name(&1.filename))
  end

  defp truncated?(xml), do: tag(xml, "IsTruncated") == "true"
  defp next_token(xml), do: tag(xml, "NextContinuationToken")

  defp tag(xml, name) do
    case Regex.run(~r/<#{name}>(.*?)<\/#{name}>/s, xml) do
      [_, value] -> value
      _ -> nil
    end
  end

  def human(size) do
    if size < 1_048_576,
      do: :erlang.float_to_binary(size / 1024, decimals: 1) <> " KB",
      else: :erlang.float_to_binary(size / 1_048_576, decimals: 1) <> " MB"
  end

  @doc "Строг шаблон: botyaga_backup_*.sql.gz и ydb_backup_*.tar.gz, без пътища и .."
  def is_backup_name(name) do
    stem =
      cond do
        String.starts_with?(name, "botyaga_backup_") ->
          rest = String.replace_prefix(name, "botyaga_backup_", "")
          if String.ends_with?(rest, ".sql.gz"), do: String.replace_suffix(rest, ".sql.gz", "")

        String.starts_with?(name, "ydb_backup_") ->
          rest = String.replace_prefix(name, "ydb_backup_", "")
          if String.ends_with?(rest, ".tar.gz"), do: String.replace_suffix(rest, ".tar.gz", "")

        true ->
          nil
      end

    case stem do
      nil -> false
      "" -> false
      s -> not String.contains?(s, "..") and String.match?(s, ~r/^[A-Za-z0-9_.\-]+$/)
    end
  end
end
