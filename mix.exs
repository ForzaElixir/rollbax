defmodule Rollbax.Mixfile do
  use Mix.Project

  @version "0.9.0"

  @default_api_endpoint "https://api.rollbar.com/api/1/item/"

  def project() do
    [
      app: :rollbax,
      version: @version,
      elixir: "~> 1.3",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "Exception tracking and logging from Elixir to Rollbar",
      package: package(),
      deps: deps(),
      aliases: [test: "test --no-start"],
      name: "Rollbax",
      docs: [
        main: "Rollbax",
        source_ref: "v#{@version}",
        source_url: "https://github.com/elixir-addicts/rollbax",
        extras: ["pages/Using Rollbax in Plug-based applications.md"]
      ]
    ]
  end

  def application() do
    [applications: [:logger, :hackney, :jason], env: env(), mod: {Rollbax, []}]
  end

  defp deps() do
    [
      {:hackney, "~> 1.1"},
      {:jason, "~> 1.0"},
      {:ex_doc, "~> 0.18", only: :dev},
      {:plug, "~> 1.4", only: :test},
      {:cowboy, "~> 1.1", only: :test}
    ]
  end

  defp package() do
    [
      maintainers: ["Aleksei Magusev", "Andrea Leopardi", "Eric Meadows-Jönsson"],
      licenses: ["ISC"],
      links: %{"GitHub" => "https://github.com/elixir-addicts/rollbax"}
    ]
  end

  defp env() do
    [
      enabled: true,
      custom: %{},
      api_endpoint: @default_api_endpoint,
      enable_crash_reports: false,
      reporters: [Rollbax.Reporter.Standard]
    ]
  end
end
