defmodule Botyaga.RateLimitTest do
  use ExUnit.Case, async: false

  alias Botyaga.RateLimit

  setup do
    RateLimit.reset()
    :ok
  end

  test "заключва след 10 неуспеха за ~15 минути" do
    for _ <- 1..10, do: RateLimit.login_failure("user")
    secs = RateLimit.login_locked("user")
    assert secs > 0 and secs <= 900

    RateLimit.login_success("user")
    assert RateLimit.login_locked("user") == nil
  end

  test "lock-ът е ограничен до 15 мин дори при clock warp" do
    now = System.system_time(:millisecond)
    # Симулирай warped monotonic clock: until е след 10 години.
    :ets.insert(:botyaga_rate_limit, {{:login, "warp"}, 10, now + 10 * 365 * 24 * 3600 * 1000})
    assert RateLimit.login_locked("warp") <= 900
  end

  test "под 10 неуспеха не заключва" do
    for _ <- 1..9, do: RateLimit.login_failure("user")
    assert RateLimit.login_locked("user") == nil
  end
end
