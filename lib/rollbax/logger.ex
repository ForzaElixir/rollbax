defmodule Rollbax.Logger do
  @moduledoc """
  TODO
  """

  @behaviour :gen_event

  defstruct [:reporters]

  @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  @doc false
  def init(_args) do
    reporters = Application.get_env(:rollbax, :reporters, [Rollbax.Reporter.Standard])
    {:ok, %__MODULE__{reporters: reporters}}
  end

  @doc false
  def handle_event(event, state)

  # If the event is on a different node than the current node, we ignore it.
  def handle_event({_level, gl, _event}, state)
      when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({level, _gl, event}, %__MODULE__{reporters: reporters} = state) do
    :ok = run_reporters(reporters, level, event)
    {:ok, state}
  end

  @doc false
  def handle_call(request, _state) do
    exit({:bad_call, request})
  end

  @doc false
  def handle_info(_message, state) do
    {:ok, state}
  end

  @doc false
  def terminate(_reason, _state) do
    :ok
  end

  @doc false
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  defp run_reporters([reporter | rest], level, event) do
    case reporter.handle_event(level, event) do
      %Rollbax.Exception{} = exception ->
        Rollbax.report_exception(exception)
      :next ->
        run_reporters(rest, level, event)
      :ignore ->
        :ok
    end
  end

  # If no reporter ignored or reported this event, then we're gonna report this
  # as a Rollbar "message" with the same logic that Logger uses to translate
  # messages (so that it will have Elixir syntax when reported).
  defp run_reporters([], level, event) do
    config =
      Application.get_all_env(:logger)
      |> Keyword.take([:handle_sasl_reports, :handle_otp_reports, :translators, :truncate])
      |> Enum.into(%{})

    if message = build_message(level, event, config) do
      body = message |> IO.chardata_to_string() |> Rollbax.Item.message_body()
      Rollbax.Client.emit(:error, current_timestamp(), body, %{}, %{})
    else
      :ok
    end
  end

  defp build_message(:error, {_pid, format, data}, %{handle_otp_reports: true} = config),
    do: build_message(:error, :format, {format, data}, config)
  defp build_message(:error_report, {_pid, :std_error, format}, %{handle_otp_reports: true} = config),
    do: build_message(:error, :report, {:std_error, format}, config)
  defp build_message(:error_report, {_pid, :supervisor_report, data}, %{handle_sasl_reports: true} = config),
    do: build_message(:error, :report, {:supervisor_report, data}, config)
  defp build_message(:error_report, {_pid, :crash_report, data}, %{handle_sasl_reports: true} = config),
    do: build_message(:error, :report, {:crash_report, data}, config)
  defp build_message(_level, _event, _config),
    do: nil

  defp build_message(level, kind, data, config) do
    %{translators: translators, truncate: truncate} = config

    case translate(translators, level, kind, data, truncate) do
      {:ok, message} ->
        Logger.Utils.truncate(message, truncate)
      _other ->
        nil
    end
  end

  defp translate([{mod, fun} | rest] = _translators, level, kind, data, truncate) do
    case apply(mod, fun, [_min_level = :error, level, kind, data]) do
      {:ok, _chardata} = result -> result
      :next -> :next
      :none -> translate(rest, level, kind, data, truncate)
    end
  end

  defp translate([], _level, :format, {format, args}, truncate) do
    {format, args} = Logger.Utils.inspect(format, args, truncate)
    {:ok, :io_lib.format(format, args)}
  end

  defp translate([], _level, :report, {_type, data}, _truncate) do
    {:ok, Kernel.inspect(data)}
  end

  defp current_timestamp() do
    :calendar.datetime_to_gregorian_seconds(:calendar.universal_time()) - @unix_epoch
  end
end
