defmodule Rollbax.ClientViaProxyTest do
  use ExUnit.RollbaxCase

  alias Rollbax.Client

  setup_all do
    {:ok, pid} =
      Rollbax.Client.start_link(
        api_endpoint: "http://localhost:4004",
        access_token: "token1",
        environment: "test",
        enabled: true,
        custom: %{qux: "custom"},
        proxy: "http://localhost:14001"
      )

    on_exit(fn ->
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      end
    end)
  end

  defmodule Proxy do
    alias Plug.Conn
    alias Plug.Adapters.Cowboy

    import Conn

    def start(pid) do
      Cowboy.http(__MODULE__, [test: pid], port: 14001)
    end

    def stop() do
      :timer.sleep(100)
      Cowboy.shutdown(__MODULE__.HTTP)
      :timer.sleep(100)
    end

    def init(opts) do
      Keyword.fetch!(opts, :test)
    end

    def call(%Conn{method: "POST"} = conn, test) do
      {:ok, body, conn} = read_body(conn)
      :timer.sleep(30)
      json_body = Jason.decode!(body)
      send(test, {:api_request_via_proxy, Jason.encode!(Map.put(json_body, "proxied", "yes"))})

      if get_in(json_body, ["data", "custom", "return_error?"]) do
        send_resp(conn, 400, ~s({"err": 1, "message": "that was a bad request"}))
      else
        send_resp(conn, 200, "{}")
      end
    end

    def call(conn, _test) do
      send_resp(conn, 404, "Not Found")
    end
  end

  setup do
    {:ok, _} = RollbarAPI.start(self())
    on_exit(&RollbarAPI.stop/0)
    {:ok, _} = Proxy.start(self())
    on_exit(&Proxy.stop/0)
  end

  describe "with proxy" do
    test "Client don't try to contact the api server" do
      body = %{"message" => %{"body" => "pass"}}
      occurrence_data = %{"server" => %{"host" => "example.net"}}
      :ok = Client.emit(:warn, System.system_time(:second), body, _custom = %{}, occurrence_data)

      refute_received :api_request
      assert_receive {:api_request_via_proxy, body}
    end

    test "Client send message to proxy server" do
      body = %{"message" => %{"body" => "pass"}}
      occurrence_data = %{"server" => %{"host" => "example.net"}}
      :ok = Client.emit(:warn, System.system_time(:second), body, _custom = %{}, occurrence_data)

      assert_receive {:api_request_via_proxy, body}
      json_body = Jason.decode!(body)
      assert json_body["data"]["server"] == %{"host" => "example.net"}
      assert json_body["proxied"] == "yes"
    end
  end
end
