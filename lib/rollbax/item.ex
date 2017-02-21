defmodule Rollbax.Item do
  @moduledoc false

  # This module is responsible for building the payload for a Rollbar "Item".
  # Refer to https://rollbar.com/docs/api/items_post for documentation on such
  # payload.

  def draft(token, environment, custom) do
    %{
      "access_token" => token,
      "data" => %{
        "server" => %{
          "host" => host(),
        },
        "environment" => environment,
        "language" => language(),
        "platform" => platform(),
        "notifier" => notifier()
      }
      |> put_custom(custom)
    }
  end

  def compose(draft, {level, timestamp, body, custom, occurrence_data}) do
    Map.update!(draft, "data", fn(data) ->
      occurrence_data
      |> Map.merge(data)
      |> Map.put("body", body)
      |> put_custom(custom)
      |> Map.put("level", level)
      |> Map.put("timestamp", timestamp)
    end)
  end

  @doc """
  Returns a map representing the body to be used for representing an "exception"
  on Rollbar.

  `class` and `message` are strings that will be used as the class and message
  of the reported exception. `stacktrace` is the stacktrace of the error.
  """
  @spec exception_body(String.t, String.t, [any]) :: map
  def exception_body(class, message, stacktrace) do
    %{
      "trace" => %{
        "frames" => stacktrace_to_frames(stacktrace),
        "exception" => %{
          "class" => class,
          "message" => message,
        },
      },
    }
  end

  @doc """
  Returns a map representing the body to be used for representing a "message" on
  Rollbar.
  """
  @spec message_body(String.t) :: map
  def message_body(message) do
    %{"message" => %{"body" => message}}
  end

  @doc """
  Returns the exception class and message for the given Elixir error.

  `kind` can be one of `:throw`, `:exit`, or `:error`. A `{class, message}`
  tuple is returned.
  """
  @spec exception_class_and_message(:throw | :exit | :error, any) :: {String.t, String.t}
  def exception_class_and_message(kind, value)

  def exception_class_and_message(:throw, value) do
    {"throw", inspect(value)}
  end

  def exception_class_and_message(:exit, value) do
    message =
      if Exception.exception?(value) do
        Exception.format_banner(:error, value)
      else
        Exception.format_exit(value)
      end
    {"exit", message}
  end

  def exception_class_and_message(:error, error) do
    exception = Exception.normalize(:error, error)
    {inspect(exception.__struct__), Exception.message(exception)}
  end

  defp stacktrace_to_frames(stacktrace) do
    Enum.map(stacktrace, &stacktrace_entry_to_frame/1)
  end

  defp stacktrace_entry_to_frame({module, fun, arity, location}) when is_integer(arity) do
    method = Exception.format_mfa(module, fun, arity) <> maybe_format_application(module)
    put_location(%{"method" => method}, location)
  end

  defp stacktrace_entry_to_frame({module, fun, arity, location}) when is_list(arity) do
    method = Exception.format_mfa(module, fun, arity) <> maybe_format_application(module)
    args = Enum.map(arity, &inspect/1)
    put_location(%{"method" => method, "args" => args}, location)
  end

  defp stacktrace_entry_to_frame({fun, arity, location}) when is_integer(arity) do
    %{"method" => Exception.format_fa(fun, arity)}
    |> put_location(location)
  end

  defp stacktrace_entry_to_frame({fun, arity, location}) when is_list(arity) do
    %{"method" => Exception.format_fa(fun, length(arity)), "args" => Enum.map(arity, &inspect/1)}
    |> put_location(location)
  end

  defp maybe_format_application(module) do
    case :application.get_application(module) do
      {:ok, application} ->
        " (" <> Atom.to_string(application) <> ")"
      :undefined ->
        ""
    end
  end

  defp put_location(frame, location) do
    if file = location[:file] do
      frame = Map.put(frame, "filename", List.to_string(file))
      if line = location[:line] do
        Map.put(frame, "lineno", line)
      else
        frame
      end
    else
      frame
    end
  end

  defp put_custom(data, custom) do
    if map_size(custom) == 0 do
      data
    else
      Map.update(data, "custom", custom, &Map.merge(&1, custom))
    end
  end

  defp host() do
    {:ok, host} = :inet.gethostname()
    List.to_string(host)
  end

  defp language() do
    "Elixir v" <> System.version
  end

  defp platform() do
    :erlang.system_info(:system_version)
    |> List.to_string
    |> String.strip
  end

  defp notifier() do
    %{
      "name" => "Rollbax",
      "version" => unquote(Mix.Project.config[:version])
    }
  end
end
