defmodule Rollbax.ClientTest do
  use ExUnit.RollbaxCase

  alias Rollbax.Client

  setup_all do
    {:ok, pid} = start_rollbax_client("token1", "test")
    on_exit(fn ->
      ensure_rollbax_client_down(pid)
    end)
  end

  setup do
    {:ok, _} = RollbarAPI.start(self())
    on_exit(&RollbarAPI.stop/0)
  end

  test "post payload" do
    :ok = Client.emit(:warn, "pass", %{meta: "OK"})
    assert_receive {:api_request, body}
    assert body =~ "access_token\":\"token1"
    assert body =~ "environment\":\"test"
    assert body =~ "level\":\"warn"
    assert body =~ "body\":\"pass"
    assert body =~ "meta\":\"OK"
  end

  test "mass sending" do
    for _ <- 1..60 do
      :ok = Client.emit(:error, "pass", %{})
    end

    for _ <- 1..60 do
      assert_receive {:api_request, _body}
    end
  end

  test "endpoint is down" do
    :ok = RollbarAPI.stop
    log = capture_log(fn ->
      :ok = Client.emit(:error, "miss", %{})
    end)
    assert log =~ "[error] (Rollbax) connection error:"
    refute_receive {:api_request, _body}
  end
end
