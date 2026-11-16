defmodule Botyaga.RateLimit do
  @moduledoc """
  Кошове за лимита: общ лимит по потребител (300 накуп, 20/сек) и строг
  лимит по IP за вход и регистрация (30 накуп, 2/сек). Заключване на
  акаунта след 10 неуспешни опита за 15 минути.
  """

  use GenServer

  @table :botyaga_rate_limit
  @max_fails 10
  @lock_ms 15 * 60 * 1000
  @max_tracked 10_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    :ets.new(@table, [:set, :public, :named_table])
    {:ok, %{}}
  end

  @doc "Връща `:allow` или `{:deny, retry_after_ms}`."
  def check(key, burst, per_sec) do
    now = System.system_time(:millisecond)
    sweep()

    tokens =
      case :ets.lookup(@table, {:bucket, key}) do
        [{_, tokens, last}] -> min(burst, tokens + (now - last) * per_sec / 1000)
        [] -> burst
      end

    if tokens >= 1 do
      :ets.insert(@table, {{:bucket, key}, tokens - 1, now})
      :allow
    else
      :ets.insert(@table, {{:bucket, key}, tokens, now})
      {:deny, trunc((1 - tokens) / per_sec * 1000) + 1}
    end
  end

  def login_locked(login) do
    key = {:login, String.downcase(String.trim(login))}
    now = System.system_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{_, _fails, until}] when until > now -> div(min(until - now, @lock_ms), 1000)
      _ -> nil
    end
  end

  def login_failure(login) do
    key = {:login, String.downcase(String.trim(login))}
    now = System.system_time(:millisecond)

    {fails, until} =
      case :ets.lookup(@table, key) do
        [{_, fails, until}] -> {fails, until}
        [] -> {0, 0}
      end

    fails = fails + 1
    until = if fails >= @max_fails, do: now + @lock_ms, else: until
    :ets.insert(@table, {key, fails, until})
  end

  def login_success(login) do
    :ets.delete(@table, {:login, String.downcase(String.trim(login))})
  end

  @doc "Изчиства кошовете — само за тестове."
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  defp sweep do
    if :ets.info(@table, :size) > @max_tracked do
      now = System.system_time(:millisecond)

      :ets.select_delete(@table, [
        {{{:login, :_}, :_, :"$1"}, [{:<, :"$1", now}], [true]}
      ])
    end
  end
end
