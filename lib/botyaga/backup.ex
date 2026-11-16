defmodule Botyaga.Backup do
  @moduledoc """
  Логически бекъп: `pg_dump` → gzip → S3 (`botyaga_backup_*.sql.gz` форматът се
  запазва). Порт на `s3store.rs#s3_backup` + `dump.rs`. За Postgres няма MUPIP
  архив (това е YottaDB-специфично) — pg_dump покрива цялата база.
  """

  alias Botyaga.{Repo, S3}

  def create(cfg) do
    with :ok <- S3.validate(cfg),
         {:ok, sql, tables} <- dump() do
      stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
      filename = "botyaga_backup_#{stamp}.sql.gz"
      key = cfg.prefix <> filename
      bytes = :zlib.gzip(sql)

      case S3.put(cfg, key, bytes, "application/gzip") do
        :ok ->
          {:ok,
           %{
             message: "Бекъп създаден: #{filename} (#{tables} таблици)",
             filename: filename,
             s3_key: key,
             size: byte_size(bytes),
             tables: tables
           }}

        error ->
          error
      end
    end
  end

  def delete(cfg, key) do
    key = String.trim(key || "")

    cond do
      key == "" ->
        {:error, {422, "s3_key е задължителен"}}

      not String.starts_with?(key, cfg.prefix) ->
        {:error, {400, "ключът не е в папката на botyaga"}}

      not S3.is_backup_name(String.replace_prefix(key, cfg.prefix, "")) ->
        {:error, {400, "ключът не е архив на botyaga"}}

      true ->
        S3.delete(cfg, key)
    end
  end

  defp dump do
    cfg = Application.get_env(:botyaga, Repo)
    host = to_string(cfg[:hostname] || "localhost")
    port = to_string(cfg[:port] || 5432)
    db = to_string(cfg[:database])
    user = to_string(cfg[:username] || "postgres")
    pass = cfg[:password] || ""

    args = ["--no-owner", "--no-privileges", "-h", host, "-p", port, "-U", user, db]

    case System.cmd("pg_dump", args, env: [{"PGPASSWORD", pass}], stderr_to_stdout: true) do
      {sql, 0} -> {:ok, sql, table_count()}
      {err, _} -> {:error, {500, "pg_dump: #{String.trim(err)}"}}
    end
  rescue
    e -> {:error, {500, "pg_dump липсва или не стартира: #{Exception.message(e)}"}}
  end

  defp table_count do
    Repo.query!("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'").rows
    |> hd()
    |> hd()
  end
end
