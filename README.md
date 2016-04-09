# Rollbax

[![Build Status](https://travis-ci.org/elixir-addicts/rollbax.svg?branch=master "Build Status")](https://travis-ci.org/elixir-addicts/rollbax)
[![Hex Version](https://img.shields.io/hexpm/v/rollbax.svg "Hex Version")](https://hex.pm/packages/rollbax)


This is an Elixir client for the Rollbar service.

## Installation

Add Rollbax as a dependency to your `mix.exs` file:

```elixir
def application() do
  [applications: [:rollbax]]
end

defp deps() do
  [{:rollbax, "~> 0.5"}]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies.

### Configuration

It requires `access_token` and `environment` parameters to be set
in your application environment, usually defined in your `config/config.exs`:

```elixir
config :rollbax,
  access_token: "ffb8056a621f309eeb1ed87fa0c7",
  environment: "production"
```

## Usage

```elixir
try do
  DoesNotExist.for_sure()
rescue
  exception ->
    Rollbax.report(exception, System.stacktrace())
end
```

### Notifier for Logger

There is a Logger backend to send logs to the Rollbar,
which could be configured as follows:

```elixir
config :logger,
  backends: [Rollbax.Notifier]

config :logger, Rollbax.Notifier,
  level: :error
```

The Rollbax log sending can be disabled by using Logger metadata:

```elixir
Logger.metadata(rollbar: false)
# For a single call
Logger.error("oops", rollbar: false)
```

### Plug and Phoenix

The [`Plug.ErrorHandler` plug](https://hexdocs.pm/plug/Plug.ErrorHandler.html) can be used to send
error reports inside a web request.

In your router:

```elixir
defmodule MyApp.Router do
  use Plug.Router # Or `use MyApp.Web, :router` for Phoenix apps
  use Plug.ErrorHandler

  # Reports the exception and re-raises it
  defp handle_errors(conn, %{kind: _kind, reason: reason, stack: stack}) do
    Rollbax.report(reason, stack, %{params: conn.params})
  end
end
```

### Non-production reporting

For non-production environments error reporting
can be disabled or turned into logging:

```elixir
config :rollbax, enabled: :log
```

## License

This software is licensed under [the ISC license](LICENSE).
