defmodule Symphony.Workspace do
  @derive Jason.Encoder
  defstruct path: nil, workspace_key: nil, created_now: false
end
