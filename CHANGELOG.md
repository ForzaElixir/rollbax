# Changelog

## v0.8.0-dev

## v0.7.0

* Added support for blacklisting logger messages through the `:blacklist` configuration option. This way, it's possible to prevent logged messages that match a given pattern from being reported.
* Started allowing globally-set custom data: the data in the `:custom` configuration option for the `:rollbax` application is now sent alongside everything reported to Rollbax (and merged with report-specific custom data).

## v0.6.1

* Fixed a bug involving invalid unicode codepoints in `Rollbax.Logger`

## v0.6.0

* Removed `Rollbax.report/2` in favour of `Rollbax.report/3`: this new function takes the "kind" of the exception (`:error`, `:exit`, or `:throw`) so that items on Rollbar are displayed more nicely.
* Renamed `Rollbax.Notifier` to `Rollbax.Logger`.
* Started logging (with level `:error`) when the Rollbar API replies with an error.
* Started putting the metadata associated with `Logger` calls in the `"message"` part of the reported item instead of the `"custom"` data associated with it.
