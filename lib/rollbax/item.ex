defmodule Rollbax.Item do
  def draft(token, envt) do
    {:ok, host} = :inet.gethostname
    %{"access_token" => token,
      "data" => %{
        "server" => %{
          "host" => List.to_string(host)},
        "environment" => envt,
        "language"  => "Elixir",
        "framework" => "OTP"}}
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
end
