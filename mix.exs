defmodule Rollbax.Mixfile do
  use Mix.Project

  def project() do
    [app: :rollbax,
     version: "0.5.4",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description(),
     package: package(),
     deps: deps()]
  end

  def application() do
    [applications: [:logger, :hackney, :poison],
     mod: {Rollbax, []}]
  end

  defp deps() do
    [{:hackney, "~> 1.1"},
     {:poison,  "~> 1.4 or ~> 2.0"},

     {:ex_doc, ">= 0.0.0", only: :docs},
     {:earmark, ">= 0.0.0", only: :docs},

     {:plug,   "~> 0.13.0", only: :test},
     {:cowboy, "~> 1.0.0", only: :test}]
  end

  defp description() do
    "Exception tracking and logging from Elixir to Rollbar"
  end

  defp package() do
    [maintainers: ["Aleksei Magusev"],
     licenses: ["ISC"],
     links: %{"GitHub" => "https://github.com/elixir-addicts/rollbax"}]
  end
end
