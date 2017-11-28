defmodule Rollbax do
  @moduledoc """
  This module provides functions to report any kind of exception to
  [Rollbar](https://rollbar.com).

  ## Configuration

  The `:rollbax` application needs to be configured properly in order to
  work. This configuration can be done, for example, in `config/config.exs`:

      config :rollbax,
        access_token: "9309123491",
        environment: "production"

  The following is a comprehensive list of configuration options supported by Rollbax:

    * `:access_token` - (binary or `{:system, binary}`) the token needed to access the
      [Rollbar Items API (POST)](https://rollbar.com/docs/api/items_post/). As of now,
      Rollbar provides several access tokens for different "parts" of their API: for
      this configuration option, the "post_server_item" access token is needed.
    * `:environment` - (binary or `{:system, binary}`) the environment that will
      be attached to each reported exception.
    * `:enabled` - (`true | false | :log`) decides whether exception reported
      with `Rollbax.report/5` are actually reported to Rollbar. If `true`, they
      are reported; if `false`, `Rollbax.report/5` is basically a no-op; if
      `:log`, exceptions reported with `Rollbax.report/5` are instead logged to
      the shell.
    * `:custom` - (map) a map of any arbitrary metadata you want to attach to
      every exception reported by Rollbax. If custom data is specified in an
      individual call to `Rollbax.report/5` it will be merged with the global
      data, with the individual data taking precedence in case of conflicts.
      Defaults to `%{}`.
    * `:api_endpoint` - (binary) the rollbar endpoint to report exceptions to.
      Defaults to `https://api.rollbar.com/api/1/item/`.

  The `:access_token` and `:environment` options accept a binary or a
  `{:system, "VAR_NAME"}` tuple. When given a tuple like `{:system, "VAR_NAME"}`,
  the value will be referenced from `System.get_env("VAR_NAME")` at runtime.

  ## Logger backend

  Rollbax provides a Logger backend (`Rollbax.Logger`) that reports logged
  messages to Rollbar; for more information, look at the documenation for
  `Rollbax.Logger`.
  """

  use Application

  @default_api_endpoint "https://api.rollbar.com/api/1/item/"
  @allowed_message_levels [:critical, :error, :warning, :info, :debug]

  @doc false
  def start(_type, _args) do
    enabled = Application.get_env(:rollbax, :enabled, true)
    custom = Application.get_env(:rollbax, :custom, %{})
    api_endpoint = Application.get_env(:rollbax, :api_endpoint, @default_api_endpoint)
    environment = resolve_system_env(Application.fetch_env!(:rollbax, :environment))

    access_token =
      case enabled do
        true -> resolve_system_env(Application.fetch_env!(:rollbax, :access_token))
        _other -> :not_needed
      end

    if Application.get_env(:rollbax, :crash_reports, [])[:enabled] do
      :error_logger.add_report_handler(Rollbax.Logger)
    end

    children = [
      Supervisor.Spec.worker(Rollbax.Client, [api_endpoint, access_token, environment, enabled, custom])
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @doc """
  Reports the given error/exit/throw.

  `kind` specifies the kind of exception being reported while `value` specifies
  the value of that exception. `kind` can be:

    * `:error` - reports an exception defined with `defexception`; `value` must
      be an exception, or this function will raise an `ArgumentError` exception
    * `:exit` - reports an exit; `value` can be any term
    * `:throw` - reports a thrown term; `value` can be any term

  The `custom` and `occurrence_data` arguments can be used to customize metadata
  sent to Rollbar. `custom` is a map of any arbitrary metadata you want to
  attach to the exception being reported. `occurrence_data` is a map of
  key-value pairs where keys and values should be understood by the [Rollbar
  POST API for items](https://rollbar.com/docs/api/items_post/); for example, as
  of now Rollbar understands the `"person"` field and uses it to display users
  which an exception affected: `occurrence_data` can be used to attach
  `"person"` data to an exception being reported. Refer to the Rollbar API
  (linked above) for what keys are supported and what the corresponding values
  should be.

  This function is *fire-and-forget*: it will always return `:ok` right away and
  perform the reporting of the given exception in the background.

  ## Examples

  Exceptions can be reported directly:

      Rollbax.report(:error, ArgumentError.exception("oops"), System.stacktrace())
      #=> :ok

  Often, you'll want to report something you either rescued or caught. For
  rescued exceptions:

      try do
        raise ArgumentError, "oops"
      rescue
        exception ->
          Rollbax.report(:error, exception, System.stacktrace())
          # You can also reraise the exception here with reraise/2
      end

  For caught exceptions:

      try do
        throw(:oops)
        # or exit(:oops)
      catch
        kind, value ->
          Rollbax.report(kind, value, System.stacktrace())
      end

  Using custom data:

      Rollbax.report(:exit, :oops, System.stacktrace(), %{"weather" => "rainy"})

  """
  @spec report(:error | :exit | :throw, any, [any], map, map) :: :ok
  def report(kind, value, stacktrace, custom \\ %{}, occurrence_data \\ %{})
      when kind in [:error, :exit, :throw] and
           is_list(stacktrace) and
           is_map(custom) and
           is_map(occurrence_data) do
    {class, message} = Rollbax.Item.exception_class_and_message(kind, value)

    report_exception(%Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: custom,
      occurrence_data: occurrence_data,
    })
  end

  @doc """
  Reports the given `message`.

  `message` will be reported as a simple Rollbar message, for example, without a stacktrace.
  `level` is the level of the message, which can be one of:

    * `:critical`
    * `:error`
    * `:warning`
    * `:info`
    * `:debug`

  `custom` and `occurrence_data` work exactly like they do in `report/5`.

  ## Examples

      Rollbax.report_message(:critical, "Everything is on fire!")
      #=> :ok

  """
  @spec report_message(:critical | :error | :warning | :info | :debug, IO.chardata, map, map) :: :ok
  def report_message(level, message, custom \\ %{}, occurrence_data \\ %{})
      when level in @allowed_message_levels and is_map(custom) and is_map(occurrence_data) do
    body = message |> IO.chardata_to_string() |> Rollbax.Item.message_body()
    Rollbax.Client.emit(level, unix_time(), body, custom, occurrence_data)
  end

  @doc false
  @spec report_exception(Rollbax.Exception.t) :: :ok
  def report_exception(%Rollbax.Exception{} = exception) do
    %{class: class, message: message, stacktrace: stacktrace,
      custom: custom, occurrence_data: occurrence_data} = exception
    body = Rollbax.Item.exception_body(class, message, stacktrace)
    Rollbax.Client.emit(:error, unix_time(), body, custom, occurrence_data)
  end

  defp resolve_system_env({:system, var}) when is_binary(var) do
    System.get_env(var) || raise ArgumentError, "system environment variable #{inspect(var)} is not set"
  end

  defp resolve_system_env(value) do
    value
  end

  defp unix_time() do
    {mgsec, sec, _usec} = :os.timestamp()
    mgsec * 1_000_000 + sec
  end
end
