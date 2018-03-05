defmodule Rollbax.Logger do
  @moduledoc """
  A module that can be used to report crashes and exits to Rollbar.

  In Elixir and Erlang, crashes from GenServers and other processes are reported through
  `:error_logger`. When installed, this module installs an `:error_logger` handler that can be
  used to report such crashes to Rollbar automatically.

  In order to use this functionality, you must configure the `:rollbax` application to report
  crashes with:

      config :rollbax, :enable_crash_reports, true

  All the configuration options for reporting crashes are documented in detail below. If you are
  upgrading from an older version of Rollbax that used this module as a logger backend via
  `config :logger, backends: [:console, Rollbax.Logger]` this config should be removed.

  `Rollbax.Logger` implements a mechanism of reporting based on *reporters*, which are modules
  that implement the `Rollbax.Reporter` behaviour. Every message received by `Rollbax.Logger` is
  run through a list of reporters and the behaviour is determined by the return value of each
  reporter's `c:Rollbax.Reporter.handle_event/2` callback:

    * when the callback returns a `Rollbax.Exception` struct, the exception is reported to Rollbar
      and no other reporters are called

    * when the callback returns `:next`, the reporter is skipped and Rollbax moves on to the next
      reporter

    * when the callback returns `:ignore`, the reported message is ignored and no more reporters
      are tried.

  The list of reporters can be configured in the `:reporters` key in the `:rollbax` application
  configuration. By default this list only contains `Rollbax.Reported.Standard` (see its
  documentation for more information). Rollbax also comes equipped with a
  `Rollbax.Reporter.Silencing` reporter that doesn't report anything it receives. For examples on
  how to provide your own reporters, look at the source for `Rollbax.Reporter.Standard`.

  ## Configuration

  The following reporting-related options can be used to configure the `:rollbax` application:

    * `:enable_crash_reports` (boolean) - when `true`, `Rollbax.Logger` is registered as an
      `:error_logger` handler and the whole reporting flow described above is executed.

    * `:reporters` (list) - a list of modules implementing the `Rollbax.Reporter` behaviour.
      Defaults to `[Rollbax.Reporter.Standard]`.

  """

  @behaviour :gen_event

  defstruct [:reporters]

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
  defp run_reporters([], _level, _event) do
    :ok
  end
end
