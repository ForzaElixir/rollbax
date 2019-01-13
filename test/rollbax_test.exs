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

  describe "report/5" do
    test "with an error" do
      stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
      exception = RuntimeError.exception("pass")
      :ok = Rollbax.report(:error, exception, stacktrace, %{}, %{uuid: "d4c7"})

      assert %{
               "data" => %{
                 "body" => %{"trace" => trace},
                 "environment" => "test",
                 "level" => "error",
                 "uuid" => "d4c7"
               }
             } = assert_performed_request()

      assert trace == %{
               "exception" => %{
                 "class" => "RuntimeError",
                 "message" => "pass"
               },
               "frames" => [
                 %{"filename" => "file.exs", "lineno" => 16, "method" => "Test.report/2"}
               ]
             }
    end

    test "with an error that is not an exception" do
      stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
      error = {:badmap, nil}
      :ok = Rollbax.report(:error, error, stacktrace, %{}, %{})

      assert %{"class" => "BadMapError", "message" => "expected a map, got: nil"} =
               assert_performed_request()["data"]["body"]["trace"]["exception"]
    end

    test "with an exit" do
      stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
      :ok = Rollbax.report(:exit, :oops, stacktrace)

      assert %{
               "data" => %{
                 "body" => %{"trace" => trace},
                 "level" => "error"
               }
             } = assert_performed_request()

      assert trace == %{
               "exception" => %{
                 "class" => "exit",
                 "message" => ":oops"
               },
               "frames" => [
                 %{"filename" => "file.exs", "lineno" => 16, "method" => "Test.report/2"}
               ]
             }
    end

    test "with an exit where the term is an exception" do
      stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]

      exception =
        try do
          raise "oops"
        rescue
          exception -> exception
        end

      :ok = Rollbax.report(:exit, exception, stacktrace, %{}, %{})

      assert %{"class" => "exit", "message" => "** (RuntimeError) oops"} =
               assert_performed_request()["data"]["body"]["trace"]["exception"]
    end

    test "with a throw" do
      stacktrace = [{Test, :report, 2, [file: 'file.exs', line: 16]}]
      :ok = Rollbax.report(:throw, :oops, stacktrace)

      assert %{
               "data" => %{
                 "body" => %{"trace" => trace},
                 "level" => "error"
               }
             } = assert_performed_request()

      assert trace == %{
               "exception" => %{
                 "class" => "throw",
                 "message" => ":oops"
               },
               "frames" => [
                 %{"filename" => "file.exs", "lineno" => 16, "method" => "Test.report/2"}
               ]
             }
    end

    test "includes stacktraces in the function name if there's an application" do
      # Let's use some modules that belong to an application and some that don't.
      stacktrace = [
        {:crypto, :strong_rand_bytes, 1, [file: 'crypto.erl', line: 1]},
        {List, :to_string, 1, [file: 'list.ex', line: 10]},
        {NoApp, :for_this_module, 3, [file: 'nofile.ex', line: 1]}
      ]

      :ok = Rollbax.report(:throw, :oops, stacktrace)

      assert [
               %{"method" => ":crypto.strong_rand_bytes/1 (crypto)"},
               %{"method" => "List.to_string/1 (elixir)"},
               %{"method" => "NoApp.for_this_module/3"}
             ] = assert_performed_request()["data"]["body"]["trace"]["frames"]
    end
  end

  test "report_message/4" do
    :ok = Rollbax.report_message(:critical, "Everything is on fire!")

    assert %{
             "data" => %{
               "level" => "critical",
               "body" => %{"message" => %{"body" => "Everything is on fire!"}}
             }
           } = assert_performed_request()
  end

  describe "start/2" do
    setup do
      on_exit(fn ->
        Application.delete_env(:rollbax, :enabled)
      end)
    end

    test "when :enabled config value is invalid, it raises" do
      Application.put_env(:rollbax, :enabled, "invalid_enabled_config_value")

      assert_raise ArgumentError, ":enabled may be only true, false, or :log", fn ->
        Rollbax.start(nil, nil)
      end
    end

    test "when :enabled config value is true but :access_token is nil, it raises" do
      Application.put_env(:rollbax, :enabled, true)
      Application.delete_env(:rollbax, :access_token)

      assert_raise ArgumentError, ":access_token is required when :enabled is true", fn ->
        Rollbax.start(nil, nil)
      end
    end
  end
end
