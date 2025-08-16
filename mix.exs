defmodule RulesEngine.MixProject do
  use Mix.Project

  def project do
    [
      app: :rules_engine,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      test_ignore_filters: [~r"test/support"],
      description:
        "RETE-based rules engine library for Elixir with DSL parsing and IR compilation",
      source_url: "https://github.com/hl/rules_engine",
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
      ],
      dialyzer: [
        plt_add_apps: [:mix],
        flags: [:no_improper_lists]
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
      # Performance monitoring and profiling
      {:telemetry, "~> 1.3"},
      {:recon, "~> 2.5"},
      # Benchmarking
      {:benchee, "~> 1.1", only: [:dev, :test]},
      {:benchee_json, "~> 1.0", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # Static analysis with type checking
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
end
