defmodule RedditViewerWeb.Components.Functional.TickerStatsBuilder do
  @moduledoc """
  Builds ticker statistics from user posts.

  Extracts ticker symbols from posts and enriches them with price data.
  """

  require Logger
  alias RedditViewer.PolygonClient

  @doc """
  Builds ticker statistics from a list of user posts.

  Returns a list of ticker stats sorted by first mention date (newest first).
  Each stat includes:
  - ticker symbol
  - first mention date
  - direction (long/short/neutral)
  - posts count
  - price data (fetched asynchronously)
  """
  def build_ticker_stats(user_posts) do
    Logger.debug("[TickerStatsBuilder] Building stats for #{length(user_posts)} posts")

    # Group posts by ticker and find first mention
    ticker_data =
      user_posts
      |> Enum.filter(fn post ->
        tickers = Map.get(post, "ticker_symbols", [])
        tickers != nil && tickers != []
      end)
      |> Enum.flat_map(fn post ->
        tickers = Map.get(post, "ticker_symbols", [])
        direction = Map.get(post, "ticker_direction")
        created_utc = Map.get(post, "created_utc")

        Enum.map(tickers, fn ticker ->
          {ticker, %{
            direction: direction,
            created_utc: created_utc,
            post_id: Map.get(post, "id")
          }}
        end)
      end)
      |> Enum.group_by(fn {ticker, _} -> ticker end, fn {_, data} -> data end)
      |> Enum.map(fn {ticker, mentions} ->
        # Find first mention
        first_mention = Enum.min_by(mentions, & &1.created_utc)

        %{
          ticker: ticker,
          first_mention_date: DateTime.from_unix!(round(first_mention.created_utc)) |> DateTime.to_date(),
          direction: first_mention.direction,
          posts_count: length(mentions),
          price_on_date: nil,
          price_date: nil,
          price_6m_later: nil,
          price_6m_date: nil,
          return_6m: nil,
          current_price: nil,
          current_price_date: nil,
          return_current: nil,
          show_current_return: false,
          loading: true
        }
      end)
      |> Enum.sort_by(& &1.first_mention_date, {:desc, Date})

    # Log the sorted order for debugging
    Logger.debug("[TickerStatsBuilder] Ticker order after sorting:")
    Enum.each(ticker_data, fn stat ->
      Logger.debug("  #{stat.ticker}: #{Date.to_iso8601(stat.first_mention_date)}")
    end)

    ticker_data
  end

  @doc """
  Enriches a ticker stat with price data from Polygon.

  Fetches:
  - Price on first mention date
  - Price 6 months later
  - Current price (if within 6 months)
  - Calculates returns
  """
  def enrich_ticker_with_prices(ticker_stat) do
    Logger.debug("[enrich_ticker_with_prices] Starting price fetch for ticker: #{ticker_stat.ticker}")

    # Get price on first mention date
    {price_on_date, price_date} =
      case PolygonClient.get_price_on_or_before_date(ticker_stat.ticker, ticker_stat.first_mention_date) do
        {:ok, price, date} ->
          Logger.debug("[enrich_ticker_with_prices] Got price for #{ticker_stat.ticker}: $#{price} on #{date}")
          {price, date}
        {:error, reason} ->
          Logger.error("[enrich_ticker_with_prices] Failed to get price for #{ticker_stat.ticker}: #{inspect(reason)}")
          {nil, nil}
      end

    # Get price 6 months later
    {price_6m_later, price_6m_date} =
      if price_on_date do
        case PolygonClient.get_price_after_months(ticker_stat.ticker, ticker_stat.first_mention_date, 6) do
          {:ok, price, date} -> {price, date}
          {:error, _} -> {nil, nil}
        end
      else
        {nil, nil}
      end

    # Calculate return
    return_6m =
      if price_on_date && price_6m_later do
        PolygonClient.calculate_return(price_on_date, price_6m_later)
      else
        nil
      end

    # Check if 6 months have passed
    today = Date.utc_today()
    six_months_later = Date.add(ticker_stat.first_mention_date, 180)
    show_current_return = Date.compare(today, six_months_later) == :lt

    # Get current price if needed
    {current_price, current_price_date, return_current} =
      if show_current_return && price_on_date do
        case PolygonClient.get_most_recent_price(ticker_stat.ticker) do
          {:ok, price, date} ->
            return = PolygonClient.calculate_return(price_on_date, price)
            {price, date, return}
          _ ->
            {nil, nil, nil}
        end
      else
        {nil, nil, nil}
      end

    %{ticker_stat |
      price_on_date: price_on_date,
      price_date: price_date,
      price_6m_later: price_6m_later,
      price_6m_date: price_6m_date,
      return_6m: return_6m,
      current_price: current_price,
      current_price_date: current_price_date,
      return_current: return_current,
      show_current_return: show_current_return,
      loading: false
    }
  end
end
