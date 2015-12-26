defmodule Rollbax.Item do
  def draft(token, envt) do
    {:ok, host} = :inet.gethostname
    %{"access_token" => token,
      "data" => %{
        "server" => %{
          "host" => List.to_string(host)
        },
        "environment" => envt,
        "language" => language(),
        "platform" => platform(),
        "framework" => "OTP",
        "notifier" => notifier()
      }
    }
  end

  def compose(draft, {level, msg, time, meta}) do
    {occurr_data, meta} =
      Map.pop(meta, :rollbax_occurr_data, %{})
    Map.update!(draft, "data", fn(data) ->
      Map.merge(occurr_data, data)
      |> put_body(msg)
      |> put_custom(meta)
      |> Map.put("level", level)
      |> Map.put("timestamp", time)
    end)
  end

  defp put_body(data, msg) do
    Map.put(data, "body", %{"message" => %{"body" => msg}})
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
