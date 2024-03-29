defmodule Oracleex.Type do
  @moduledoc """
  Type conversions.
  """

  @typedoc "Input param."
  @type param :: bitstring()
    | number()
    | date()
    | time()
    | datetime()
    | NaiveDateTime.t()
    | DateTime.t()
    | Date.t()
    | Decimal.t()

  @typedoc "Output value."
  @type return_value :: bitstring()
    | integer()
    | NaiveDateTime.t()
    | Decimal.t()

  @typedoc "Date as `{year, month, day}`"
  @type date :: {1..9_999, 1..12, 1..31}

  @typedoc "Time as `{hour, minute, sec, usec}`"
  @type time :: {0..24, 0..60, 0..60, 0..999_999}

  @typedoc "Datetime"
  @type datetime :: {date(), time()}

  @doc """
  Transforms input params into `:odbc` params.
  """
  @spec encode(value :: param(), opts :: Keyword.t) ::
    {:odbc.odbc_data_type(), [:odbc.value()]}
  def encode(value, _) when is_boolean(value) do
    {:sql_bit, [value]}
  end

  def encode(%Date{} = date, _) do
    date |> Date.to_erl |> encode(nil)
  end
  def encode(%DateTime{} = date_time, _) do
    date_time |> DateTime.to_naive() |> NaiveDateTime.to_erl() |> encode(nil)
  end
  def encode(%NaiveDateTime{} = date_time, _) do
    date_time |> NaiveDateTime.to_erl() |> encode(nil)
  end

  def encode({_year, _month, _day} = date, _) do
    encoded = Date.from_erl!(date)
    |> to_string
    |> :unicode.characters_to_binary(:unicode, :latin1)
    {{:sql_varchar, String.length(encoded)}, [encoded]}
  end

  def encode({hour, minute, sec, usec}, _) do
    precision = if usec == 0, do: 0, else: 6
    encoded = Time.from_erl!({hour, minute, sec}, {usec, precision})
    |> to_string
    |> :unicode.characters_to_binary(:unicode, :latin1)
    {{:sql_varchar, String.length(encoded)}, [encoded]}
  end

  def encode({{year, month, day}, {hour, minute, sec}}, _) do
    encode({{year, month, day}, {hour, minute, sec, 0}}, nil)
  end

  def encode({{year, month, day}, {hour, minute, sec, usec}}, _) do
    precision = if usec == 0, do: 0, else: 6
    encoded = NaiveDateTime.from_erl!(
      {{year, month, day}, {hour, minute, sec}}, {usec, precision})
    |> to_string
    |> :unicode.characters_to_binary(:unicode, :latin1)

    {{:sql_varchar, String.length(encoded)}, [encoded]}
  end

  def encode(value, _) when is_integer(value)
  and (value > -1_000_000_000)
  and (value < 1_000_000_000) do
    {:sql_integer, [value]}
  end

  def encode(value, _) when is_integer(value) do
    encoded = value |> to_string |> :unicode.characters_to_binary(:unicode, :latin1)
    {{:sql_varchar, String.length(encoded)}, [encoded]}
  end

  def encode(value, _) when is_float(value) do
    encoded = value |> to_string |> :unicode.characters_to_binary(:unicode, :latin1)
    {{:sql_varchar, String.length(encoded)}, [encoded]}
  end

  def encode(%Decimal{} = value, _) do
    encoded = value |> to_string |> :unicode.characters_to_binary(:unicode, :latin1)
    {{:sql_varchar, String.length(encoded)}, [encoded]}
  end

  def encode(value, _) when is_binary(value) do
    with utf16 when is_bitstring(utf16) <-
      :unicode.characters_to_binary(value, :unicode, {:utf16, :little})
    do
      {{:sql_wvarchar, byte_size(value)}, [utf16]}
    else
      _ -> raise %Oracleex.Error{
        message: "failed to convert string to UTF16LE"}
    end
  end

  def encode(nil, _) do
    {:sql_integer, [:null]}
  end

  def encode(value, _) do
    raise %Oracleex.Error{
      message: "could not parse param #{inspect value} of unrecognised type."}
  end

  @doc """
  Transforms `:odbc` return values to Elixir representations.
  """
  @spec decode(:odbc.value(), opts :: Keyword.t) :: return_value()

  def decode(value, _) when is_float(value) do
    int_val = Kernel.round(value)
    if int_val == value do
      int_val
    else
      Decimal.from_float(value)
    end
  end

  def decode(value, opts) when is_binary(value) do
    if opts[:preserve_encoding] || String.printable?(value) do
      value
    else
      :unicode.characters_to_binary(value, {:utf16, :little}, :unicode)
    end
  end

  def decode(value, _) when is_list(value) do
    to_string(value)
  end

  def decode(:null, _) do
    nil
  end

  def decode({date, {h, m, s}}, _) do
    {date, {h, m, s}} |> NaiveDateTime.from_erl!()
  end

  def decode(value, _) do
    value
  end
end
