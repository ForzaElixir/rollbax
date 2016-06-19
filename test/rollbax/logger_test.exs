defmodule Rollbax.LoggerTest do
  use ExUnit.RollbaxCase

  require Logger

  setup_all do
    {:ok, pid} = start_rollbax_client("token1", "test")
    {:ok, _} = Logger.add_backend(Rollbax.Logger, flush: true)
    on_exit(fn ->
      Logger.remove_backend(Rollbax.Logger, flush: true)
      ensure_rollbax_client_down(pid)
    end)
  end

  setup do
    {:ok, _} = RollbarAPI.start(self())
    on_exit(&RollbarAPI.stop/0)
  end

  test "level filtering" do
    Logger.configure_backend(Rollbax.Logger, level: :error)
    capture_log(fn ->
      Logger.error(["test", ?\s, "pass"])
      Logger.info("miss")
    end)
    assert_receive {:api_request, body}
    assert body =~ "body\":\"test pass"
    refute_receive {:api_request, _body}
  end

  test "using rollbax: false for disabling reporting to Rollbar" do
    capture_log(fn -> Logger.error("miss", rollbax: false) end)
    refute_receive {:api_request, _body}
  end

  test "endpoint is down" do
    :ok = RollbarAPI.stop
    capture_log(fn -> Logger.error("miss") end)
    refute_receive {:api_request, _body}
  end

  test "reporting with metadata" do
    Logger.configure_backend(Rollbax.Logger, metadata: [:foo])
    capture_log(fn -> Logger.error("pass", foo: "bar") end)
    assert_receive {:api_request, body}
    assert body =~ ~s("body":"pass")
    assert body =~ ~s("foo":"bar")
  end

  test "logging a message that has invalid unicode codepoints" do
    capture_log(fn -> Logger.error(["invalid:", ?\s, 1_000_000_000]) end)
    assert_receive {:api_request, body}
    assert body =~ ~s("body":"invalid: �")
  end
end
