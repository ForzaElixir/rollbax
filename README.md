# Rollbax

[![Build Status](https://travis-ci.org/elixir-addicts/rollbax.svg?branch=master "Build Status")](https://travis-ci.org/elixir-addicts/rollbax)
[![Hex Version](https://img.shields.io/hexpm/v/rollbax.svg "Hex Version")](https://hex.pm/packages/rollbax)

Elixir client for [Rollbar](https://rollbar.com).

## Installation

Add Rollbax as a dependency to your `mix.exs` file:

```elixir
defp deps() do
  [{:rollbax, ">= 0.0.0"}]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies. Add `:rollbax` to your list of `:applications` if you're not using `:extra_applications`.

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

### Crash reports

Rollbax provides a way to automatically report crashes from OTP processes (GenServers, Tasks, and so on). It can be enabled with:

```elixir
config :rollbax, enable_crash_reports: true
```

For more information, check out the documentation for [`Rollbax.Logger`](http://hexdocs.pm/rollbax/Rollbax.Logger.html).
If you had previously configured `Rollbax.Logger` to be a Logger backend (for example `config :logger, backends: [Rollbax.Logger]`), you will need to remove since `Rollbax.Logger` is not a Logger backend anymore and you will get crashes if you use it as such.

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
