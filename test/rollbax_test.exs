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
    assert body =~ ~s("level":"error")
    assert body =~ ~s("class":"RuntimeError")
    assert body =~ ~s("message":"pass")
    assert body =~ ~s("filename":"file.exs")
    assert body =~ ~s("lineno":16)
    assert body =~ ~s("method":"Test.report/2")
    assert body =~ ~s("uuid":"d4c7")
    refute body =~ ~s("custom")
  end

  test "report/3 with an error that is not an exception" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    error = {:badmap, nil}
    :ok = Rollbax.report(:error, error, stacktrace, %{}, %{})
    assert_receive {:api_request, body}
    assert body =~ ~s("class":"BadMapError")
    assert body =~ ~s("message":"expected a map, got: nil")
  end

  test "report/3 with an error that is a message" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    error = "Something was wrong"
    :ok = Rollbax.report(:error, error, stacktrace, %{}, %{})
    assert_receive {:api_request, body}
    assert body =~ ~s("level":"error")
    assert body =~ ~s("message":"Something was wrong")
  end

  test "report/3 with an debug that is a message" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    message = "Settings saved"
    :ok = Rollbax.report(:debug, message, stacktrace, %{}, %{})
    assert_receive {:api_request, body}
    assert body =~ ~s("level":"debug")
    assert body =~ ~s("message":"Settings saved")
  end

  test "report/3 with an info that is a message" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    message = "Login successful"
    :ok = Rollbax.report(:info, message, stacktrace, %{}, %{})
    assert_receive {:api_request, body}
    assert body =~ ~s("level":"info")
    assert body =~ ~s("message":"Login successful")
  end

  test "report/3 with an warning that is a message" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    message = "Unexpected input"
    :ok = Rollbax.report(:warning, message, stacktrace, %{}, %{})
    assert_receive {:api_request, body}
    assert body =~ ~s("level":"warning")
    assert body =~ ~s("message":"Unexpected input")
  end

  test "report/3 with an critical that is a message" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    error = "Something is broken"
    :ok = Rollbax.report(:critical, error, stacktrace, %{}, %{})
    assert_receive {:api_request, body}
    assert body =~ ~s("level":"critical")
    assert body =~ ~s("message":"Something is broken")
  end

  test "report/3 with an exit" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    :ok = Rollbax.report(:exit, :oops, stacktrace)
    assert_receive {:api_request, body}
    assert body =~ ~s("level":"error")
    assert body =~ ~s("class":"exit")
    assert body =~ ~s("message":":oops")
    assert body =~ ~s("filename":"file.exs")
    assert body =~ ~s("lineno":16)
    assert body =~ ~s("method":"Test.report/2")
    refute body =~ ~s("custom")
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
    assert body =~ ~s("level":"error")
    assert body =~ ~s("class":"throw")
    assert body =~ ~s("message":":oops")
    assert body =~ ~s("filename":"file.exs")
    assert body =~ ~s("lineno":16)
    assert body =~ ~s("method":"Test.report/2")
    refute body =~ ~s("custom")
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
