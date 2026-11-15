defmodule Botyaga.Settings do
  @moduledoc """
  Глобални настройки като двойки ключ/стойност. Колоната в базата е
  `setting_key`, в JSON е `key`. Тайните се маскират, а `auth.jwt_secret`
  и активната фирма не се връщат изобщо.
  """

  alias Botyaga.Repo
  alias Botyaga.Setting

  @mask "••••••••"
  @secret_keys ~w(smtp.password s3.secret_key)

  def load do
    Repo.all(Setting)
    |> Map.new(&{&1.setting_key, &1.value || ""})
  end

  def get(key, default \\ "") do
    case Repo.get_by(Setting, setting_key: key) do
      %Setting{value: value} -> value || ""
      nil -> default
    end
  end

  def upsert(key, value) do
    case Repo.get_by(Setting, setting_key: key) do
      %Setting{} = setting ->
        Repo.update!(Ecto.Changeset.change(setting, value: value))

      nil ->
        Repo.insert!(%Setting{setting_key: key, value: value})
    end
  end

  @doc "Тайната за JWT: env или уникална за инсталацията в базата."
  def jwt_secret do
    case System.get_env("BOTYAGA_JWT_SECRET") do
      secret when is_binary(secret) and secret != "" ->
        secret

      _ ->
        case get("auth.jwt_secret") do
          "" ->
            secret = 32 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
            upsert("auth.jwt_secret", secret)
            secret

          secret ->
            secret
        end
    end
  end

  def registration_enabled? do
    not flag_off?(get("auth.registration_enabled"))
  end

  def smtp_cfg do
    %{
      host: get("smtp.host") |> String.trim(),
      port: parse_port(get("smtp.port"), 587),
      username: get("smtp.username"),
      password: get("smtp.password"),
      from_email: get("smtp.from_email") |> String.trim(),
      from_name: if(get("smtp.from_name") == "", do: "botyaga", else: get("smtp.from_name")),
      use_tls: not flag_off?(get("smtp.use_tls"))
    }
  end

  def s3_cfg do
    %{
      endpoint: get("s3.endpoint") |> String.trim(),
      bucket: get("s3.bucket") |> String.trim(),
      access_key: get("s3.access_key") |> String.trim(),
      secret_key: get("s3.secret_key"),
      region: if(get("s3.region") == "", do: "us-east-1", else: get("s3.region")),
      prefix: if(get("s3.prefix") == "", do: "backups/", else: get("s3.prefix"))
    }
  end

  def app_name do
    case get("app.name") |> String.trim() do
      "" -> "botyaga"
      name -> name
    end
  end

  def app_url, do: get("app.url") |> String.trim()

  def mail_ready? do
    app_url() != "" and get("smtp.host") |> String.trim() != "" and
      not flag_off?(get("smtp.enabled"))
  end

  @doc "Списъкът за GET /v1/system-settings: сортиран, с маскиране на тайните."
  def index_items do
    load()
    |> Enum.reject(fn {key, _} -> private?(key) end)
    |> Enum.map(fn {key, value} ->
      value = if secret?(key) and value != "", do: @mask, else: value
      %{key: key, value: value}
    end)
    |> Enum.sort_by(& &1.key)
  end

  @doc "Запис по подадените ключове. Маска или празно оставя тайната стара."
  def update_items(items) when is_list(items) do
    Enum.each(items, fn item ->
      key = (Map.get(item, "key") || Map.get(item, :key) || "") |> to_string() |> String.trim()

      if key != "" and not private?(key) do
        value = Map.get(item, "value", Map.get(item, :value))

        stored =
          case value do
            nil -> ""
            v when is_binary(v) -> v
            v when is_boolean(v) -> if(v, do: "1", else: "0")
            v when is_number(v) -> to_string(v)
            _ -> nil
          end

        if stored != nil and not (secret?(key) and (stored == "" or stored == @mask)) do
          upsert(key, stored)
        end
      end
    end)

    index_items()
  end

  def secret_keys, do: @secret_keys

  defp secret?(key), do: key in @secret_keys

  defp private?(key),
    do:
      key == "auth.jwt_secret" or String.starts_with?(key, "активна_фирма:") or
        String.starts_with?(key, "totp_last:")

  defp flag_off?(value) do
    value = String.trim(value)
    value == "0" or String.downcase(value) == "false"
  end

  defp parse_port(value, default) do
    case Integer.parse(String.trim(value)) do
      {port, _} when port > 0 -> port
      _ -> default
    end
  end
end
