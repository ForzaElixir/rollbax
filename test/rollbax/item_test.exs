defmodule Rollbax.ClientTest do
  use ExUnit.RollbaxCase
  alias Rollbax.Item

  @access_token "123"
  @message "test"
  @stacktrace [{Test, :report, 2, [file: 'file.exs', line: 16]}]
  @timestamp :os.timestamp()

  test "compose with stacktrace" do
    r = Item.compose(Item.draft(@access_token, Mix.env), {
      :error, RuntimeError.exception(@message), @stacktrace, @timestamp, %{ "metakey" => "metaval" }
    })

    assert r["access_token"] == @access_token
    assert r["data"]["environment"] == Mix.env
    assert r["data"]["level"] == :error
    assert r["data"]["timestamp"] == @timestamp
    assert String.contains?(r["data"]["platform"], "Erlang")
    assert String.contains?(r["data"]["language"], "Elixir")
    {:ok, host} = :inet.gethostname
    assert r["data"]["server"]["host"] == to_string(host)

    trace = r["data"]["body"]["trace"]
    assert trace["exception"]["class"] == "Elixir.RuntimeError"
    assert trace["exception"]["message"] == @message
    frame = hd(trace["frames"])
    assert frame["filename"] == 'file.exs'
    assert frame["lineno"] == 16
    refute r["data"]["body"]["trace_chain"]
    refute r["data"]["body"]["message"]
    refute r["data"]["body"]["crash_report"]
  end

  test "compose without stacktrace" do
    r = Item.compose(Item.draft(@access_token, Mix.env), {
      :error, RuntimeError.exception(@message), nil, @timestamp, %{ "metakey" => "metaval" }
    })

    assert r["access_token"] == @access_token
    assert r["data"]["environment"] == Mix.env
    assert r["data"]["level"] == :error
    assert r["data"]["timestamp"] == @timestamp
    assert String.contains?(r["data"]["platform"], "Erlang")
    assert String.contains?(r["data"]["language"], "Elixir")
    {:ok, host} = :inet.gethostname
    assert r["data"]["server"]["host"] == to_string(host)

    refute r["data"]["body"]["trace"]
    refute r["data"]["body"]["trace_chain"]
    assert r["data"]["body"]["message"]["body"] == "** (RuntimeError) " <> @message
  end
end