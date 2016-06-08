defmodule Rollbax.Logger do
  @moduledoc false

  # Logger backend that reports messages to Rollbar.

  use GenEvent

  @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  def init(__MODULE__) do
    {:ok, configure([])}
  end

  def handle_call({:configure, opts}, _state) do
    {:ok, :ok, configure(opts)}
  end

  def handle_event({_level, gl, _event}, state)
  when node(gl) != node() do
    {:ok, state}
  end

  def handle_event({level, _gl, event}, %{metadata: keys} = state) do
    if proceed?(event) and meet_level?(level, state.level) do
      post_event(level, event, keys)
    end
    {:ok, state}
  end

  defp proceed?({Logger, _msg, _event_time, meta}) do
    Keyword.get(meta, :rollbax, true)
  end

  defp meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

  defp post_event(level, {Logger, message, event_time, meta}, keys) do
    event_unix_time = event_time_to_unix(event_time)
    body = Rollbax.Item.message_to_body(IO.chardata_to_string(message))
    custom = Map.take(meta, keys)
    Rollbax.Client.emit(level, event_unix_time, body, custom, %{})
  end

  defp configure(opts) do
    config =
      Application.get_env(:logger, __MODULE__, [])
      |> Keyword.merge(opts)
    Application.put_env(:logger, __MODULE__, config)

    %{level: Keyword.get(config, :level, :error),
      metadata: Keyword.get(config, :metadata, [])}
  end

  defp event_time_to_unix({{_, _, _} = date, {hour, min, sec, _millisec}}) do
    :calendar.datetime_to_gregorian_seconds({date, {hour, min, sec}}) - @unix_epoch
  end
end
