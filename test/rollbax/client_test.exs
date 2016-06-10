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

  test "emit/5" do
    :ok = Client.emit(:warn, unix_time(), %{"message" => %{"body" => "pass"}}, _custom = %{foo: "bar"}, %{})
    assert_receive {:api_request, body}
    assert body =~ ~s("access_token":"token1")
    assert body =~ ~s("environment":"test")
    assert body =~ ~s("level":"warn")
    assert body =~ ~s("body":"pass")
    assert body =~ ~s("foo":"bar")
  end

  test "mass sending" do
    for _ <- 1..60 do
      :ok = Client.emit(:error, unix_time(), %{"message" => %{"body" => "pass"}}, %{}, %{})
    end

    for _ <- 1..60 do
      assert_receive {:api_request, _body}
    end
  end

  test "endpoint is down" do
    :ok = RollbarAPI.stop
    log = capture_log(fn ->
      :ok = Client.emit(:error, unix_time(), %{"message" => %{"body" => "miss"}}, %{}, %{})
    end)
    assert log =~ "[error] (Rollbax) connection error: :econnrefused"
    refute_receive {:api_request, _body}
  end

  defp unix_time() do
    {mgsec, sec, _usec} = :os.timestamp()
    mgsec * 1_000_000 + sec
  end
end
