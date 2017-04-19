# Using Rollbax in Plug-based applications

[Plug](https://github.com/elixir-lang/plug) provides the `Plug.ErrorHandler` plug which plays very well with Rollbax. As you can see in [the documentation for `Plug.ErrorHandler`](https://hexdocs.pm/plug/Plug.ErrorHandler.html), this plug can be used to "catch" exceptions that happen inside a given plug and act on them. This can be used to report all exceptions happening in that plug to Rollbar. For example:

```elixir
defmodule MyApp.Router do
  use Plug.Router # or `use MyApp.Web, :router` for Phoenix apps
  use Plug.ErrorHandler

  defp handle_errors(conn, %{kind: kind, reason: reason, stack: stacktrace}) do
    Rollbax.report(kind, reason, stacktrace)
  end
end
```

Rollbax also supports attaching *metadata* to a reported exception as well as overriding Rollbar data for a reported exception. Both these can be used to have more detailed reports. For example, in the code snippet below, we could report the request parameters as metadata to be attached to the exception:

```elixir
defp handle_errors(conn, %{kind: kind, reason: reason, stack: stacktrace}) do
  Rollbax.report(kind, reason, stacktrace, %{params: conn.params})
end
```

Since Rollbar supports the concept of "request" and "server" in the [Item POST API](https://rollbar.com/docs/api/items_post/), a lot of data that Rollbar will be able to understand can be attached to a reported exceptions. To add data about the host, the request, and more to the exception reported in the snippet below, you could do something like this:

```elixir
defp handle_errors(conn, %{kind: kind, reason: reason, stack: stacktrace}) do
  conn =
    conn
    |> Plug.Conn.fetch_cookies()
    |> Plug.Conn.fetch_query_params()

  conn_data = %{
    "request" => %{
      "cookies" => conn.req_cookies,
      "url" => "#{conn.scheme}://#{conn.host}:#{conn.port}#{conn.request_path}",
      "user_ip" => (conn.remote_ip |> Tuple.to_list() |> Enum.join(".")),
      "headers" => Enum.into(conn.req_headers, %{}),
      "params" => conn.params,
      "method" => conn.method,
    },
    "server" => %{
      "pid" => System.get_env("MY_SERVER_PID"),
      "host" => "#{System.get_env("MY_HOSTNAME")}:#{System.get_env("MY_PORT")}",
      "root" => System.get_env("MY_APPLICATION_PATH"),
    },
  }

  Rollbax.report(kind, reason, stacktrace, %{}, conn_data)
end
```

Check the [documentation for the Rollbar API](https://rollbar.com/docs/api/items_post/) for all the supported values that can form a "request".

## Sensitive data

In the examples above, *all* parameters are fetched from the connection and forwarded to Rollbar (in the `"params"` key); this means that any sensitive data such as passwords or authentication keys will be sent to Rollbar as well. A good idea may be to scrub any sensitive data out of the parameters before reporting errors to Rollbar. For example:

```elixir
defp handle_errors(conn, error) do
  conn =
    conn
    |> Plug.Conn.fetch_cookies()
    |> Plug.Conn.fetch_query_params()

  params =
    for {key, _value} = tuple <- conn.params do
      if key in ["password", "password_confirmation"] do
        {key, "[FILTERED]"}
      else
        tuple
      end
    end

  # Same as the examples above
end
```
