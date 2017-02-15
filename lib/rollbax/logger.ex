defmodule Rollbax.Logger do
  @moduledoc """
  An [`:error_logger`](http://erlang.org/doc/man/error_logger.html) handler for
  automatically sending failures in processes to Rollbar.
  """

  use GenEvent

  defstruct [:reporters]

  @doc false
  def init(_args) do
    reporters = Application.get_env(:rollbax, :reporters, []) ++ [Rollbax.DefaultReporter]
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

  defp run_reporters([reporter | rest], level, event) do
    case reporter.handle_event(level, event) do
      %Rollbax.Exception{} = exception ->
        Rollbax.report_exception(exception)
      :noop ->
        run_reporters(rest, level, event)
      :dont_report ->
        :ok
    end
  end

  defp run_reporters([], _level, _event) do
    :ok
  end
end
