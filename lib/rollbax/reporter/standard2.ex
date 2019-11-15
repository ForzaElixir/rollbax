defmodule Rollbax.Reporter.Standard2 do
  @moduledoc """
  A `Rollbax.Reporter` that translates crashes and exits from processes
  to nicely-formatted Rollbar exceptions.

  Compatible with the new Elixir Logger.
  """

  @behaviour Rollbax.Reporter

  def handle_event(:error,
        {Logger,
          msg,
          _timestamp,
          [{:crash_reason, {reason, stacktrace}} | _]}) do
    handle_error_format(msg, reason, stacktrace)
  end
  def handle_event(_type, _event) do
    :next
  end

  ## generic process death.
  defp handle_error_format(["Process" <> _ | _], reason, stacktrace) do
    {class, message, stacktrace} = format_as_exception(
      reason,
      stacktrace,
      "process terminating")

    %Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: %{}}
  end

  ## genserver death.
  defp handle_error_format(info = ["GenServer" <> _| _], reason, stacktrace) do
    {class, message, stacktrace} = format_as_exception(
      reason,
      stacktrace,
      "GenServer terminating")

    death_info = :erlang.iolist_to_binary(info)

    %Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: %{
      #  "name" => parse_name(death_info),
      #  "last_message" => parse_message(death_info),
      #  "state" => parse_state(death_info)
      }}
  end

  ## task death.
  defp handle_error_format(info = ["Task" <> _| _], reason, stacktrace) do
    {class, message, stacktrace} = format_as_exception(
      reason,
      stacktrace,
      "Task terminating")

    death_info = :erlang.iolist_to_binary(info)

    %Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: %{
      #  "name" => inspect(name),
      #  "started_from" => inspect(starter),
      #  "function" => inspect(function),
      #  "arguments" => inspect(arguments)
      }}
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
