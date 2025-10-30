defmodule RedditViewerWeb.RedditLive do
  use RedditViewerWeb, :live_view

  alias RedditViewer.PostProcessor
  alias Phoenix.PubSub
  alias RedditViewerWeb.Components.Functional.{TickerStatsBuilder, PitchSummaryBuilder}
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
    ticker_data = TickerStatsBuilder.build_ticker_stats(user_posts)

    # Process each ticker individually in background tasks to avoid timeouts
    # The Polygon rate limiter will handle throttling
    me = self()

    Enum.each(ticker_data, fn ticker_stat ->
      Task.start(fn ->
        Logger.info("[build_ticker_stats] Starting background task for ticker: #{ticker_stat.ticker}")
        enriched = TickerStatsBuilder.enrich_ticker_with_prices(ticker_stat)
        send(me, {:ticker_price_updated, enriched})
      end)
    end)

    ticker_data
  end


  defp build_pitch_summary(user_posts, ticker_stats) do
    PitchSummaryBuilder.build_pitch_summary(user_posts, ticker_stats)
  end
end
