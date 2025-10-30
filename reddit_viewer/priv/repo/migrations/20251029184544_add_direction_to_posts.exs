defmodule RedditViewer.Repo.Migrations.AddDirectionToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :ticker_direction, :string
    end
  end
end
