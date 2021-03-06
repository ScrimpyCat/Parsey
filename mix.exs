defmodule Parsey.Mixfile do
    use Mix.Project

    def project do
        [
            app: :parsey,
            description: "A library to parse non-complex nested inputs with a given ruleset.",
            version: "0.0.3",
            elixir: "~> 1.2",
            build_embedded: Mix.env == :prod,
            start_permanent: Mix.env == :prod,
            deps: deps(),
            package: package()
        ]
    end

    # Configuration for the OTP application
    #
    # Type "mix help compile.app" for more information
    def application do
        [applications: [:logger]]
    end

    # Dependencies can be Hex packages:
    #
    #   {:mydep, "~> 0.3.0"}
    #
    # Or git/path repositories:
    #
    #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
    #
    # Type "mix help deps" for more examples and options
    defp deps do
        if Version.compare(System.version, "1.7.0") == :lt do
            [
                { :earmark, "~> 0.1", only: :dev },
                { :ex_doc, "~> 0.7", only: :dev }
            ]
        else
            [
                { :ex_doc, "~> 0.19", only: :dev, runtime: false }
            ]
        end
    end

    defp package do
        [
            maintainers: ["Stefan Johnson"],
            licenses: ["BSD 2-Clause"],
            links: %{ "GitHub" => "https://github.com/ScrimpyCat/Parsey" }
        ]
    end
end
