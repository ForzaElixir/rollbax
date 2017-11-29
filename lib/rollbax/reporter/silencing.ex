defmodule Rollbax.Reporter.Silencing do
  @moduledoc """
  A `Rollbax.Reporter` that ignores all messages that go through it.
  """

  @behaviour Rollbax.Reporter

  def handle_event(_type, _event) do
    :ignore
  end
end
