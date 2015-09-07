defmodule Rollbax.Item do
  def draft(token, envt) do
    {:ok, host} = :inet.gethostname()
    %{"access_token" => token,
      "data" => %{
        "server" => %{
          "host" => List.to_string(host)},
        "environment" => envt,
        "language"  => "Elixir",
        "framework" => "OTP"}}
  end

  def compose(draft, {level, msg, time, meta}) do
    Map.update! draft, "data", fn(data) ->
      put_body(data, msg)
      |> put_custom(meta)
      |> Map.put("level", level)
      |> Map.put("timestamp", time)
    end
  end

  defp put_body(data, msg) do
    Map.put(data, "body", %{"message" => %{"body" => msg}})
  end

  defp put_custom(data, meta) do
    if map_size(meta) == 0 do
      data
    else
      Map.merge(data, meta)
    end
  end
end
