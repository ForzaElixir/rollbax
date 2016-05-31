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

  test "exception report" do
    stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
    exception = RuntimeError.exception("pass")
    :ok = Rollbax.report(:error, exception, stacktrace, %{}, %{uuid: "d4c7"})
    assert_receive {:api_request, body}
    assert body =~ "level\":\"error"
    assert body =~ "class\":\"RuntimeError\""
    assert body =~ "message\":\"pass\""
    assert body =~ "filename\":\"file.exs\""
    assert body =~ "lineno\":16"
    assert body =~ "method\":\"Test.report/2\""
    assert body =~ "uuid\":\"d4c7"
    refute body =~ "custom"
  end
end
