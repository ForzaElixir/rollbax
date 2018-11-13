defmodule Rollbax.Client do
  @moduledoc false

  # This GenServer keeps a pre-built bare-bones version of an exception (a
  # "draft") to be reported to Rollbar, which is then filled with the data
  # related to each specific exception when such exception is being
  # reported. This GenServer is also responsible for actually sending data to
  # the Rollbar API and receiving responses from said API.

  use GenServer

  require Logger

  alias Rollbax.Item

  @name __MODULE__
  @hackney_pool __MODULE__
  @headers [{"content-type", "application/json"}]

  ## GenServer state

  defstruct [:draft, :url, :enabled, :hackney_opts, hackney_responses: %{}]

  ## Public API

  def start_link(config) do
    state = %__MODULE__{
      draft: Item.draft(config[:access_token], config[:environment], config[:custom]),
      url: config[:api_endpoint],
      enabled: config[:enabled],
      hackney_opts: hackney_opts(config)
    }

    GenServer.start_link(__MODULE__, state, name: @name)
  end

  defp hackney_opts(config) do
    hackney_extra_opts =
      if config[:proxy] do
        [proxy: config[:proxy]]
      else
        []
      end

    [:async, pool: @hackney_pool] ++ hackney_extra_opts
  end

  def emit(level, timestamp, body, custom, occurrence_data)
      when is_atom(level) and is_integer(timestamp) and timestamp > 0 and is_map(body) and
             is_map(custom) and is_map(occurrence_data) do
    if pid = Process.whereis(@name) do
      event = {Atom.to_string(level), timestamp, body, custom, occurrence_data}
      GenServer.cast(pid, {:emit, event})
    else
      Logger.warn(
        "(Rollbax) Trying to report an exception but the :rollbax application has not been started",
        rollbax: false
      )
    end
  end

  ## GenServer callbacks

  def init(state) do
    Logger.metadata(rollbax: false)
    :ok = :hackney_pool.start_pool(@hackney_pool, max_connections: 20)
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok = :hackney_pool.stop_pool(@hackney_pool)
  end

  def handle_cast({:emit, _event}, %{enabled: false} = state) do
    {:noreply, state}
  end

  def handle_cast({:emit, event}, %{enabled: :log} = state) do
    Logger.info(["(Rollbax) registered report.\n", event_to_chardata(event)])
    {:noreply, state}
  end

  def handle_cast({:emit, event}, %{enabled: true} = state) do
    case compose_json(state.draft, event) do
      {:ok, payload} ->
        case :hackney.post(state.url, @headers, payload, state.hackney_opts) do
          {:ok, _ref} ->
            :ok

          {:error, reason} ->
            Logger.error("(Rollbax) connection error: #{inspect(reason)}")
        end

      {:error, exception} ->
        Logger.error([
          "(Rollbax) failed to encode report below ",
          "for reason: ",
          Exception.message(exception),
          ?\n,
          event_to_chardata(event)
        ])
    end

    {:noreply, state}
  end

  def handle_info({:hackney_response, ref, response}, state) do
    new_state = handle_hackney_response(ref, response, state)
    {:noreply, new_state}
  end

  def handle_info(message, state) do
    Logger.info("(Rollbax) unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  ## Helper functions

  defp compose_json(draft, event) do
    draft
    |> Item.compose(event)
    |> Jason.encode_to_iodata()
  end

  defp event_to_chardata({level, timestamp, body, custom, occurrence_data}) do
    [
      inspect(body),
      "\nLevel: ",
      level,
      "\nTimestamp: ",
      Integer.to_string(timestamp),
      "\nCustom data: ",
      inspect(custom),
      "\nOccurrence data: ",
      inspect(occurrence_data)
    ]
  end

  defp handle_hackney_response(ref, :done, %{hackney_responses: responses} = state) do
    body = responses |> Map.fetch!(ref) |> IO.iodata_to_binary()

    case Jason.decode(body) do
      {:ok, %{"err" => 1, "message" => message}} when is_binary(message) ->
        Logger.error("(Rollbax) API returned an error: #{inspect(message)}")

      {:ok, response} ->
        Logger.debug("(Rollbax) API response: #{inspect(response)}")

      {:error, _} ->
        Logger.error("(Rollbax) API returned malformed JSON: #{inspect(body)}")
    end

    %{state | hackney_responses: Map.delete(responses, ref)}
  end

  defp handle_hackney_response(
         ref,
         {:status, code, description},
         %{hackney_responses: responses} = state
       ) do
    if code != 200 do
      Logger.error("(Rollbax) unexpected API status: #{code}/#{description}")
    end

    %{state | hackney_responses: Map.put(responses, ref, [])}
  end

  defp handle_hackney_response(_ref, {:headers, headers}, state) do
    Logger.debug("(Rollbax) API headers: #{inspect(headers)}")
    state
  end

  defp handle_hackney_response(ref, body_chunk, %{hackney_responses: responses} = state)
       when is_binary(body_chunk) do
    %{state | hackney_responses: Map.update!(responses, ref, &[&1 | body_chunk])}
  end

  defp handle_hackney_response(ref, {:error, reason}, %{hackney_responses: responses} = state) do
    Logger.error("(Rollbax) connection error: #{inspect(reason)}")
    %{state | hackney_responses: Map.delete(responses, ref)}
  end
end
