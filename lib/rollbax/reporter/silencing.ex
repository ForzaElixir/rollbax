defmodule Rollbax.Reporter.Silencing do
  @behaviour Rollbax.Reporter

  def handle_event(_type, _event) do
    :ignore
  end
end
