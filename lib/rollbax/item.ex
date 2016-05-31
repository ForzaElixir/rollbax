defmodule Rollbax.Item do
  def draft(token, envt) do
    {:ok, host} = :inet.gethostname
    %{
      "access_token" => token,
      "data" => %{
        "server" => %{
          "host" => List.to_string(host)
        },
        "environment" => envt,
        "language" => language(),
        "platform" => platform(),
        "notifier" => notifier()
      }
    }
  end

  def compose(draft, {level, timestamp, body, meta}) do
    {occurr_data, meta} =
      Map.pop(meta, :rollbax_occurr_data, %{})
    Map.update!(draft, "data", fn(data) ->
      Map.merge(occurr_data, data)
      |> Map.put("body", body)
      |> put_custom(meta)
      |> Map.put("level", level)
      |> Map.put("timestamp", timestamp)
    end)
  end

  def message_to_body(message) do
    %{"message" => %{"body" => message}}
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
