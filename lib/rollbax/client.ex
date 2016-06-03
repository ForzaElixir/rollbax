defmodule Rollbax.Client do
  use GenServer

  require Logger

  alias Rollbax.Item

  @api_url "https://api.rollbar.com/api/1/item/"
  @headers [{"content-type", "application/json"}]

  ## GenServer state

  defstruct [:draft, :url, :enabled]

  ## Public API

  def start_link(token, environment, enabled, url \\ @api_url) do
    state = new(token, environment, url, enabled)
    GenServer.start_link(__MODULE__, state, [name: __MODULE__])
  end

  def new(token, environment, url, enabled) do
    draft = Item.draft(token, environment)
    %__MODULE__{draft: draft, url: url, enabled: enabled}
  end

  def emit(level, timestamp, body, meta) when is_map(meta) do
    event = {Atom.to_string(level), timestamp, body, meta}
    GenServer.cast(__MODULE__, {:emit, event})
  end

  ## GenServer callbacks

  def init(state) do
    Logger.metadata(rollbax: false)
    :ok = :hackney_pool.start_pool(__MODULE__, [max_connections: 20])
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok = :hackney_pool.stop_pool(__MODULE__)
  end

  def handle_cast({:emit, _event}, %{enabled: false} = state) do
    {:noreply, state}
  end

  def handle_cast({:emit, event}, %{enabled: :log} = state) do
    {level, timestamp, body, meta} = event
    Logger.info [
      "(Rollbax) registered report:", ?\n, inspect(body),
      "\n    Level: ", level,
      "\nTimestamp: ", Integer.to_string(timestamp),
      "\n Metadata: " | inspect(meta)]
    {:noreply, state}
  end

  def handle_cast({:emit, event}, %{enabled: true} = state) do
    payload = compose_json(state.draft, event)
    opts = [:async, pool: __MODULE__]
    case :hackney.post(state.url, @headers, payload, opts) do
      {:ok, _ref} -> :ok
      {:error, reason} ->
        Logger.error("(Rollbax) connection error: #{inspect(reason)}")
    end
    {:noreply, state}
  end

  def handle_info({:hackney_response, _ref, :done}, state) do
    {:noreply, state}
  end

  def handle_info({:hackney_response, _ref, response}, state) do
    case response do
      {:status, code, desc} when code != 200 ->
        Logger.warn("(Rollbax) unexpected API status: #{code}/#{desc}")
      {:error, reason} ->
        Logger.error("(Rollbax) connection error: #{inspect(reason)}")
      _otherwise ->
        Logger.debug("(Rollbax) API response: #{inspect(response)}")
    end
    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.info("(Rollbax) unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  ## Helper functions

  defp compose_json(draft, event) do
    Item.compose(draft, event)
    |> Poison.encode!(iodata: true)
  end
end
