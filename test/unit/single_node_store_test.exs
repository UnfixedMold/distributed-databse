defmodule DistDb.SingleNodeStoreTest do
  use ExUnit.Case, async: false
  import DistDb.TestSupport

  setup do
    :ok = Application.stop(:dist_db)
    {:ok, _} = Application.ensure_all_started(:dist_db)
    :sys.replace_state(DistDb.Broadcast, fn _ -> %{messages: %{}} end)
    DistDb.Store.clear()
    :ok
  end

  describe "single-node store" do
    test "put and get" do
      assert :ok = DistDb.Store.put("key", "value")
      eventually(fn -> assert DistDb.Store.get("key") == "value" end)
    end

    test "update value" do
      assert :ok = DistDb.Store.put("counter", 1)
      eventually(fn -> assert DistDb.Store.get("counter") == 1 end)

      assert :ok = DistDb.Store.put("counter", 2)
      eventually(fn -> assert DistDb.Store.get("counter") == 2 end)
    end

    test "delete key" do
      assert :ok = DistDb.Store.put("temp", "value")
      eventually(fn -> assert DistDb.Store.get("temp") == "value" end)

      assert :ok = DistDb.Store.delete("temp")
      eventually(fn -> assert DistDb.Store.get("temp") == nil end)
    end

    test "list_all" do
      assert :ok = DistDb.Store.put("a", 1)
      assert :ok = DistDb.Store.put("b", 2)

      eventually(fn -> assert %{"a" => 1, "b" => 2} = DistDb.Store.list_all() end)
    end
  end
end
