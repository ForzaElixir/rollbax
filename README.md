# Rollbax

[![Build Status](https://travis-ci.org/elixir-addicts/rollbax.svg?branch=master "Build Status")](https://travis-ci.org/elixir-addicts/rollbax)
[![Hex Version](https://img.shields.io/hexpm/v/rollbax.svg "Hex Version")](https://hex.pm/packages/rollbax)
[![Deps Status](https://beta.hexfaktor.org/badge/all/github/elixir-addicts/rollbax.svg)](https://beta.hexfaktor.org/github/elixir-addicts/rollbax)

Elixir client for [Rollbar](https://rollbar.com).

## Installation

Add Rollbax as a dependency to your `mix.exs` file:

```elixir
defp deps() do
  [{:rollbax, "~> 0.6"}]
end
```

and add it to your list of applications:

```elixir
def application() do
  [applications: [:rollbax]]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies.

## Usage

Rollbax requires some configuration in order to work. For example, in `config/config.exs`:

```elixir
config :rollbax,
  access_token: "ffb8056a621f309eeb1ed87fa0c7",
  environment: "production"
```

Then, exceptions (errors, exits, and throws) can be reported to Rollbar using `Rollbax.report/3`:

```elixir
try do
  DoesNotExist.for_sure()
rescue
  exception ->
    Rollbax.report(:error, exception, System.stacktrace())
end
```

For detailed information on configuration and usage, take a look at the [online documentation](http://hexdocs.pm/rollbax).

### Logger backend

Rollbax provides a backend for Elixir's `Logger` as the `Rollbax.Logger` module. It can be configured as follows:

```elixir
# We register Rollbax.Logger as a Logger backend.
config :logger,
  backends: [Rollbax.Logger]

# We configure the Rollbax.Logger backend.
config :logger, Rollbax.Logger,
  level: :error
```

Sending logged messages to Rollbar can be disabled via `Logger` metadata:

```elixir
# To disable reporting for all subsequent logs:
Logger.metadata(rollbar: false)

# To disable reporting for the current logged message only:
Logger.error("oops", rollbar: false)
```

For more information, check out the documentation for [`Rollbax.Logger`](http://hexdocs.pm/rollbax/Rollbax.Logger.html).

### Plug and Phoenix

For examples on how to take advantage of Rollbax in Plug-based applications (including Phoenix applications), have a look at the ["Using Rollbax in Plug-based applications" page in the documentation](http://hexdocs.pm/rollbax/using-rollbax-in-plug-based-applications.html).

### Non-production reporting

For non-production environments error reporting can be either disabled completely (by setting `:enabled` to `false`) or replaced with logging of exceptions (by setting `:enabled` to `:log`).

```elixir
config :rollbax, enabled: :log
```

## Contributing

To run tests, run `$ mix test --no-start`. The `--no-start` bit is important so that tests don't fail (because of the `:rollbax` application being started without an `:access_token` specifically).

When making changes to the code, adhere to this [Elixir style guide](https://github.com/lexmag/elixir-style-guide).

Finally, thanks for contributing! :)

## License

This software is licensed under [the ISC license](LICENSE).
