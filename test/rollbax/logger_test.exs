defmodule Rollbax.LoggerTest do
  use ExUnit.RollbaxCase

  setup_all do
    {:ok, pid} = start_rollbax_client("token1", "test")

    on_exit(fn ->
      ensure_rollbax_client_down(pid)
    end)
  end

  setup context do
    {:ok, _pid} = RollbarAPI.start(self())

    if reporters = context[:reporters] do
      Application.put_env(:rollbax, :reporters, reporters)
    else
      Application.delete_env(:rollbax, :reporters)
    end

    :error_logger.add_report_handler(Rollbax.Logger)

    on_exit(fn ->
      RollbarAPI.stop()
      :error_logger.delete_report_handler(Rollbax.Logger)
    end)
  end

  test "GenServer terminating with an Elixir error" do
    defmodule Elixir.MyGenServer do
      use GenServer

      def init(args), do: {:ok, args}

      def handle_cast(:raise_elixir, _state) do
        Map.fetch!(Map.new(), :nonexistent_key)
      end
    end

    {:ok, gen_server} = GenServer.start(MyGenServer, {})

    capture_log(fn ->
      GenServer.cast(gen_server, :raise_elixir)
    end)

    data = assert_performed_request()["data"]

    # Check the exception.
    assert data["body"]["trace"]["exception"] == %{
             "class" => "GenServer terminating (KeyError)",
             "message" => "key :nonexistent_key not found in: %{}"
           }

    assert [frame] = find_frames_for_current_file(data["body"]["trace"]["frames"])
    assert frame["method"] == "MyGenServer.handle_cast/2"

    assert data["custom"]["last_message"] =~ "$gen_cast"
    assert data["custom"]["name"] == inspect(gen_server)
    assert data["custom"]["state"] == "{}"
  after
    purge_module(MyGenServer)
  end

  test "GenServer terminating with an Erlang error" do
    defmodule Elixir.MyGenServer do
      use GenServer

      def init(args), do: {:ok, args}

      def handle_cast(:raise_erlang, state) do
        :maps.find(:a_key, [:not_a, %{}])
        {:noreply, state}
      end
    end

    {:ok, gen_server} = GenServer.start(MyGenServer, {})

    capture_log(fn ->
      GenServer.cast(gen_server, :raise_erlang)
    end)

    data = assert_performed_request()["data"]

    assert data["body"]["trace"]["exception"] == %{
             "class" => "GenServer terminating (BadMapError)",
             "message" => "expected a map, got: [:not_a, %{}]"
           }

    assert [frame] = find_frames_for_current_file(data["body"]["trace"]["frames"])
    assert frame["method"] == "MyGenServer.handle_cast/2"

    assert data["custom"]["last_message"] =~ "$gen_cast"
    assert data["custom"]["name"] == inspect(gen_server)
    assert data["custom"]["state"] == "{}"
  after
    purge_module(MyGenServer)
  end

  test "GenServer terminating because of an exit" do
    defmodule Elixir.MyGenServer do
      use GenServer

      def init(args), do: {:ok, args}

      def handle_cast(:call_self, state) do
        GenServer.call(self(), {:call, :self})
        {:noreply, state}
      end
    end

    {:ok, gen_server} = GenServer.start(MyGenServer, {})

    capture_log(fn ->
      GenServer.cast(gen_server, :call_self)
    end)

    data = assert_performed_request()["data"]

    exception = data["body"]["trace"]["exception"]
    assert exception["class"] == "GenServer terminating"
    assert exception["message"] =~ "exited in: GenServer.call(#{inspect(gen_server)}"
    assert exception["message"] =~ "process attempted to call itself"

    assert [frame] = find_frames_for_current_file(data["body"]["trace"]["frames"])
    assert frame["method"] == "MyGenServer.handle_cast/2"

    assert data["custom"]["last_message"] =~ "$gen_cast"
    assert data["custom"]["name"] == inspect(gen_server)
    assert data["custom"]["state"] == "{}"
  after
    purge_module(MyGenServer)
  end

  test "GenServer stopping" do
    defmodule Elixir.MyGenServer do
      use GenServer

      def init(args), do: {:ok, args}

      def handle_cast(:stop, state) do
        {:stop, :stop_reason, state}
      end
    end

    {:ok, gen_server} = GenServer.start(MyGenServer, {})

    capture_log(fn ->
      GenServer.cast(gen_server, :stop)
    end)

    data = assert_performed_request()["data"]

    # Check the exception.
    assert data["body"]["trace"]["exception"] == %{
             "class" => "GenServer terminating (stop)",
             "message" => ":stop_reason"
           }

    assert data["body"]["trace"]["frames"] == []

    assert data["custom"]["last_message"] =~ "$gen_cast"
    assert data["custom"]["name"] == inspect(gen_server)
    assert data["custom"]["state"] == "{}"
  after
    purge_module(MyGenServer)
  end

  test "gen_event terminating" do
    defmodule Elixir.MyGenEventHandler do
      @behaviour :gen_event

      def init(state), do: {:ok, state}
      def terminate(_reason, _state), do: :ok
      def code_change(_old_vsn, state, _extra), do: {:ok, state}
      def handle_call(_request, state), do: {:ok, :ok, state}
      def handle_info(_message, state), do: {:ok, state}

      def handle_event(:raise_error, state) do
        raise "oops"
        {:ok, state}
      end
    end

    {:ok, manager} = :gen_event.start()
    :ok = :gen_event.add_handler(manager, MyGenEventHandler, {})

    capture_log(fn ->
      :gen_event.notify(manager, :raise_error)

      data = assert_performed_request()["data"]

      # Check the exception.
      assert data["body"]["trace"]["exception"] == %{
               "class" => "gen_event handler terminating (RuntimeError)",
               "message" => "oops"
             }

      assert [frame] = find_frames_for_current_file(data["body"]["trace"]["frames"])
      assert frame["method"] == "MyGenEventHandler.handle_event/2"

      assert data["custom"] == %{
               "name" => "MyGenEventHandler",
               "manager" => inspect(manager),
               "last_message" => ":raise_error",
               "state" => "{}"
             }
    end)
  after
    purge_module(MyGenEventHandler)
  end

  test "process raising an error" do
    capture_log(fn ->
      pid = spawn(fn -> raise "oops" end)

      data = assert_performed_request()["data"]

      assert data["body"]["trace"]["exception"] == %{
               "class" => "error in process (RuntimeError)",
               "message" => "oops"
             }

      assert [frame] = find_frames_for_current_file(data["body"]["trace"]["frames"])

      assert frame["method"] =~
               ~r[anonymous fn/0 in Rollbax.LoggerTest.(\")?test process raising an error(\")?/1]

      assert data["custom"] == %{"pid" => inspect(pid)}
    end)
  end

  test "task with anonymous function raising an error" do
    capture_log(fn ->
      {:ok, task} = Task.start(fn -> raise "oops" end)

      data = assert_performed_request()["data"]

      assert data["body"]["trace"]["exception"] == %{
               "class" => "Task terminating (RuntimeError)",
               "message" => "oops"
             }

      assert [frame] = find_frames_for_current_file(data["body"]["trace"]["frames"])

      assert frame["method"] =~
               ~r[anonymous fn/0 in Rollbax.LoggerTest.(\")?test task with anonymous function raising an error(\")?/1]

      assert data["custom"]["name"] == inspect(task)
      assert data["custom"]["function"] =~ ~r/\A#Function<.* in Rollbax\.LoggerTest/
      assert data["custom"]["arguments"] == "[]"
    end)
  end

  test "task with mfa raising an error" do
    defmodule Elixir.MyModule do
      def raise_error(message), do: raise(message)
    end

    capture_log(fn ->
      {:ok, task} = Task.start(MyModule, :raise_error, ["my message"])

      data = assert_performed_request()["data"]

      assert data["body"]["trace"]["exception"] == %{
               "class" => "Task terminating (RuntimeError)",
               "message" => "my message"
             }

      assert [frame] = find_frames_for_current_file(data["body"]["trace"]["frames"])
      assert frame["method"] == "MyModule.raise_error/1"

      assert data["custom"] == %{
               "name" => inspect(task),
               "function" => "&MyModule.raise_error/1",
               "arguments" => ~s(["my message"]),
               "started_from" => inspect(self())
             }
    end)
  after
    purge_module(MyModule)
  end

  if List.to_integer(:erlang.system_info(:otp_release)) < 19 do
    test "gen_fsm terminating" do
      defmodule Elixir.MyGenFsm do
        @behaviour :gen_fsm
        def init(data), do: {:ok, :idle, data}
        def terminate(_reason, _state, _data), do: :ok
        def code_change(_vsn, state, data, _extra), do: {:ok, state, data}
        def handle_event(_event, state, data), do: {:next_state, state, data}
        def handle_sync_event(_event, _from, state, data), do: {:next_state, state, data}
        def handle_info(_message, state, data), do: {:next_state, state, data}

        def idle(:error, state) do
          :maps.find(:a_key, _not_a_map = [])
          {:next_state, :idle, state}
        end
      end

      capture_log(fn ->
        {:ok, gen_fsm} = :gen_fsm.start(MyGenFsm, {}, _opts = [])

        :gen_fsm.send_event(gen_fsm, :error)

        data = assert_performed_request()["data"]

        # Check the exception.
        assert data["body"]["trace"]["exception"] == %{
                 "class" => "State machine terminating (BadMapError)",
                 "message" => "expected a map, got: []"
               }

        assert [frame] = find_frames_for_current_file(data["body"]["trace"]["frames"])
        assert frame["method"] == "MyGenFsm.idle/2"

        assert data["custom"] == %{
                 "last_event" => ":error",
                 "name" => inspect(gen_fsm),
                 "state" => ":idle",
                 "data" => "{}"
               }
      end)
    after
      purge_module(MyGenFsm)
    end
  end

  test "when the endpoint is down, no logs are reported" do
    :ok = RollbarAPI.stop()

    capture_log(fn ->
      spawn(fn -> raise "oops" end)
      refute_receive {:api_request, _body}
    end)
  end

  @tag reporters: [Rollbax.Reporter.Silencing]
  test "reporters can skip events" do
    capture_log(fn ->
      spawn(fn -> raise "oops" end)
      refute_receive {:api_request, _body}
    end)
  end

  defp find_frames_for_current_file(frames) do
    current_file = Path.relative_to_cwd(__ENV__.file)
    Enum.filter(frames, &(&1["filename"] == current_file))
  end

  defp purge_module(module) do
    :code.delete(module)
    :code.purge(module)
  end
end
