defmodule RedditViewer.PolygonClient do
  @moduledoc """
  Client for interacting with the Polygon.io API for stock market data.
  All requests are rate-limited to 10 requests per second.
  """

  require Logger

  @polygon_base_url "https://api.polygon.io"
  @polygon_api_key "6sSz3nR7_19MqaXPp2hAfcY3g1Wl8NCe"

  @doc """
  Get daily bars (OHLC) for a ticker between two dates
  """
  def get_daily_bars(ticker, from_date, to_date) do
    # Acquire rate limit token before making request
    :ok = RedditViewer.RateLimiter.Polygon.acquire_token()

    url = "#{@polygon_base_url}/v2/aggs/ticker/#{ticker}/range/1/day/#{from_date}/#{to_date}"

    Logger.debug("[Polygon] Fetching bars for #{ticker} from #{from_date} to #{to_date}")

    headers = []

    params = [
      apiKey: @polygon_api_key,
      adjusted: true,
      sort: "asc",
      limit: 200
    ]

    case Req.get(url, headers: headers, params: params) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        Logger.debug("[Polygon] Got successful response for #{ticker}")
        parse_bars_response(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Polygon API error: #{status} - #{inspect(body)}")
        {:error, "API returned status #{status}"}

      {:error, reason} ->
        Logger.error("Request to Polygon failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Get the price for a specific date or the most recent prior trading day
  """
  def get_price_on_or_before_date(ticker, target_date) do
    # Convert date to Date struct
    date =
      case target_date do
        %Date{} = d -> d
        str when is_binary(str) -> Date.from_iso8601!(str)
        _ -> target_date |> to_string() |> Date.from_iso8601!()
      end

    # Go back 30 days to ensure we catch the last trading day
    from_date = Date.add(date, -30) |> Date.to_iso8601()
    to_date = Date.to_iso8601(date)

    case get_daily_bars(ticker, from_date, to_date) do
      {:ok, bars} when bars != [] ->
        # Get the last bar (most recent up to target date)
        last_bar = List.last(bars)
        price = Map.get(last_bar, "c")
        actual_date = format_timestamp_to_date(Map.get(last_bar, "t"))

        {:ok, price, actual_date}

      {:ok, []} ->
        {:error, "No price data found"}

      error ->
        error
    end
  end

  @doc """
  Get price data for calculating forward returns
  """
  def get_price_after_months(ticker, start_date, months) do
    # Convert to Date if needed
    start =
      case start_date do
        %Date{} = d -> d
        str when is_binary(str) -> Date.from_iso8601!(str)
      end

    # Calculate target date (approximately months forward)
    # Using 30 days per month approximation
    target_date = Date.add(start, months * 30)

    # Get data from a bit before to a bit after the target date
    from_date = Date.add(target_date, -10) |> Date.to_iso8601()
    to_date = Date.add(target_date, 10) |> Date.to_iso8601()

    case get_daily_bars(ticker, from_date, to_date) do
      {:ok, bars} when bars != [] ->
        # Find the bar closest to target date
        target_unix =
          DateTime.new!(target_date, ~T[00:00:00], "Etc/UTC") |> DateTime.to_unix(:millisecond)

        closest_bar =
          bars
          |> Enum.min_by(fn bar ->
            abs(Map.get(bar, "t") - target_unix)
          end)

        price = Map.get(closest_bar, "c")
        actual_date_str = format_timestamp_to_date(Map.get(closest_bar, "t"))

        {:ok, price, actual_date_str}

      {:ok, []} ->
        # If no data in range, get the most recent available
        get_most_recent_price(ticker)

      error ->
        error
    end
  end

  @doc """
  Get the most recent price available for a ticker
  """
  def get_most_recent_price(ticker) do
    # Get last 30 days of data
    to_date = Date.utc_today() |> Date.to_iso8601()
    from_date = Date.utc_today() |> Date.add(-30) |> Date.to_iso8601()

    case get_daily_bars(ticker, from_date, to_date) do
      {:ok, bars} when bars != [] ->
        last_bar = List.last(bars)
        price = Map.get(last_bar, "c")
        date_str = format_timestamp_to_date(Map.get(last_bar, "t"))

        {:ok, price, date_str}

      _ ->
        {:error, "No recent price data found"}
    end
  end

  @doc """
  Calculate forward return percentage
  """
  def calculate_return(start_price, end_price) when start_price > 0 do
    ((end_price - start_price) / start_price * 100) |> Float.round(2)
  end

  def calculate_return(_, _), do: nil

  defp parse_bars_response(%{"status" => "OK", "resultsCount" => 0}) do
    Logger.debug("[Polygon] No data available for ticker")
    {:ok, []}
  end

  defp parse_bars_response(%{"status" => "OK", "results" => results}) when is_list(results) do
    Logger.debug("[Polygon] Parsed #{length(results)} bars from response")
    {:ok, results}
  end

  defp parse_bars_response(%{"status" => "ERROR", "error" => error}) do
    Logger.error("[Polygon] API returned error: #{error}")
    {:error, error}
  end

  defp parse_bars_response(response) do
    Logger.error("[Polygon] Unexpected response format: #{inspect(response)}")
    {:error, "Unexpected response format"}
  end

  defp format_timestamp_to_date(timestamp_ms) when is_integer(timestamp_ms) do
    timestamp_ms
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp format_timestamp_to_date(_), do: nil
end
