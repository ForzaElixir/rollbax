defmodule RollbaxTest do
  use ExUnit.RollbaxCase

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

  test "report/3 with an error" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    exception = RuntimeError.exception("pass")
    :ok = Rollbax.report(:error, exception, stacktrace, %{}, %{uuid: "d4c7"})
    assert_receive {:api_request, body}
    assert {:ok, decoded} = Poison.decode body
    assert %{
      "access_token" => "token1",
      "data" => %{
        "body" => %{
          "trace" => %{
            "exception" => %{
              "class" => "RuntimeError",
              "message" => "pass"
            },
            "frames" => [%{
              "filename" => "file.exs",
              "lineno" => 16,
              "method" => "Test.report/2"
            }]}},
      "level" => "error",
      "uuid" => "d4c7"
    }} = decoded
    refute match? %{"data" => %{"body" => %{"custom" => _}}}, decoded
  end

  test "report/3 with an error that is not an exception" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    error = {:badmap, nil}
    :ok = Rollbax.report(:error, error, stacktrace, %{}, %{})
    assert_receive {:api_request, body}
    assert body =~ ~s("class":"BadMapError")
    assert body =~ ~s("message":"expected a map, got: nil")
  end

  test "report/3 with an exit" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    :ok = Rollbax.report(:exit, :oops, stacktrace)
    assert_receive {:api_request, body}
    assert {:ok, decoded} = Poison.decode body
    assert %{
      "access_token" => "token1",
      "data" => %{
        "body" => %{
          "trace" => %{
            "exception" => %{
              "class" => "exit",
              "message" => ":oops"
            },
            "frames" => [%{
              "filename" => "file.exs",
              "lineno" => 16,
              "method" => "Test.report/2"
            }]}},
      "level" => "error"
    }} = decoded
    refute match? %{"data" => %{"body" => %{"custom" => _}}}, decoded
  end

  test "report/3 with an exit where the term is an exception" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    exception =
      try do
        raise "oops"
      rescue
        exception -> exception
      end

    :ok = Rollbax.report(:exit, exception, stacktrace, %{}, %{})

    assert_receive {:api_request, body}
    assert body =~ ~s["class":"exit"]
    assert body =~ ~s["message":"** (RuntimeError) oops"]
  end

  test "report/3 with a throw" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    :ok = Rollbax.report(:throw, :oops, stacktrace)
    assert_receive {:api_request, body}
    assert {:ok, decoded} = Poison.decode body
    assert %{
      "access_token" => "token1",
      "data" => %{
        "body" => %{
          "trace" => %{
            "exception" => %{
              "class" => "throw",
              "message" => ":oops"
            },
            "frames" => [%{
              "filename" => "file.exs",
              "lineno" => 16,
              "method" => "Test.report/2"
            }]}},
      "level" => "error"
    }} = decoded
    refute match? %{"data" => %{"body" => %{"custom" => _}}}, decoded
  end

  test "report/3 includes stacktraces in the function name if there's an application" do
    # Let's use some modules that belong to an application and some that don't.
    stacktrace = [
      {:crypto, :strong_rand_bytes, 1, [file: 'crypto.erl', line: 1]},
      {List, :to_string, 1, [file: 'list.ex', line: 10]},
      {NoApp, :for_this_module, 3, [file: 'nofile.ex', line: 1]},
    ]

    :ok = Rollbax.report(:throw, :oops, stacktrace)

    assert_receive {:api_request, body}

    assert body =~ ~s["method":":crypto.strong_rand_bytes/1 (crypto)"]
    assert body =~ ~s["method":"List.to_string/1 (elixir)"]
    assert body =~ ~s["method":"NoApp.for_this_module/3"]
  end
end
