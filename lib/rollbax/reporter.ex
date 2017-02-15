defmodule Rollbax.Reporter do
  @callback handle_event(type :: term, event :: term) ::
            Rollbax.Exception.t | :noop | :dont_report
end
