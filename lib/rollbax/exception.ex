defmodule Rollbax.Exception do
  @type t :: %__MODULE__{
    class: String.t,
    message: String.t,
    stacktrace: Exception.stacktrace,
    custom: map,
    occurrence_data: map,
  }

  defstruct [
    :class,
    :message,
    :stacktrace,
    custom: %{},
    occurrence_data: %{},
  ]
end
