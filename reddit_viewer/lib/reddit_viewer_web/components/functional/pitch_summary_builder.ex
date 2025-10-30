defmodule RedditViewerWeb.Components.Functional.PitchSummaryBuilder do
  @moduledoc """
  Builds pitch performance summary from user posts and ticker statistics.

  Calculates success rates and average returns for different trading directions.
  """

  require Logger

  @doc """
  Builds a pitch summary from user posts and ticker statistics.

  Returns a map with performance metrics for:
  - Long positions
  - Short positions
  - Neutral positions
  - Total (combined long/short)

  Each includes:
  - count: number of posts
  - right_direction: count of successful predictions
  - wrong_direction: count of failed predictions
  - avg_return_right: average return when right
  - avg_return_wrong: average return when wrong
  """
  def build_pitch_summary(user_posts, ticker_stats \\ nil) do
    # Get all posts with tickers that have been processed
    posts_with_tickers =
      user_posts
      |> Enum.filter(fn post ->
        tickers = Map.get(post, "ticker_symbols", [])
        direction = Map.get(post, "ticker_direction")
        tickers != [] && direction != nil && direction != ""
      end)

    # If no posts with tickers, return nil
    if posts_with_tickers == [] do
      nil
    else
      # Use provided ticker stats or build them if not provided
      ticker_stats_list = ticker_stats || build_ticker_stats(user_posts)

      # Create a map of ticker stats that have price data
      ticker_stats_map =
        ticker_stats_list
        |> Enum.filter(fn stat ->
          stat.return_6m != nil || (stat.return_current != nil && stat.show_current_return)
        end)
        |> Enum.map(fn stat -> {stat.ticker, stat} end)
        |> Map.new()

      Logger.debug(
        "[PitchSummary] Building with #{length(ticker_stats_list)} total tickers, #{map_size(ticker_stats_map)} tickers with price data"
      )

      # Group posts by direction and calculate stats
      grouped =
        posts_with_tickers
        |> Enum.group_by(& &1["ticker_direction"])

      # Calculate stats for each direction
      stats =
        ["long", "short", "neutral"]
        |> Enum.map(fn direction ->
          posts = Map.get(grouped, direction, [])

          if posts == [] do
            {direction,
             %{
               count: 0,
               right_direction: 0,
               wrong_direction: 0,
               avg_return_right: nil,
               avg_return_wrong: nil
             }}
          else
            # Calculate performance for each post
            post_results =
              posts
              |> Enum.map(fn post ->
                # Get performance for each ticker in the post
                ticker_returns =
                  post["ticker_symbols"]
                  |> Enum.map(fn ticker ->
                    ticker_stat = Map.get(ticker_stats_map, ticker)

                    cond do
                      ticker_stat && ticker_stat.return_6m ->
                        {ticker_stat.return_6m, :six_month}

                      ticker_stat && ticker_stat.return_current && ticker_stat.show_current_return ->
                        {ticker_stat.return_current, :current}

                      true ->
                        nil
                    end
                  end)
                  |> Enum.filter(&(&1 != nil))

                # Average return for this post (if any tickers have data)
                if ticker_returns == [] do
                  nil
                else
                  avg_return =
                    ticker_returns
                    |> Enum.map(fn {ret, _} -> ret end)
                    |> Enum.sum()
                    |> Kernel./(length(ticker_returns))

                  {avg_return, ticker_returns}
                end
              end)
              |> Enum.filter(&(&1 != nil))

            # Separate into right/wrong direction with returns
            {right_results, wrong_results} =
              post_results
              |> Enum.reduce({[], []}, fn {return_pct, _ticker_data}, {right_acc, wrong_acc} ->
                case direction do
                  "long" ->
                    if return_pct > 0 do
                      {[return_pct | right_acc], wrong_acc}
                    else
                      {right_acc, [return_pct | wrong_acc]}
                    end

                  "short" ->
                    if return_pct < 0 do
                      {[return_pct | right_acc], wrong_acc}
                    else
                      {right_acc, [return_pct | wrong_acc]}
                    end

                  _ ->
                    {right_acc, wrong_acc}
                end
              end)

            right = length(right_results)
            wrong = length(wrong_results)

            avg_return_right =
              if right_results == [] do
                nil
              else
                Float.round(Enum.sum(right_results) / length(right_results), 2)
              end

            avg_return_wrong =
              if wrong_results == [] do
                nil
              else
                Float.round(Enum.sum(wrong_results) / length(wrong_results), 2)
              end

            {direction,
             %{
               count: length(posts),
               right_direction: right,
               wrong_direction: wrong,
               avg_return_right: avg_return_right,
               avg_return_wrong: avg_return_wrong
             }}
          end
        end)
        |> Map.new()

      # Calculate totals (excluding neutrals)
      long_stats =
        Map.get(stats, "long", %{
          count: 0,
          right_direction: 0,
          wrong_direction: 0,
          avg_return_right: nil,
          avg_return_wrong: nil
        })

      short_stats =
        Map.get(stats, "short", %{
          count: 0,
          right_direction: 0,
          wrong_direction: 0,
          avg_return_right: nil,
          avg_return_wrong: nil
        })

      # Calculate weighted average returns for right/wrong
      all_right_returns = []
      all_wrong_returns = []

      # Collect all right returns
      all_right_returns =
        all_right_returns ++
          if(long_stats.avg_return_right && long_stats.right_direction > 0,
            do: List.duplicate(long_stats.avg_return_right, long_stats.right_direction),
            else: []
          )

      all_right_returns =
        all_right_returns ++
          if(short_stats.avg_return_right && short_stats.right_direction > 0,
            do: List.duplicate(short_stats.avg_return_right, short_stats.right_direction),
            else: []
          )

      # Collect all wrong returns
      all_wrong_returns =
        all_wrong_returns ++
          if(long_stats.avg_return_wrong && long_stats.wrong_direction > 0,
            do: List.duplicate(long_stats.avg_return_wrong, long_stats.wrong_direction),
            else: []
          )

      all_wrong_returns =
        all_wrong_returns ++
          if(short_stats.avg_return_wrong && short_stats.wrong_direction > 0,
            do: List.duplicate(short_stats.avg_return_wrong, short_stats.wrong_direction),
            else: []
          )

      total_avg_return_right =
        if all_right_returns == [] do
          nil
        else
          Float.round(Enum.sum(all_right_returns) / length(all_right_returns), 2)
        end

      total_avg_return_wrong =
        if all_wrong_returns == [] do
          nil
        else
          Float.round(Enum.sum(all_wrong_returns) / length(all_wrong_returns), 2)
        end

      total_stats = %{
        count: long_stats.count + short_stats.count,
        right_direction: long_stats.right_direction + short_stats.right_direction,
        wrong_direction: long_stats.wrong_direction + short_stats.wrong_direction,
        avg_return_right: total_avg_return_right,
        avg_return_wrong: total_avg_return_wrong
      }

      %{
        long:
          Map.get(stats, "long", %{
            count: 0,
            right_direction: 0,
            wrong_direction: 0,
            avg_return_right: nil,
            avg_return_wrong: nil
          }),
        short:
          Map.get(stats, "short", %{
            count: 0,
            right_direction: 0,
            wrong_direction: 0,
            avg_return_right: nil,
            avg_return_wrong: nil
          }),
        neutral:
          Map.get(stats, "neutral", %{
            count: 0,
            right_direction: 0,
            wrong_direction: 0,
            avg_return_right: nil,
            avg_return_wrong: nil
          }),
        total: total_stats
      }
    end
  end

  # Fallback ticker stats builder - should use TickerStatsBuilder module instead
  defp build_ticker_stats(user_posts) do
    RedditViewerWeb.Components.Functional.TickerStatsBuilder.build_ticker_stats(user_posts)
  end
end
