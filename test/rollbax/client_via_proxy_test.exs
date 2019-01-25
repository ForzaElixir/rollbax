defmodule Rollbax.ClientViaProxyTest do
  use ExUnit.RollbaxCase

  alias Rollbax.Client

  setup_all do
    {:ok, pid} =
      start_rollbax_client(
        "token1",
        "test",
        %{proxied: "yes"},
        "http://localhost:5005",
        "http://localhost:7004"
      )

    on_exit(fn ->
      ensure_rollbax_client_down(pid)
    end)
  end

  setup do
    {:ok, _} = RollbarAPI.start(self(), 7004)
    on_exit(&RollbarAPI.stop/0)
  end

  describe "with proxy" do
    test "client send message to proxy server" do
      body = %{"message" => %{"body" => "pass"}}
      occurrence_data = %{"server" => %{"host" => "example.net"}}
      :ok = Client.emit(:warn, System.system_time(:second), body, _custom = %{}, occurrence_data)

      assert_receive {:api_request, body}
      json_body = Jason.decode!(body)
      assert json_body["data"]["server"] == %{"host" => "example.net"}
      assert json_body["data"]["custom"] == %{"proxied" => "yes"}
    end
  end
end
