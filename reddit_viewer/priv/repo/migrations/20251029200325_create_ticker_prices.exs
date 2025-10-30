defmodule RedditViewer.Repo.Migrations.CreateTickerPrices do
  use Ecto.Migration

  def change do
    create table(:ticker_prices) do
      add :ticker, :string, null: false
      add :date, :date, null: false
      add :price, :decimal
      add :fetched_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:ticker_prices, [:ticker, :date])
    create index(:ticker_prices, :ticker)
    create index(:ticker_prices, :date)
  end
end
