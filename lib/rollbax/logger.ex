defmodule Rollbax.Logger do
  @moduledoc """
  TODO
  """

  use GenEvent

  require Logger

  @default_included_process_info [
    :initial_call,
    :links,
    :registered_name,
    :status,
    :trap_exit,
  ]

  @doc false
  def init(_args) do
    {:ok, []}
  end

  @doc false
  def handle_event(event, state)

  def handle_event({_level, gl, _event}, state)
      when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({:error_report, _gl, {_pid, :crash_report, [crash_info | _linked]}}, state) do
    handle_crash_report(crash_info)
    {:ok, state}
  end

  def handle_event(_event, state) do
    {:ok, state}
  end

  defp handle_crash_report(crash_info) do
    {error_info, crash_info} = Keyword.pop(crash_info, :error_info)

    # When the kind is :exit, "value" could be a two-element tuple. In such
    # cases, the second element could be a stacktrace or not: for example, if
    # the first value is an exception, the second value is a stacktrace (try to
    # raise an error inside a GenServer and you will see this). However,
    # sometimes the second value is not a stacktrace: for example, throwing from
    # a GenServer will make the tuple look like "{:bad_return_value,
    # :thrown_value}". To overcome this, we use the same hack that Elixir's
    # source uses inside Exception.format_exit/1: we try to format the
    # stacktrace as a stacktrace and if we fail then we consider it not being a
    # stacktrace.
    {kind, value, stacktrace} =
      case error_info do
        {:exit, {maybe_exception, maybe_stacktrace} = value, stacktrace} ->
          try do
            Enum.each(maybe_stacktrace, &Exception.format_stacktrace_entry/1)
          else
            :ok -> {:exit, maybe_exception, maybe_stacktrace}
          catch
            :error, _ -> {:exit, value, stacktrace}
          end
        other ->
          other
      end

    Rollbax.report(kind, value, stacktrace, custom_data_from_crash_info(crash_info))
  end

  defp custom_data_from_crash_info(crash_info) do
    included_process_info =
      :rollbax
      |> Application.get_env(:crash_reports)
      |> Keyword.get(:included_process_info, @default_included_process_info)

    crash_info =
      if :initial_call in included_process_info and Keyword.has_key?(crash_info, :initial_call) do
        Keyword.update!(crash_info, :initial_call, fn {module, function, args} ->
          Exception.format_mfa(module, function, args)
        end)
      else
        crash_info
      end

    for {key, value} <- crash_info,
        key in included_process_info,
        into: %{},
        do: {key, if(is_binary(value), do: value, else: inspect(value))}
  end
end
