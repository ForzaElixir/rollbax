defmodule Rollbax.Reporter do
  @moduledoc """
  Behaviour to be implemented by Rollbax reporters that wish to report `:error_logger` messages to
  Rollbar. See `Rollbax.Logger` for more information.
  """

  @callback handle_event(type :: term, event :: term) :: Rollbax.Exception.t() | :next | :ignore
end
