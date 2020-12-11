defmodule Rollbax do
  @moduledoc """
  This module provides functions to report any kind of exception or message to
  [Rollbar](https://rollbar.com).

  ## Configuration

  The `:rollbax` application needs to be configured properly in order to
  work. This configuration can be done, for example, in `config/config.exs`:

      config :rollbax,
        access_token: "9309123491",
        environment: "production"

  The following is a comprehensive list of configuration options supported by Rollbax:

    * `:access_token` - (binary or `nil`) the token needed to access the [Rollbar
      Items API (POST)](https://rollbar.com/docs/api/items_post/). As of now, Rollbar provides
      several access tokens for different "parts" of their API: for this configuration option, the
      `"post_server_item"` access token is needed. This option is required only when the
      `:enabled` option is set to `true`, and can be `nil` otherwise.

    * `:environment` - (binary) the environment that will be attached to each reported exception.

    * `:enabled` - (`true | false | :log`) decides whether things reported with `report/5` or
      `report_message/4` are actually reported to Rollbar. If `true`, they are reported; if
      `false`, `report/5` and `report_message/4` don't do anything; if `:log`, things reported
      with `report/5` and `report_message/4` are instead logged to the shell.

    * `:custom` - (map) a map of any arbitrary metadata you want to attach to everything reported
      by Rollbax. If custom data is specified in an individual call to `report/5` or
      `report_message/5` it will be merged with the global data, with the individual data taking
      precedence in case of conflicts. Defaults to `%{}`.

    * `:api_endpoint` - (binary) the Rollbar endpoint to report exceptions and messages to.
      Defaults to `https://api.rollbar.com/api/1/item/`.

    * `:enable_crash_reports` - see `Rollbax.Logger`.

    * `:reporters` - see `Rollbax.Logger`.

    * `:proxy` - (binary) a proxy that can be used to connect to the Rollbar host. For more
      information about the format of the proxy, check the proxy URL description in the
      [hackney documentation](https://github.com/benoitc/hackney#proxy-a-connection).

  ## Runtime configuration

  Configuration can be modified at runtime by providing a configuration callback, like this:

      config :rollbax,
        config_callback: {MyModule, :my_function}

  In the example above, `MyModule.my_function/1` will be called with the existing configuration as
  an argument. It's supposed to return a keyword list representing a possibly modified
  configuration. This can for example be used to read system environment variables at runtime when
  the application starts:

      defmodule MyModule do
        def my_function(config) do
          Keyword.put(config, :access_token, System.get_env("ROLLBAR_ACCESS_TOKEN"))
        end
      end

  ## Logger backend

  Rollbax provides a module that reports logged crashes and exits to Rollbar. For more
  information, look at the documentation for `Rollbax.Logger`.
  """

  use Application

  @allowed_message_levels [:critical, :error, :warning, :info, :debug]

  @doc false
  def start(_type, _args) do
    config = init_config()

    unless config[:enabled] in [true, false, :log] do
      raise ArgumentError, ":enabled may be only one of: true, false, or :log"
    end

    if config[:enabled] == true and is_nil(config[:access_token]) do
      raise ArgumentError, ":access_token is required when :enabled is true"
    end

    if config[:enable_crash_reports] do
      # We do this because the handler will read `:reporters` out of the app's environment.
      Application.put_env(:rollbax, :reporters, config[:reporters])
      :error_logger.add_report_handler(Rollbax.Logger)
    end

    children = [
      {Rollbax.Client, [config]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp init_config() do
    env = Application.get_all_env(:rollbax)

    config =
      env
      |> Keyword.take([
        :enabled,
        :custom,
        :api_endpoint,
        :enable_crash_reports,
        :reporters,
        :proxy
      ])
      |> put_if_present(:environment, env[:environment])
      |> put_if_present(:access_token, env[:access_token])

    case Application.get_env(:rollbax, :config_callback) do
      {config_callback_mod, config_callback_fun} ->
        apply(config_callback_mod, config_callback_fun, [config])

      nil ->
        config
    end
  end

  defp put_if_present(keyword, key, value) do
    if value, do: Keyword.put(keyword, key, value), else: keyword
  end

  @doc """
  Reports the given error/exit/throw.

  `kind` specifies the kind of exception being reported while `value` specifies
  the value of that exception. `kind` can be:

    * `:error` - reports an exception defined with `defexception`. `value` must
      be an exception, or this function will raise an `ArgumentError` exception.

    * `:exit` - reports an exit. `value` can be any term.

    * `:throw` - reports a thrown term. `value` can be any term.

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

  This function is **fire-and-forget**: it will always return `:ok` right away and
  perform the reporting of the given exception in the background so as to not block
  the caller.

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
      when kind in [:error, :exit, :throw] and is_list(stacktrace) and is_map(custom) and
             is_map(occurrence_data) do
    {class, message} = Rollbax.Item.exception_class_and_message(kind, value)

    report_exception(%Rollbax.Exception{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: custom,
      occurrence_data: occurrence_data
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
  @spec report_message(:critical | :error | :warning | :info | :debug, IO.chardata(), map, map) ::
          :ok
  def report_message(level, message, custom \\ %{}, occurrence_data \\ %{})
      when level in @allowed_message_levels and is_map(custom) and is_map(occurrence_data) do
    body = message |> IO.chardata_to_string() |> Rollbax.Item.message_body()
    Rollbax.Client.emit(level, System.system_time(:second), body, custom, occurrence_data)
  end

  @doc false
  @spec report_exception(Rollbax.Exception.t()) :: :ok
  def report_exception(%Rollbax.Exception{} = exception) do
    %{
      class: class,
      message: message,
      stacktrace: stacktrace,
      custom: custom,
      occurrence_data: occurrence_data
    } = exception

    body = Rollbax.Item.exception_body(class, message, stacktrace)
    Rollbax.Client.emit(:error, System.system_time(:second), body, custom, occurrence_data)
  end
end
