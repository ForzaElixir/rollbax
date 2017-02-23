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
    if message = format_event(level, event) do
      body =
        message
        |> IO.chardata_to_string()
        |> Rollbax.Item.message_body()

      Rollbax.Client.emit(:error, current_timestamp(), body, %{}, %{})
    end

    :ok
  end

  defp format_event(:error, {_pid, format, args}),
    do: :io_lib.format(format, args)
  defp format_event(:error_report, {_pid, type, format})
       when type in [:std_error, :supervisor_report, :crash_report],
    do: inspect(format)
  defp format_event(_type, _data),
    do: nil

  defp current_timestamp() do
    :calendar.datetime_to_gregorian_seconds(:calendar.universal_time()) - @unix_epoch
  end
end
