# Changelog

## v0.6.0-dev

* Remove `Rollbax.report/2` in favour of `Rollbax.report/3`: this new function takes the "kind" of the exception (`:error`, `:exit`, or `:throw`) so that items on Rollbar are displayed more nicely.
* Rename `Rollbax.Notifier` to `Rollbax.Logger`.
* Log (with level `:error`) when the Rollbar API replies with an error, and log the error.
* Put the metadata associated with `Logger` calls in the `"message"` part of the reported item instead of the `"custom"` data associated with it.
