defmodule OuterfacesOdd.MixProject do
  use Mix.Project

  @github_url "https://github.com/outerfaces/outerfaces_ex_odd"

  def project do
    [
      app: :outerfaces_odd,
      version: "0.2.4",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Outerfaces ODD (Outerfaces Dependency Distribution) -- Extensions for Outerfaces framework",
      name: "Outerfaces Dependency Distribution (ODD)",
      source_url: @github_url,
      package: package(),
      docs: [
        main: "readme",
        extras: ["README.md"] ++ Path.wildcard("guides/*.md")
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:outerfaces, "~> 0.2.4"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Aligned To Development - development@alignedto.dev"],
      licenses: ["MIT"],
      links: %{"GitHub" => @github_url}
    ]
  end

  defp aliases do
    [
      docs: ["docs"]
    ]
  end
end
