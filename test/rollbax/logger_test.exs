defmodule Rollbax.LoggerTest do
  use ExUnit.RollbaxCase

  alias Rollbax.Logger, as: L

  require Logger

  setup_all do
    {:ok, pid} = start_rollbax_client("token1", "test")
    {:ok, _} = Logger.add_backend(L, flush: true)
    on_exit(fn ->
      Logger.remove_backend(L, flush: true)
      ensure_rollbax_client_down(pid)
    end)
  end

  setup do
    {:ok, _} = RollbarAPI.start(self())
    on_exit(&RollbarAPI.stop/0)
  end

  test "notify level filtering" do
    Logger.configure_backend(L, level: :warn)
    capture_log(fn ->
      Logger.error(["test", ?\s, "pass"])
      Logger.info("miss")
    end)
    assert_receive {:api_request, body}
    assert body =~ "body\":\"test pass"
    refute_receive {:api_request, _body}
  end

  test "notifier skip" do
    Logger.metadata(rollbax: false)
    capture_log(fn -> Logger.error("miss") end)
    refute_receive {:api_request, _body}
  end

  test "endpoint is down" do
    :ok = RollbarAPI.stop
    capture_log(fn -> Logger.error("miss") end)
    refute_receive {:api_request, _body}
  end
end
