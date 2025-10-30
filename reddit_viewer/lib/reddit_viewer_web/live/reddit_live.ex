defmodule RedditViewerWeb.RedditLive do
  use RedditViewerWeb, :live_view

  alias RedditViewer.PostProcessor
  alias Phoenix.PubSub
  require Logger

  @impl true
  def mount(params, _session, socket) do
    # Subscribe to post updates
    PubSub.subscribe(RedditViewer.PubSub, "post_updates")

    socket =
      socket
      |> assign(:reddit_url, params["reddit_url"] || "")
      |> assign(:post, nil)
      |> assign(:user_posts, [])
      |> assign(:error, nil)
      |> assign(:loading, false)
      |> assign(:fetch_progress, nil)
      |> assign(:current_author, nil)
      |> assign(:view_mode, :posts)  # :posts or :tickers
      |> assign(:ticker_stats, [])
      |> assign(:pitch_summary, nil)

    # If we have a URL, load it
    if params["reddit_url"] && params["reddit_url"] != "" do
      send(self(), {:load_reddit_url, params["reddit_url"]})
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    reddit_url = params["reddit_url"] || ""

    socket =
      if reddit_url != socket.assigns.reddit_url && reddit_url != "" do
        Logger.info("[RedditLive] Loading new URL: #{reddit_url}")
        send(self(), {:load_reddit_url, reddit_url})

        # Clear old data when loading a new URL
        socket
        |> assign(:reddit_url, reddit_url)
        |> assign(:post, nil)
        |> assign(:user_posts, [])
        |> assign(:ticker_stats, [])
        |> assign(:pitch_summary, nil)
        |> assign(:loading, true)
        |> assign(:current_author, nil)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:load_reddit_url, url}, socket) do
    socket = assign(socket, :loading, true)
    liveview_pid = self()

    # Start the loading process in a separate task
    Task.start(fn ->
      case PostProcessor.get_or_process_post_from_url(url) do
        {:ok, post} ->
          # Send the post back to the LiveView
          send(liveview_pid, {:post_loaded, post})

          # Load user posts - no limit, get all posts
          case PostProcessor.get_or_process_user_posts(
                 Map.get(post, "author")
               ) do
            {:ok, user_posts} ->
              send(liveview_pid, {:user_posts_loaded, user_posts})

            {:error, reason} ->
              send(liveview_pid, {:user_posts_error, reason})
          end

        {:error, reason} ->
          send(liveview_pid, {:post_error, reason})
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:post_loaded, post}, socket) do
    author = Map.get(post, "author")

    # Subscribe to historical fetch progress for this author
    if socket.assigns.current_author != author do
      # Unsubscribe from previous author
      if socket.assigns.current_author do
        PubSub.unsubscribe(RedditViewer.PubSub, "historical_fetch:#{socket.assigns.current_author}")
      end

      # Subscribe to new author
      PubSub.subscribe(RedditViewer.PubSub, "historical_fetch:#{author}")

      # Start historical fetch
      RedditViewer.HistoricalFetcher.fetch_historical_posts(author)
    end

    {:noreply,
     socket
     |> assign(:post, post)
     |> assign(:error, nil)
     |> assign(:current_author, author)}
  end

  @impl true
  def handle_info({:user_posts_loaded, user_posts}, socket) do
    Logger.info("[RedditLive] User posts loaded: #{length(user_posts)} posts for author: #{socket.assigns.current_author}")

    # Always build ticker stats to start fetching price data early
    ticker_stats = build_ticker_stats(user_posts)

    socket =
      socket
      |> assign(:user_posts, user_posts)
      |> assign(:ticker_stats, ticker_stats)
      |> assign(:loading, false)

    # Don't build pitch summary yet - wait until we have ticker price data
    socket = assign(socket, :pitch_summary, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:post_error, reason}, socket) do
    {:noreply,
     socket
     |> assign(:post, nil)
     |> assign(:user_posts, [])
     |> assign(:error, "Failed to load post: #{reason}")
     |> assign(:loading, false)}
  end

  @impl true
  def handle_info({:user_posts_error, reason}, socket) do
    {:noreply,
     socket
     |> assign(:error, "Failed to load user posts: #{reason}")
     |> assign(:loading, false)}
  end

  @impl true
  def handle_info({:post_updated, updated_post}, socket) do
    # Update the specific post in our lists
    updated_post_map = PostProcessor.post_to_map(updated_post)

    # Update main post if it matches
    socket =
      if socket.assigns.post && Map.get(socket.assigns.post, "id") == updated_post.reddit_post_id do
        assign(socket, :post, updated_post_map)
      else
        socket
      end

    # Update user posts list
    user_posts =
      Enum.map(socket.assigns.user_posts, fn post ->
        if Map.get(post, "id") == updated_post.reddit_post_id do
          updated_post_map
        else
          post
        end
      end)

    # Update ticker stats if in tickers view
    socket =
      if socket.assigns.view_mode == :tickers do
        # Rebuild ticker stats to include any new posts
        ticker_stats = build_ticker_stats(user_posts)
        pitch_summary = build_pitch_summary(user_posts, ticker_stats)
        socket
        |> assign(:user_posts, user_posts)
        |> assign(:ticker_stats, ticker_stats)
        |> assign(:pitch_summary, pitch_summary)
      else
        # Don't rebuild pitch summary in posts view unless we have ticker stats with price data
        if socket.assigns.ticker_stats != [] &&
           Enum.any?(socket.assigns.ticker_stats, fn stat ->
             stat.price_on_date != nil || (stat.return_current != nil && stat.show_current_return)
           end) do
          pitch_summary = build_pitch_summary(user_posts, socket.assigns.ticker_stats)
          socket
          |> assign(:user_posts, user_posts)
          |> assign(:pitch_summary, pitch_summary)
        else
          assign(socket, :user_posts, user_posts)
        end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:fetch_progress, progress}, socket) do
    {:noreply, assign(socket, :fetch_progress, progress)}
  end

  @impl true
  def handle_info({:new_post_saved, new_post}, socket) do
    # Add the new post to the user_posts list if it's not already there
    updated_user_posts =
      if Enum.any?(socket.assigns.user_posts, fn p -> Map.get(p, "id") == Map.get(new_post, "id") end) do
        socket.assigns.user_posts
      else
        # Insert at the beginning since it's likely newer
        [new_post | socket.assigns.user_posts]
        |> Enum.sort_by(fn p -> Map.get(p, "created_utc", 0) end, :desc)
      end

    # Update ticker stats if in ticker view and the new post has tickers
    socket =
      if socket.assigns.view_mode == :tickers && Map.get(new_post, "ticker_symbols", []) != [] do
        # Rebuild to include new tickers
        ticker_stats = build_ticker_stats(updated_user_posts)
        socket
        |> assign(:user_posts, updated_user_posts)
        |> assign(:ticker_stats, ticker_stats)
      else
        assign(socket, :user_posts, updated_user_posts)
      end

    # Update pitch summary only if we have ticker price data
    socket =
      if socket.assigns.ticker_stats != [] &&
         Enum.any?(socket.assigns.ticker_stats, fn stat ->
           stat.price_on_date != nil || (stat.return_current != nil && stat.show_current_return)
         end) do
        pitch_summary = build_pitch_summary(updated_user_posts, socket.assigns.ticker_stats)
        assign(socket, :pitch_summary, pitch_summary)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:ticker_price_updated, updated_ticker}, socket) do
    # Update the ticker in our list
    Logger.info("[ticker_price_updated] Received update for ticker: #{updated_ticker.ticker}, has price data: #{updated_ticker.price_on_date != nil}")

    updated_stats =
      socket.assigns.ticker_stats
      |> Enum.map(fn ticker ->
        if ticker.ticker == updated_ticker.ticker do
          updated_ticker
        else
          ticker
        end
      end)
      |> Enum.sort_by(& &1.first_mention_date, {:desc, Date})  # Maintain sort order

    # Log to verify sort order is maintained
    Logger.info("[ticker_price_updated] Updated ticker order - first 5:")
    updated_stats |> Enum.take(5) |> Enum.each(fn stat ->
      Logger.info("  #{stat.ticker}: #{Date.to_iso8601(stat.first_mention_date)}")
    end)

    # Rebuild pitch summary with updated ticker data
    pitch_summary =
      if socket.assigns.user_posts != [] do
        build_pitch_summary(socket.assigns.user_posts, updated_stats)
      else
        nil
      end

    {:noreply,
     socket
     |> assign(:ticker_stats, updated_stats)
     |> assign(:pitch_summary, pitch_summary)}
  end

  @impl true
  def handle_event("search", %{"search" => %{"reddit_url" => url}}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?reddit_url=#{url}")}
  end

  @impl true
  def handle_event("toggle_view", %{"view" => view}, socket) do
    Logger.info("[toggle_view] Switching to view: #{view}")
    view_mode = String.to_atom(view)
    socket = assign(socket, :view_mode, view_mode)

    # Update pitch summary if we have ticker price data
    socket =
      if socket.assigns.user_posts != [] && socket.assigns.ticker_stats != [] &&
         Enum.any?(socket.assigns.ticker_stats, fn stat ->
           stat.price_on_date != nil || (stat.return_current != nil && stat.show_current_return)
         end) do
        pitch_summary = build_pitch_summary(socket.assigns.user_posts, socket.assigns.ticker_stats)
        assign(socket, :pitch_summary, pitch_summary)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("retry_failed", %{"author" => author}, socket) do
    liveview_pid = self()

    # Start the retry in the background
    Task.start(fn ->
      PostProcessor.retry_failed_posts(author)
    end)

    # Refresh the user posts to show the updated status
    if socket.assigns.post do
      Task.start(fn ->
        Process.sleep(100) # Small delay to allow DB updates
        case PostProcessor.get_or_process_user_posts(author, 25) do
          {:ok, user_posts} ->
            send(liveview_pid, {:user_posts_loaded, user_posts})
          _ ->
            :ok
        end
      end)
    end

    {:noreply, put_flash(socket, :info, "Retrying failed posts...")}
  end

  defp build_ticker_stats(user_posts) do
    Logger.info("[build_ticker_stats] Building stats for #{length(user_posts)} posts")

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
    Logger.info("[build_ticker_stats] Ticker order after sorting:")
    Enum.each(ticker_data, fn stat ->
      Logger.info("  #{stat.ticker}: #{Date.to_iso8601(stat.first_mention_date)}")
    end)

    # Process tickers with controlled concurrency
    me = self()

    # Process each ticker individually in background tasks to avoid timeouts
    # The Polygon rate limiter will handle throttling
    Logger.info("[build_ticker_stats] Processing #{length(ticker_data)} tickers for price data")

    Enum.each(ticker_data, fn ticker_stat ->
      Task.start(fn ->
        Logger.info("[build_ticker_stats] Starting background task for ticker: #{ticker_stat.ticker}")
        enriched = enrich_ticker_with_prices(ticker_stat)
        send(me, {:ticker_price_updated, enriched})
      end)
    end)

    ticker_data
  end

  defp enrich_ticker_with_prices(ticker_stat) do
    alias RedditViewer.PolygonClient

    Logger.info("[enrich_ticker_with_prices] Starting price fetch for ticker: #{ticker_stat.ticker}")

    # Get price on first mention date
    {price_on_date, price_date} =
      case PolygonClient.get_price_on_or_before_date(ticker_stat.ticker, ticker_stat.first_mention_date) do
        {:ok, price, date} ->
          Logger.info("[enrich_ticker_with_prices] Got price for #{ticker_stat.ticker}: $#{price} on #{date}")
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

  defp build_pitch_summary(user_posts, ticker_stats \\ nil) do
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
      ticker_stats_map = ticker_stats_list
        |> Enum.filter(fn stat ->
          stat.return_6m != nil || (stat.return_current != nil && stat.show_current_return)
        end)
        |> Enum.map(fn stat -> {stat.ticker, stat} end)
        |> Map.new()

      Logger.info("[PitchSummary] Building with #{length(ticker_stats_list)} total tickers, #{map_size(ticker_stats_map)} tickers with price data")

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
            {direction, %{
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
                  |> Enum.filter(& &1 != nil)

                # Average return for this post (if any tickers have data)
                if ticker_returns == [] do
                  nil
                else
                  avg_return = ticker_returns
                    |> Enum.map(fn {ret, _} -> ret end)
                    |> Enum.sum()
                    |> Kernel./(length(ticker_returns))

                  {avg_return, ticker_returns}
                end
              end)
              |> Enum.filter(& &1 != nil)

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

            {direction, %{
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
      long_stats = Map.get(stats, "long", %{count: 0, right_direction: 0, wrong_direction: 0, avg_return_right: nil, avg_return_wrong: nil})
      short_stats = Map.get(stats, "short", %{count: 0, right_direction: 0, wrong_direction: 0, avg_return_right: nil, avg_return_wrong: nil})

      # Calculate weighted average returns for right/wrong
      all_right_returns = []
      all_wrong_returns = []

      # Collect all right returns
      all_right_returns =
        all_right_returns ++
        if(long_stats.avg_return_right && long_stats.right_direction > 0,
          do: List.duplicate(long_stats.avg_return_right, long_stats.right_direction),
          else: [])

      all_right_returns =
        all_right_returns ++
        if(short_stats.avg_return_right && short_stats.right_direction > 0,
          do: List.duplicate(short_stats.avg_return_right, short_stats.right_direction),
          else: [])

      # Collect all wrong returns
      all_wrong_returns =
        all_wrong_returns ++
        if(long_stats.avg_return_wrong && long_stats.wrong_direction > 0,
          do: List.duplicate(long_stats.avg_return_wrong, long_stats.wrong_direction),
          else: [])

      all_wrong_returns =
        all_wrong_returns ++
        if(short_stats.avg_return_wrong && short_stats.wrong_direction > 0,
          do: List.duplicate(short_stats.avg_return_wrong, short_stats.wrong_direction),
          else: [])

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
        long: Map.get(stats, "long", %{count: 0, right_direction: 0, wrong_direction: 0, avg_return_right: nil, avg_return_wrong: nil}),
        short: Map.get(stats, "short", %{count: 0, right_direction: 0, wrong_direction: 0, avg_return_right: nil, avg_return_wrong: nil}),
        neutral: Map.get(stats, "neutral", %{count: 0, right_direction: 0, wrong_direction: 0, avg_return_right: nil, avg_return_wrong: nil}),
        total: total_stats
      }
    end
  end
end
