defmodule Rollbax.ClientTest do
  use ExUnit.RollbaxCase

  alias Rollbax.Client

  setup_all do
    {:ok, _} = start_rollbax_client("token1", "test")
    :ok
  end

  setup do
    {:ok, _} = RollbarAPI.start(self())
    on_exit(fn -> RollbarAPI.stop() end)
  end

  test "post payload" do
    :ok = Client.emit(:error, "pass", %{meta: "OK", person: %{id: 123}})
    assert_receive {:api_request, body}
    decoded_body = Poison.decode!(body)
    assert decoded_body["access_token"] == "token1"
    assert decoded_body["data"]["environment"] == "test"
    assert decoded_body["data"]["level"] == "error"
    assert decoded_body["data"]["body"] == %{"message" => %{"body" => "pass"}}
    assert decoded_body["data"]["meta"] == "OK"
    assert decoded_body["data"]["person"] == %{"id" => 123}
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
    :ok = RollbarAPI.stop()
    log = capture_log(fn ->
      :ok = Client.emit(:error, "miss", %{})
    end)
    assert log =~ "[error] (Rollbax) connection error:"
    refute_receive {:api_request, _body}
  end
end
