defmodule Symphony.Http.Json do
  def encode!(v), do: Jason.encode!(to_json(v))
  def to_json(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def to_json(%MapSet{} = s), do: MapSet.to_list(s)
  def to_json(%_{} = s), do: s |> Map.from_struct() |> to_json()
  def to_json(m) when is_map(m), do: Map.new(m, fn {k, v} -> {k, to_json(v)} end)
  def to_json(l) when is_list(l), do: Enum.map(l, &to_json/1)
  def to_json(v), do: v
end
