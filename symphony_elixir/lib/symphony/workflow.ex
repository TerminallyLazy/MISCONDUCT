defmodule Symphony.Workflow do
  @derive Jason.Encoder
  defstruct config: %{}, prompt_template: "", loaded_at: nil
end
