defmodule Rollbax.DefaultReporter do
  @behaviour Rollbax.Reporter

  require Logger

  def handle_event(:error, {_pid, format, data}) do
    handle_error_format(format, data)
  end

  def handle_event(_type, _event) do
    :dont_report
  end

  # Errors in a GenServer.
  defp handle_error_format('** Generic server ' ++ _, [name, last_message, state, reason]) do
    {class, message, stacktrace} = format_as_exception(reason, "GenServer terminating")

    %Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: %{
        "name" => inspect(name),
        "last_message" => inspect(last_message),
        "state" => inspect(state),
      },
    }
  end

  # Errors in a GenEvent handler.
  defp handle_error_format('** gen_event handler ' ++ _, [name, manager, last_message, state, reason]) do
    {class, message, stacktrace} = format_as_exception(reason, "gen_event handler terminating")

    %Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: %{
        "name" => inspect(name),
        "manager" => inspect(manager),
        "last_message" => inspect(last_message),
        "state" => inspect(state),
      },
    }
  end

  # Errors in a task.
  defp handle_error_format('** Task ' ++ _, [name, starter, function, arguments, reason]) do
    {class, message, stacktrace} = format_as_exception(reason, "Task terminating")

    %Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: %{
        "name" => inspect(name),
        "started_from" => inspect(starter),
        "function" => inspect(function),
        "arguments" => inspect(arguments),
      },
    }
  end

  # Errors in gen_fsm/gen_statem.
  defp handle_error_format('** State machine ' ++ _ = message, data) do
    if charlist_contains?(message, 'Callback mode') do
      handle_gen_statem_error(message, data)
    else
      handle_gen_fsm_error(data)
    end
  end

  # Errors in a regular process.
  defp handle_error_format('Error in process ' ++ _, [pid, {reason, stacktrace}]) do
    exception = Exception.normalize(:error, reason)

    %Rollbax.Exception{
      class: "error in process (#{inspect(exception.__struct__)})",
      message: Exception.message(exception),
      stacktrace: stacktrace,
      custom: %{
        "pid" => inspect(pid),
      },
    }
  end

  # Any other error (for example, the ones logged through
  # :error_logger.error_msg/1). This reporter doesn't report those to Rollbar.
  defp handle_error_format(_format, _data) do
    :dont_report
  end

  defp handle_gen_statem_error(message, [_name | data] = whole_data) do
    data =
      if charlist_contains?(message, 'Last event') do
        tl(data)
      else
        data
      end

    [_server_state, reason_kind, reason | _rest] = data

    {exc_class, exc_message} =
      case {reason_kind, reason} do
        {:error, reason} ->
          exception = Exception.normalize(:error, reason)
          {"State machine terminating (" <> inspect(exception.__struct__) <> ")", Exception.message(exception)}
        {:exit, reason} ->
          {"State machine terminating (exit)", Exception.format_exit(reason)}
      end

    stacktrace =
      if charlist_contains?(message, 'Stacktrace') do
        List.last(data)
      else
        []
      end

    %Rollbax.Exception{
      class: exc_class,
      message: exc_message,
      stacktrace: stacktrace,
      custom: gen_statem_custom(message, whole_data, %{}),
    }
  end

  defp gen_statem_custom('** State machine ~p terminating~n' ++ rest, [name | data], custom) do
    gen_statem_custom(rest, data, Map.put(custom, "name", inspect(name)))
  end

  defp gen_statem_custom('** Last event = ~p~n' ++ rest, [last_event | data], custom) do
    gen_statem_custom(rest, data, Map.put(custom, "last_event", inspect(last_event)))
  end

  defp gen_statem_custom('** When server state  = ~p~n' ++ rest, [server_state | data], custom) do
    gen_statem_custom(rest, data, Map.put(custom, "server_state", inspect(server_state)))
  end

  # We ignore this as it's reported in the error.
  defp gen_statem_custom('** Reason for termination = ~w:~p~n' ++ rest, [_reason_kind, _reason | data], custom) do
    gen_statem_custom(rest, data, custom)
  end

  defp gen_statem_custom('** Callback mode = ~p~n' ++ rest, [callback_mode | data], custom) do
    gen_statem_custom(rest, data, Map.put(custom, "callback_mode", inspect(callback_mode)))
  end

  defp gen_statem_custom('** Queued = ~p~n' ++ rest, [queued_messages | data], custom) do
    gen_statem_custom(rest, data, Map.put(custom, "queued_messages", inspect(queued_messages)))
  end

  defp gen_statem_custom('** Postponed = ~p~n' ++ rest, [postponed_messages | data], custom) do
    gen_statem_custom(rest, data, Map.put(custom, "postponed_messages", inspect(postponed_messages)))
  end

  defp gen_statem_custom(_other, _data, custom) do
    custom
  end

  defp handle_gen_fsm_error([name, last_event, state, data, reason]) do
    {class, message, stacktrace} = format_as_exception(reason, "State machine terminating")

    %Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: %{
        "name" => inspect(name),
        "last_event" => inspect(last_event),
        "state" => inspect(state),
        "data" => inspect(data),
      },
    }
  end

  defp handle_gen_fsm_error(data) do
    Logger.warn "Couldn't parse gen_fsm crash data: #{inspect(data)}"
    :dont_report
  end

  defp format_as_exception({maybe_exception, [_ | _] = maybe_stacktrace} = reason, class) do
    # We do this &Exception.format_stacktrace_entry/1 dance just to ensure that
    # "maybe_stacktrace" is a valid stacktrace. If it's not,
    # Exception.format_stacktrace_entry/1 will raise an error and we'll treat it
    # as not a stacktrace.
    try do
      Enum.each(maybe_stacktrace, &Exception.format_stacktrace_entry/1)
    catch
      :error, _ ->
        format_stop_as_exception(reason, class)
        {class, _message = inspect(reason), _stacktrace = []}
    else
      :ok ->
        format_error_as_exception(maybe_exception, maybe_stacktrace, class)
    end
  end

  defp format_as_exception(reason, class) do
    format_stop_as_exception(reason, class)
  end

  defp format_stop_as_exception(reason, class) do
    {class <> " (stop)", Exception.format_exit(reason), _stacktrace = []}
  end

  defp format_error_as_exception(reason, stacktrace, class) do
    case Exception.normalize(:error, reason, stacktrace) do
      %ErlangError{} ->
        {class, Exception.format_exit(reason), stacktrace}
      exception ->
        class = class <> " (" <> inspect(exception.__struct__) <> ")"
        {class, Exception.message(exception), stacktrace}
    end
  end

  defp charlist_contains?(charlist, part) do
    :string.str(charlist, part) != 0
  end
end
