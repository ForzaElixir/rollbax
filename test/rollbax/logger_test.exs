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
    assert %{
      "data" => %{
        "body" => %{
          "message" => %{
            "body" => "test pass"
          }
        }
      }
    } = Poison.decode!(body)
    refute_receive {:api_request, _body}
  end

  test "using rollbax: false for disabling reporting to Rollbar" do
    capture_log(fn -> Logger.error("miss", rollbax: false) end)
    refute_receive {:api_request, _body}
  end

  test ":blacklist option" do
    Logger.configure_backend(Rollbax.Logger, blacklist: ["someone", ~r/\d{4}/])

    capture_log(fn ->
      Logger.error("my message")
      Logger.error("someone else's message")
      Logger.error("numbers are banned: 1234")
    end)

    assert_receive {:api_request, body}
    assert %{
      "data" => %{
        "body" => %{
          "message" => %{
            "body" => "my message"
          }
        }
      }
    } = Poison.decode!(body)

    refute_receive {:api_request, _body}
  after
    Logger.configure_backend(Rollbax.Logger, blacklist: [])
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
    assert %{
      "data" => %{
        "body" => %{
          "message" => %{
            "body" => "pass",
            "foo" => "bar"
          }
        }
      }
    } = Poison.decode!(body)
  end

  if Version.compare(System.version, "1.3.0-rc.1") != :lt do
    test "logging a message that has invalid unicode codepoints" do
      capture_log(fn -> Logger.error(["invalid:", ?\s, 1_000_000_000]) end)
      assert_receive {:api_request, body}
      assert body =~ ~s("body":"invalid: �")
      assert %{
        "data" => %{
          "body" => %{
            "message" => %{
              "body" => "invalid: �"
            }
          }
        }
      } = Poison.decode!(body)
    end
  end
end
