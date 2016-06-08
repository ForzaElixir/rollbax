defmodule Rollbax do
  @moduledoc """
  This module provides functions to report any kind of exception to
  [Rollbar](https://rollbar.com).
  """

  use Application

  @doc false
  def start(_type, _args) do
    import Supervisor.Spec

    enabled = get_config(:enabled, true)

    token = fetch_config(:access_token)
    envt  = fetch_config(:environment)

    children = [
      worker(Rollbax.Client, [token, envt, enabled])
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
  when kind in [:error, :exit, :throw] and is_list(stacktrace) and is_map(custom) and is_map(occurrence_data) do
    # We need this manual check here otherwise Exception.format_banner(:error,
    # term) will assume that term is an Erlang error (it will say
    # "** # (ErlangError) ...").
    if kind == :error and not Exception.exception?(value) do
      raise ArgumentError, "expected an exception, got: #{value}"
    end

    body = Rollbax.Item.exception_to_body(kind, value, stacktrace)
    Rollbax.Client.emit(:error, unix_time(), body, custom, occurrence_data)
  end

  @doc """
  Same as `report(:error, exception, stacktrace)`.

  Fails if `exception` is not an exception.

  ## Examples

      Rollbax.report(ArgumentError.exception("oops"), System.stacktrace)

  """
  @spec report(Exception.t, [any]) :: :ok
  def report(exception, stacktrace) when is_list(stacktrace) do
    report(:error, exception, stacktrace)
  end

  defp get_config(key, default) do
    Application.get_env(:rollbax, key, default)
  end

  defp fetch_config(key) do
    case get_config(key, :not_found) do
      :not_found ->
        raise ArgumentError, "the configuration parameter #{inspect(key)} is not set"
      value -> value
    end
  end

  defp unix_time() do
    {mgsec, sec, _usec} = :os.timestamp()
    mgsec * 1_000_000 + sec
  end
end
