# This file configures Credo for the project.
# See: https://hexdocs.pm/credo/config_file.html

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: ["_build/", "deps/", ".elixir_ls/"]
      },
      checks: [
        # Enable default strict checks except those that conflict with NimbleParsec style
        {Credo.Check.Readability.SinglePipe, false},
        {Credo.Check.Refactor.PipeChainStart, false}
      ]
    }
  ]
}
