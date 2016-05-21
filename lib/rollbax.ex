defmodule Rollbax do
  use Application

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

  def report(exception, stacktrace, meta \\ %{} , occurr_data \\ %{})
  when is_list(stacktrace) and is_map(meta) and is_map(occurr_data) do
    meta = Map.put(meta, :rollbax_occurr_data, occurr_data)
    Rollbax.Client.emit(:error, exception, stacktrace, meta)
  end
end
