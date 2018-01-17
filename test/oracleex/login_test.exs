defmodule Oracleex.LoginTest do
  use ExUnit.Case, async: false

  alias Oracleex.Result

  test "Given valid details, connects to database" do
    assert {:ok, pid} = Oracleex.start_link([scrollable_cursors: :off])
    assert {:ok, _, %Result{num_rows: 1, rows: [["test"]]}} =
      Oracleex.query(pid, "SELECT 'test' from dual", [])
  end

  test "Given invalid details, errors" do
    Process.flag(:trap_exit, true)

    assert {:ok, pid} = Oracleex.start_link([password: "badpassword", scrollable_cursors: :off])
    assert_receive {:EXIT, ^pid,
                    %Oracleex.Error{odbc_code: :invalid_authorization}}, 5_000
  end
end
