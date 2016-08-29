defmodule Rollbax.Logger do
  @moduledoc """
  `Logger` backend that reports logged messages to Rollbar.

  This module is a `Logger` backend that reports logged messages to Rollbar. In
  order to use it, first make sure that Rollbax is configured correctly for
  reporting to Rollbar (look at the documentation for the `Rollbax` module for
  more information). Then, add `Rollbax.Logger` as a backend in the
  configuration for the `:logger` application. For example, in
  `config/config.exs`:

      config :logger,
        backends: [:console, Rollbax.Logger]

  ## Configuration

  `Rollbax.Logger` supports the following configuration options:

    * `:level` - (`:debug`, `:info`, `:warn`, or `:error`) the logging
      level. Any message with severity less than the configured level will not
      be reported to Rollbar. Note that messages are filtered by the general
      `:level` configuration option for the `:logger` application first (in the
      same way as for the `:console` backend).
    * `:metadata` - (list of atoms) list of metadata to be attached to the
      reported message. These metadata will be showed alongside each
      "occurrence" of a given item in Rollbar. Defaults to `[]`.

  These options can be configured under `Rollbax.Logger` in the configuration
  for the `:logger` application. For example, in `config/config.exs`:

      config :logger, Rollbax.Logger,
        level: :warn,
        metadata: [:file, :line, :function]

  ## Disable reporting

  Reporting to Rollbar can manually disabled for given `Logger` calls by passing
  the `rollbar: false` as a metadata to such calls. For example, to disable
  reporting for a specific logged message:

      Logger.error("Secret error, better not report this", rollbar: false)

  To disable reporting for all subsequent messages:

      Logger.metadata(rollbar: false)

  """

  use GenEvent

  @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  @doc false
  def init(__MODULE__) do
    {:ok, configure([])}
  end

  @doc false
  def handle_call({:configure, opts}, _state) do
    {:ok, :ok, configure(opts)}
  end

  @doc false
  def handle_event(event, state)

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

  # TODO: in the future, we probably need to flush all responses from Rollbar's
  # API coming from logged messages, so nothing is printed.
  def handle_event(:flush, state) do
    {:ok, state}
  end

  defp proceed?({Logger, _message, _event_time, metadata}) do
    Keyword.get(metadata, :rollbax, true)
  end

  defp meet_level?(level, min_level) do
    Logger.compare_levels(level, min_level) != :lt
  end

  defp post_event(level, {Logger, message, event_time, metadata}, keys) do
    event_unix_time = event_time_to_unix(event_time)
    message = message |> prune_chardata() |> IO.chardata_to_string()
    metadata = Keyword.take(metadata, keys) |> Enum.into(%{})
    body = Rollbax.Item.message_to_body(message, metadata)
    Rollbax.Client.emit(level, event_unix_time, body, %{}, %{})
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

  # Before converting the chardata to log into a string (with
  # IO.chardata_to_string/1), we need to prune it so that we don't try to
  # convert invalid unicode codepoints, which leads to a UnicodeConversionError
  # being raised. This function is taken basically straight from
  # https://github.com/elixir-lang/elixir/blob/e26f8de5753c16ad047b25e4ee9c31b9a45026e5/lib/logger/lib/logger/formatter.ex#L49-L66.
  replacement = "�"

  defp prune_chardata(binary) when is_binary(binary), do: prune_binary(binary, "")
  defp prune_chardata([head | tail]) when head in 0..1114111, do: [head | prune_chardata(tail)]
  defp prune_chardata([head | tail]), do: [prune_chardata(head) | prune_chardata(tail)]
  defp prune_chardata([]), do: []
  defp prune_chardata(_), do: unquote(replacement)

  defp prune_binary(<<head::utf8, tail::binary>>, acc),
    do: prune_binary(tail, <<acc::binary, head::utf8>>)
  defp prune_binary(<<_, tail::binary>>, acc),
    do: prune_binary(tail, <<acc::binary, unquote(replacement)>>)
  defp prune_binary(<<>>, acc),
    do: acc
end
