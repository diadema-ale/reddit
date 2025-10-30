defmodule RedditViewer.Repo.Migrations.DropTickerPrices do
  use Ecto.Migration

  def up do
    drop_if_exists table(:ticker_prices)
  end

  def down do
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
