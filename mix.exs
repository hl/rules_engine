defmodule RulesEngine.MixProject do
  use Mix.Project

  def project do
    [
      app: :rules_engine,
      version: "0.1.0",
      elixir: "~> 1.19 or ~> 1.19-rc",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      description: "Pragmatic DSL-to-IR rules engine for Elixir",
      source_url: "https://github.com/your-org/rules_engine",
      docs: [
        main: "readme",
        extras: ["README.md", "SPECS.md"],
        groups_for_extras: [
          DSL: Path.wildcard("specs/dsl*.md"),
          Compiler: ["specs/compiler_ir.md", "specs/codegen_modules.md"],
          Engine: [
            "specs/agenda.md",
            "specs/refraction.md",
            "specs/performance.md",
            "specs/tracing.md"
          ]
        ]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {RulesEngine.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimble_parsec, "~> 1.4"},
      {:jason, "~> 1.4"},
      {:decimal, "~> 2.1"},
      {:jsv, "~> 0.4"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
end
