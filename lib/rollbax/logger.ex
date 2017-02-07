defmodule Rollbax.Logger do
  @moduledoc """
  An [`:error_logger`](http://erlang.org/doc/man/error_logger.html) handler for
  automatically sending failures in processes to Rollbar.
  """

  use GenEvent

  require Logger

  @doc false
  def init(_args) do
    {:ok, []}
  end

  @doc false
  def handle_event(event, state)

  # If the event is on a different node than the current node, we ignore it.
  def handle_event({_level, gl, _event}, state)
      when node(gl) != node() do
    {:ok, state}
  end

  # We only care about error format events, and not even all of them (but we'll
  # filter the one we don't care about in handle_error_format/2).
  def handle_event({:error, _gl, {_pid, format, data}}, state) do
    handle_error_format(format, data)
    {:ok, state}
  end

  # All other events are useless for us.
  def handle_event(event, state) do
    {:ok, state}
  end

  # Errors in a GenServer.
  defp handle_error_format('** Generic server ' ++ _, [name, last_message, state, reason]) do
    {class, message, stacktrace} = format_as_exception(reason, "GenServer terminating")
    custom = %{
      "name" => inspect(name),
      "last_message" => inspect(last_message),
      "state" => inspect(state),
    }
    Rollbax.report_exception(class, message, stacktrace, custom, _occurrence_data = %{})
  end

  # Errors in a GenEvent handler.
  defp handle_error_format('** gen_event handler ' ++ _, [name, manager, last_message, state, reason]) do
    {class, message, stacktrace} = format_as_exception(reason, "GenEvent handler terminating")
    custom = %{
      "name" => inspect(name),
      "manager" => inspect(manager),
      "last_message" => inspect(last_message),
      "state" => inspect(state),
    }
    Rollbax.report_exception(class, message, stacktrace, custom, _occurrence_data = %{})
  end

  # Errors in a task.
  defp handle_error_format('** Task ' ++ _, [name, starter, function, arguments, reason]) do
    {class, message, stacktrace} = format_as_exception(reason, "Task terminating")
    custom = %{
      "name" => inspect(name),
      "started_from" => inspect(starter),
      "function" => inspect(function),
      "arguments" => inspect(arguments),
    }
    Rollbax.report_exception(class, message, stacktrace, custom, _occurrence_data = %{})
  end

  # Errors in a regular process.
  defp handle_error_format('Error in process ' ++ _, [pid, {reason, stacktrace}]) do
    exception = Exception.normalize(:error, reason)
    class = "error in process (#{inspect(exception.__struct__)})"
    message = Exception.message(exception)
    custom = %{
      "pid" => inspect(pid),
    }
    Rollbax.report_exception(class, message, stacktrace, custom, _occurrence_data = %{})
  end

  # Any other error (for example, the ones logged through
  # :error_logger.error_msg/1). We don't want to report those to Rollbar.
  defp handle_error_format(_format, _data) do
    Logger.debug "Got an error format that doesn't resemble a crash, so ignoring it"
    :ok
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
        {class, _message = inspect(reason), _stacktrace = []}
    else
      :ok ->
        format_as_exception(maybe_exception, maybe_stacktrace, class)
    end
  end

  defp format_as_exception(reason, class) do
    {class, Exception.format_exit(reason), _stacktrace = []}
  end

  defp format_as_exception(reason, stacktrace, class) do
    case Exception.normalize(:error, reason, stacktrace) do
      %ErlangError{} ->
        {class, Exception.format_exit(reason), stacktrace}
      exception ->
        class = class <> " (" <> inspect(exception.__struct__) <> ")"
        {class, Exception.message(exception), stacktrace}
    end
  end
end
