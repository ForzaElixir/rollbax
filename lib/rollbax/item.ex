defmodule Rollbax.Item do
  def draft(token, envt) do
    {:ok, host} = :inet.gethostname
    %{
      access_token: token,
      data: %{
        server: %{
          host: List.to_string(host)
        },
        environment: envt,
        language: language(),
        platform: platform(),
        notifier: notifier()
      }
    }
  end

  def compose(draft, {level, e, stacktrace, time, meta}) do
    {occurr_data, meta} =
      Map.pop(meta, :rollbax_occurr_data, %{})
    Map.update!(draft, :data, fn(data) ->
      Map.merge(occurr_data, data)
      |> put_body(e, stacktrace)
      |> put_custom(meta)
      |> Map.put(:level, level)
      |> Map.put(:timestamp, time)
    end)
  end

  # If a message with no stack trace, use "message"
  defp put_body(data, e, nil) do
    Map.put(data, :body, %{ message: %{ body: Exception.format(:error, e, nil) } })
  end

  # If this payload is a single exception, use "trace"
  # stacktrace example: [{Test, :report, 2, [file: 'file.exs', line: 16]}]
  defp put_body(data, e, stacktrace) do
    Map.put(data, :body, %{ trace: trace(e, stacktrace) })
  end

  defp trace(e, stacktrace) do
    %{ frames: frames(stacktrace), exception: exception(e) }
  end

  # Required: frames
  # A list of stack frames, ordered such that the most recent call is last in the list.
  # TODO implement all options. See https://rollbar.com/docs/api/items_post/
  defp frames(stacktrace) do
    Enum.map(stacktrace, fn({_, _, _, file}) ->
      %{
        # Required: filename
        # The filename including its full path
        filename: file[:file],

        # Optional: lineno
        # The line number as an integer
        lineno: file[:line]
      }
    end)
  end

  # Required: exception
  # An object describing the exception instance.
  # TODO description
  defp exception(e) do
    %{
      # Required: class
      # The exception class name.
      class: to_string(e.__struct__),

      # Optional: message
      # The exception message, as a string
      message: e.message
    }
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
