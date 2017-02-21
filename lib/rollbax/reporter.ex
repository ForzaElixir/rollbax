defmodule Rollbax.Reporter do
  @callback handle_event(type :: term, event :: term) ::
            Rollbax.Exception.t | :skip | :ignore
end
