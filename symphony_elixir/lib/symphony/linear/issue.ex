defmodule Symphony.Linear.Issue do
  @derive Jason.Encoder
  defstruct id: nil,
            identifier: nil,
            title: nil,
            description: nil,
            workspace_path: nil,
            repository_path: nil,
            priority: nil,
            state: nil,
            branch_name: nil,
            url: nil,
            labels: [],
            blocked_by: [],
            created_at: nil,
            updated_at: nil
end
