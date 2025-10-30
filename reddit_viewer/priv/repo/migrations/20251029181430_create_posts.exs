defmodule RedditViewer.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      # Reddit data
      add :reddit_post_id, :string, null: false
      add :title, :string, null: false
      add :author, :string, null: false
      add :subreddit, :string, null: false
      add :selftext, :text
      add :link_flair_text, :string
      add :score, :integer
      add :num_comments, :integer
      add :permalink, :string
      add :created_utc, :utc_datetime

      # Calculated fields
      add :title_length, :integer
      add :post_length, :integer

      # AI enrichments
      add :ticker_symbols, {:array, :string}, default: []
      add :ai_processed_at, :utc_datetime
      add :ai_processing_error, :text

      # Raw Reddit API response
      add :raw_data, :map

      timestamps()
    end

    create unique_index(:posts, [:reddit_post_id])
    create index(:posts, [:author])
    create index(:posts, [:subreddit])
    create index(:posts, [:ai_processed_at])
  end
end
