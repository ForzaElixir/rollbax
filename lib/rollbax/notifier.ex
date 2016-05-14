defmodule Rollbax.Notifier do
  use GenEvent

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

  defp proceed?({Logger, _msg, _ts, meta}) do
    Keyword.get(meta, :rollbax, true)
  end

  defp meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

  defp post_event(level, {Logger, msg, _ts, meta}, keys) do
    msg = IO.chardata_to_string(msg)
    meta = Map.take(meta, keys)
    Rollbax.Client.emit(level, msg, meta)
  end

  defp configure(opts) do
    config =
      Application.get_env(:logger, __MODULE__, [])
      |> Keyword.merge(opts)
    Application.put_env(:logger, __MODULE__, config)

    %{level: Keyword.get(config, :level, :error),
      metadata: Keyword.get(config, :metadata, [])}
  end
end
