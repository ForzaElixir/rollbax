defmodule Rollbax.ClientTest do
  use ExUnit.RollbaxCase

  alias Rollbax.Client

  setup_all do
    {:ok, pid} = start_rollbax_client("token1", "test", %{qux: "custom"})

    on_exit(fn ->
      ensure_rollbax_client_down(pid)
    end)
  end

  setup do
    {:ok, _} = RollbarAPI.start(self())
    on_exit(&RollbarAPI.stop/0)
  end

  describe "emit/5" do
    test "fills in the right data" do
      body = %{"message" => %{"body" => "pass"}}
      custom = %{foo: "bar"}
      :ok = Client.emit(:warn, System.system_time(:second), body, custom, %{})

      assert %{
               "access_token" => "token1",
               "data" => %{
                 "environment" => "test",
                 "level" => "warn",
                 "body" => %{"message" => %{"body" => "pass"}},
                 "custom" => %{"foo" => "bar", "qux" => "custom"}
               }
             } = assert_performed_request()
    end

    test "gives precedence to custom values over global ones" do
      body = %{"message" => %{"body" => "pass"}}
      custom = %{qux: "overridden", quux: "another"}
      :ok = Client.emit(:warn, System.system_time(:second), body, custom, %{})

      assert assert_performed_request()["data"]["custom"] ==
               %{"qux" => "overridden", "quux" => "another"}
    end

    test "gives precedence to user occurrence data over data from Rollbax" do
      body = %{"message" => %{"body" => "pass"}}
      occurrence_data = %{"server" => %{"host" => "example.net"}}
      :ok = Client.emit(:warn, System.system_time(:second), body, _custom = %{}, occurrence_data)

      assert assert_performed_request()["data"]["server"] == %{"host" => "example.net"}
    end
  end

  test "mass sending" do
    body = %{"message" => %{"body" => "pass"}}

    Enum.each(1..60, fn _ ->
      :ok = Client.emit(:error, System.system_time(:second), body, %{}, %{})
    end)

    Enum.each(1..60, fn _ ->
      assert_performed_request()
    end)
  end

  test "endpoint is down" do
    :ok = RollbarAPI.stop()

    log =
      capture_log(fn ->
        payload = %{"message" => %{"body" => "miss"}}
        :ok = Client.emit(:error, System.system_time(:second), payload, %{}, %{})
      end)

    assert log =~ "[error] (Rollbax) connection error: :econnrefused"
    refute_receive {:api_request, _body}
  end

  test "rate limiting" do
    body = %{"message" => %{"body" => "pass"}}

    log =
      capture_log(fn ->
        :ok =
          Client.emit(:error, System.system_time(:second), body, %{rate_limit_seconds: "1"}, %{})
      end)

    assert log =~ "unexpected API status: 429/Too Many Requests"

    assert_performed_request()

    Process.sleep(100)

    log =
      capture_log(fn ->
        :ok = Client.emit(:error, System.system_time(:second), body, %{}, %{})
      end)

    assert log =~ "ignored report due to rate limiting"

    refute_receive {:api_request, _body}

    Process.sleep(1000)

    :ok = Client.emit(:error, System.system_time(:second), body, %{}, %{})
    assert_performed_request()
  end

  test "errors from the API are logged" do
    log =
      capture_log(fn ->
        :ok = Client.emit(:error, System.system_time(:second), %{}, %{return_error?: true}, %{})
        assert_performed_request()
      end)

    assert log =~ ~s{[error] (Rollbax) unexpected API status: 400}
    assert log =~ ~s{[error] (Rollbax) API returned an error: "that was a bad request"}
  end

  test "invalid item failure" do
    log =
      capture_log(fn ->
        payload = %{"message" => %{"body" => <<208>>}}
        :ok = Client.emit(:error, System.system_time(:second), payload, %{}, %{})
        refute_receive {:api_request, _body}
      end)

    assert log =~ "[error] (Rollbax) failed to encode report below for reason: invalid byte 0xD0"

    assert log =~ ~r"""
           %{"message" => %{"body" => <<208>>}}
           Level: error
           Timestamp: \d+
           Custom data: %{}
           Occurrence data: %{}
           """
  end
end
