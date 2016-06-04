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

  def report(kind, value, stacktrace, custom \\ %{}, occurrence_data \\ %{})
  when kind in [:error, :exit, :throw] and is_list(stacktrace) and is_map(custom) and is_map(occurrence_data) do
    # We need this manual check here otherwise Exception.format_banner(:error,
    # term) will assume that term is an Erlang error (it will say
    # "** # (ErlangError) ...").
    if kind == :error and not Exception.exception?(value) do
      raise ArgumentError, "expected an exception when the kind is :error, got: #{value}"
    end

    body = Rollbax.Item.exception_to_body(kind, value, stacktrace)
    Rollbax.Client.emit(:error, unix_time(), body, custom, occurrence_data)
  end

  defp unix_time() do
    {mgsec, sec, _usec} = :os.timestamp()
    mgsec * 1_000_000 + sec
  end
end
