defmodule DistDb.Broadcast.Thresholds do
  @moduledoc false

  @spec for_node_count(pos_integer()) :: %{
          echo: non_neg_integer(),
          ready: non_neg_integer(),
          deliver: non_neg_integer()
        }
  def for_node_count(n) when is_integer(n) and n > 0 do
    f = max(div(n - 1, 3), 0)

    %{
      echo: n - 2 * f,
      ready: f + 1,
      deliver: 2 * f + 1
    }
  end
end
