# Oracleex

Adapter to Oracle. Using `DBConnection` and `ODBC`.

It connects to [Ecto](https://github.com/elixir-ecto/ecto) with [OracleEcto](https://github.com/MikeAlbertFleetSolutions/oracle_ecto).

Based on [findmypast-oss/mssqlex](https://github.com/findmypast-oss/mssqlex)

## Installation

Oracleex requires the [Erlang ODBC application](http://erlang.org/doc/man/odbc.html) to be installed.
This might require the installation of an additional package depending on how you have installed
Erlang (e.g. on Ubuntu `sudo apt-get install erlang-odbc`).

Oracleex depends on Oracle's ODBC Driver.  See the Dockerfile for how to install.

## Testing

Tests require an instance of Oracle to be running on `localhost` and the appropriate environment
variables to be set.  See the docker-compose file for details

### To start the database:

```bash
docker-compose start db
```

### To open a shell at the app root:

```bash
docker-compose run oracleex
```

### To run the unit tests:

```bash
mix deps.get
mix test
```
