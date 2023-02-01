defmodule Oracleex.Mixfile do
  use Mix.Project

  def project do
    [
      app: :oracleex,
      version: "0.2.0",
      description: "Adapter to Oracle. Using DBConnection and ODBC.",
      elixir: "~> 1.4",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :odbc]]
  end

  defp deps do
    [
      {:db_connection, "~> 2.4.0"},
      {:decimal, "~> 2.0"}
    ]
  end
end
