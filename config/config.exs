use Mix.Config

config :ex_unit,
  assert_receive_timeout: 800,
  refute_receive_timeout: 200
