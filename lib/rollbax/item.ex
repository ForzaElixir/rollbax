defmodule Rollbax.Item do
  @moduledoc false

  # This module is responsible for building the payload for a Rollbar "Item".
  # Refer to https://rollbar.com/docs/api/items_post for documentation on such
  # payload.

  def draft(token, environment) do
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

  def message_to_body(message, meta) do
    %{"message" => Map.put(meta, "body", message)}
  end

  def exception_to_body(kind, value, stacktrace) do
    %{
      "trace" => %{
        "frames" => stacktrace_to_frames(stacktrace),
        "exception" => exception(kind, value),
      },
    }
  end

  defp exception(:throw, value) do
    %{"class" => "throw", "message" => inspect(value)}
  end

  defp exception(:exit, value) do
    %{"class" => "exit", "message" => Exception.format_exit(value)}
  end

  defp exception(:error, exception) do
    %{"class" => inspect(exception.__struct__), "message" => Exception.message(exception)}
  end

  defp stacktrace_to_frames(stacktrace) do
    Enum.map(stacktrace, &stacktrace_entry_to_frame/1)
  end

  def stacktrace_entry_to_frame({module, fun, arity, location}) when is_integer(arity) do
    %{"method" => Exception.format_mfa(module, fun, arity)}
    |> put_location(location)
  end

  def stacktrace_entry_to_frame({module, fun, arity, location}) when is_list(arity) do
    %{"method" => Exception.format_mfa(module, fun, length(arity)), "args" => Enum.map(arity, &inspect/1)}
    |> put_location(location)
  end

  def stacktrace_entry_to_frame({fun, arity, location}) when is_integer(arity) do
    %{"method" => Exception.format_fa(fun, arity)}
    |> put_location(location)
  end

  def stacktrace_entry_to_frame({fun, arity, location}) when is_list(arity) do
    %{"method" => Exception.format_fa(fun, length(arity)), "args" => Enum.map(arity, &inspect/1)}
    |> put_location(location)
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

  defp put_custom(data, meta) do
    if map_size(meta) == 0 do
      data
    else
      Map.put(data, "custom", meta)
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
