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
end
