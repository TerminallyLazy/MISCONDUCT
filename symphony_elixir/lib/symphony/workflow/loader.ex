defmodule Symphony.Workflow.Loader do
  alias Symphony.Workflow

  def load(path) do
    case File.read(Path.expand(path)) do
      {:ok, body} -> parse(body)
      {:error, _} -> {:error, :missing_workflow_file}
    end
  end

  def parse("---\n" <> rest), do: parse_front(rest)
  def parse("---\r\n" <> rest), do: parse_front(rest)

  def parse(body),
    do:
      {:ok,
       %Workflow{config: %{}, prompt_template: String.trim(body), loaded_at: DateTime.utc_now()}}

  defp parse_front(rest) do
    case :binary.split(rest, ["\n---\n", "\r\n---\r\n"], []) do
      [yaml, prompt] ->
        case YamlElixir.read_from_string(yaml) do
          {:ok, nil} ->
            {:ok,
             %Workflow{
               config: %{},
               prompt_template: String.trim(prompt),
               loaded_at: DateTime.utc_now()
             }}

          {:ok, map} when is_map(map) ->
            {:ok,
             %Workflow{
               config: stringify(map),
               prompt_template: String.trim(prompt),
               loaded_at: DateTime.utc_now()
             }}

          {:ok, _} ->
            {:error, :workflow_front_matter_not_a_map}

          {:error, e} ->
            {:error, {:workflow_parse_error, e}}
        end

      _ ->
        {:error, :workflow_parse_error}
    end
  rescue
    e -> {:error, {:workflow_parse_error, Exception.message(e)}}
  end

  defp stringify(m) when is_map(m), do: Map.new(m, fn {k, v} -> {to_string(k), stringify(v)} end)
  defp stringify(l) when is_list(l), do: Enum.map(l, &stringify/1)
  defp stringify(v), do: v
end
