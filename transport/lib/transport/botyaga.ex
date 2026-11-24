defmodule Transport.Botyaga do
  @moduledoc """
  Връзка към базата на botyaga само за четене: JWT тайната от настройките и
  правото на потребителя да работи във фирмата (активен, текуща версия на
  сесията, членство или суперадмин). Една връзка за всички заявки — при паднала
  база те чакат на опашка, вместо всяка да отваря своя.
  """

  use GenServer

  @secret_ttl :timer.seconds(60)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "`{:ok, тайна}` или `{:error, :unconfigured | :unavailable}`; празна тайна не се кешира."
  def secret do
    case GenServer.call(__MODULE__, :secret, :timer.seconds(5)) do
      {:ok, _} = ok -> ok
      _ -> {:error, :unavailable}
    end
  end

  @doc "`:ok`, или `{:error, {статус, пояснение}}` / `{:error, :unavailable}`."
  def check(sub, ver, company_id)
      when is_binary(sub) and is_integer(company_id) and company_id > 0 do
    case GenServer.call(__MODULE__, {:check, sub, ver, company_id}, :timer.seconds(5)) do
      :ok -> :ok
      {:error, {_, _}} = denied -> denied
      _ -> {:error, :unavailable}
    end
  end

  def check(_sub, _ver, _company_id), do: {:error, {403, "липсва фирма"}}

  @impl true
  def init(_opts), do: {:ok, %{conn: nil, secret: nil}}

  @impl true
  def handle_call(:secret, _from, s) do
    with_conn(s, fn pid, s ->
      now = System.monotonic_time(:millisecond)

      cached =
        case s.secret do
          {value, at} when now - at < @secret_ttl -> {:ok, value}
          _ -> :error
        end

      case cached do
        {:ok, value} ->
          {{:ok, value}, s}

        :error ->
          case Postgrex.query!(
                 pid,
                 "SELECT value FROM settings WHERE setting_key = 'auth.jwt_secret'",
                 []
               ) do
            %Postgrex.Result{rows: [[value]]} when is_binary(value) and value != "" ->
              {{:ok, value}, %{s | secret: {value, now}}}

            _ ->
              {{:error, :unconfigured}, s}
          end
      end
    end)
  end

  def handle_call({:check, sub, ver, company_id}, _from, s) do
    sql = """
    SELECT u.is_active, u.session_version, u.is_super_admin,
           EXISTS (SELECT 1 FROM user_companies m
                   WHERE m.user_id = u.id AND m.company_id = $2),
           EXISTS (SELECT 1 FROM companies c WHERE c.id = $2)
    FROM users u
    WHERE u.username = $1 OR u.email = $1
    """

    with_conn(s, fn pid, s ->
      {decide(Postgrex.query!(pid, sql, [sub, company_id]).rows, ver), s}
    end)
  end

  @doc false
  # Чистото решение по реда от botyaga: без IO, за да се тества директно.
  def decide([], _ver), do: {:error, {401, "потребителят не съществува"}}

  def decide([[active, version, super, member, company_exists]], ver) do
    if company_exists do
      case verdict(active, version, super, member, ver) do
        :ok -> :ok
        denied -> {:error, denied}
      end
    else
      {:error, {404, "фирмата не е намерена"}}
    end
  end

  # Суперадминът минава с текущата версия на сесията; останалите — и с членство.
  defp verdict(1, ver, 1, _member, ver), do: :ok
  defp verdict(1, ver, _super, true, ver), do: :ok

  defp verdict(1, version, _super, _member, ver) when version != ver,
    do: {401, "сесията е приключена — влезте отново"}

  defp verdict(1, _, _, _, _), do: {403, "нямате достъп до тази фирма"}
  defp verdict(_, _, _, _, _), do: {403, "потребителят е неактивен"}

  defp with_conn(s, fun) do
    case connect(s.conn) do
      {:ok, pid} ->
        try do
          {reply, s} = fun.(pid, %{s | conn: pid})
          {:reply, reply, s}
        rescue
          _ -> {:reply, {:error, :unavailable}, s}
        catch
          :exit, _ -> {:reply, {:error, :unavailable}, s}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, s}
    end
  end

  defp connect(pid) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: connect(nil)
  end

  defp connect(nil) do
    case Application.get_env(:transport, :botyaga_database_url) do
      nil ->
        {:error, :unconfigured}

      url ->
        case Postgrex.start_link(pg_opts(url)) do
          {:ok, pid} -> {:ok, pid}
          {:error, _} -> {:error, :unavailable}
        end
    end
  end

  defp pg_opts(url) do
    uri = URI.parse(url)
    [user, pass] = String.split(uri.userinfo || "", ":", parts: 2)

    [
      hostname: uri.host || "localhost",
      port: uri.port || 5432,
      username: user,
      password: pass,
      database: String.trim_leading(uri.path || "", "/")
    ]
  end
end
