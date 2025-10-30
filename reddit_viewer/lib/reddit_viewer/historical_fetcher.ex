defmodule RedditViewer.HistoricalFetcher do
  @moduledoc """
  Fetches historical posts for a user going back up to 2 years
  """
  use GenServer
  alias Phoenix.PubSub
  alias RedditViewer.{RedditAPI, PostProcessor, Repo, Posts.Post}
  require Logger
  import Ecto.Query

  @fetch_interval 2000 # 2 seconds between fetches
  @batch_size 25
  @five_years_ago_unix 157_680_000 # 5 years in seconds (365.25 * 5 * 24 * 60 * 60)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def fetch_historical_posts(username) do
    GenServer.cast(__MODULE__, {:fetch_historical, username})
  end

  def get_progress do
    GenServer.call(__MODULE__, :get_progress)
  end

  # Server callbacks
  def init(_opts) do
    {:ok, %{
      current_fetch: nil,
      progress: %{}
    }}
  end

  def handle_cast({:fetch_historical, username}, state) do
    # Cancel any existing fetch for this user
    if state.current_fetch && state.current_fetch.username == username do
      Process.cancel_timer(state.current_fetch.timer_ref)
    end

    # Count existing posts just for informational purposes
    post_count =
      Post
      |> where([p], p.author == ^username)
      |> Repo.aggregate(:count, :id)

    initial_state = %{
      posts_fetched: 0,  # Start counting from 0 for new fetches
    }

    message = "Fetching all historical posts for #{username} (#{post_count} already in DB)..."

    Logger.info("[HistoricalFetcher] Starting historical fetch for #{username}, #{post_count} posts already in DB")

    # Start fetch
    timer_ref = Process.send_after(self(), {:fetch_batch, username, nil, initial_state.posts_fetched}, 100)

    new_state = %{state |
      current_fetch: Map.merge(%{
        username: username,
        timer_ref: timer_ref,
        start_time: System.monotonic_time(:second)
      }, initial_state),
      progress: Map.put(state.progress, username, %{
        status: :fetching,
        posts_fetched: initial_state.posts_fetched,
        oldest_date: nil,
        newest_date: nil,
        message: message
      })
    }

    broadcast_progress(username, new_state.progress[username])

    {:noreply, new_state}
  end

  def handle_call(:get_progress, _from, state) do
    {:reply, state.progress, state}
  end

  def handle_info({:fetch_batch, username, after_token, total_fetched}, state) do
    Logger.info("[HistoricalFetcher] Fetching batch for #{username}, after: #{inspect(after_token)}, total fetched so far: #{total_fetched}")

    case RedditAPI.get_user_posts(username, @batch_size, after_token) do
      {:ok, posts, next_after} ->
        Logger.info("[HistoricalFetcher] Got #{length(posts)} posts from Reddit API")

        # Process ALL posts - let the database handle duplicates with upsert
        if posts != [] do
          process_posts_batch(posts)
        end

        # Get the oldest post timestamp to check if we should continue
        oldest_post = List.last(posts)
        oldest_timestamp = if oldest_post, do: Map.get(oldest_post, "created_utc", 0), else: 0
        current_time = System.system_time(:second)
        five_years_ago = current_time - @five_years_ago_unix

        new_total = total_fetched + length(posts)

        # Update progress
        oldest_date = format_timestamp(oldest_timestamp)
        newest_date = get_in(state, [:progress, username, :newest_date]) || format_timestamp(System.system_time(:second))

        progress = %{
          status: :fetching,
          posts_fetched: new_total,
          oldest_date: oldest_date,
          newest_date: newest_date,
          message: "Fetching posts from #{oldest_date}... (#{new_total} posts so far)"
        }

        new_state = put_in(state, [:progress, username], progress)
        broadcast_progress(username, progress)

        # Continue fetching if:
        # 1. We have a next page token
        # 2. We got posts in this batch
        # 3. We haven't reached 5 years ago
        should_continue = next_after && posts != [] && oldest_timestamp > five_years_ago

        Logger.info("[HistoricalFetcher] Continue check: next_after=#{inspect(next_after)}, posts_count=#{length(posts)}, oldest_timestamp=#{oldest_timestamp}, five_years_ago=#{five_years_ago}, should_continue=#{should_continue}")

        if should_continue do
          timer_ref = Process.send_after(self(), {:fetch_batch, username, next_after, new_total}, @fetch_interval)
          new_state = put_in(new_state, [:current_fetch, :timer_ref], timer_ref)
          {:noreply, new_state}
        else
          # Fetch complete
          complete_message =
            cond do
              oldest_timestamp <= five_years_ago ->
                "Fetched all posts back to 5 years ago (#{new_total} posts total)"
              posts == [] ->
                "No more posts available (#{new_total} posts total)"
              !next_after ->
                "Reached end of available posts (#{new_total} posts total)"
              true ->
                "Fetch complete (#{new_total} posts total)"
            end

          final_progress = %{progress |
            status: :complete,
            message: complete_message
          }
          new_state = put_in(new_state, [:progress, username], final_progress)
          broadcast_progress(username, final_progress)

          {:noreply, %{new_state | current_fetch: nil}}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch posts for #{username}: #{inspect(reason)}")

        prev_progress = get_in(state, [:progress, username]) || %{}
        progress = %{
          status: :error,
          posts_fetched: total_fetched,
          oldest_date: Map.get(prev_progress, :oldest_date),
          newest_date: Map.get(prev_progress, :newest_date),
          message: "Error fetching posts: #{reason}"
        }

        new_state = put_in(state, [:progress, username], progress)
        broadcast_progress(username, progress)

        {:noreply, %{new_state | current_fetch: nil}}
    end
  end

  defp process_posts_batch(posts) do
    # Save posts and queue for AI processing
    Enum.each(posts, fn reddit_post ->
      Task.start(fn ->
        attrs = RedditAPI.reddit_post_to_db_attrs(reddit_post)

        case RedditViewer.Posts.upsert_post(attrs) do
          {:ok, post} ->
            # Broadcast that a new post has been saved
            PubSub.broadcast(
              RedditViewer.PubSub,
              "historical_fetch:#{post.author}",
              {:new_post_saved, PostProcessor.post_to_map(post)}
            )

            if post.ai_processed_at == nil && post.ai_processing_error == nil do
              Task.start(fn ->
                PostProcessor.enrich_post_with_ai(post)
              end)
            end

          {:error, error} ->
            Logger.error("Failed to save post: #{inspect(error)}")
        end
      end)
    end)
  end

  defp broadcast_progress(username, progress) do
    PubSub.broadcast(
      RedditViewer.PubSub,
      "historical_fetch:#{username}",
      {:fetch_progress, progress}
    )
  end

  defp format_timestamp(unix_timestamp) do
    case DateTime.from_unix(round(unix_timestamp)) do
      {:ok, datetime} ->
        Calendar.strftime(datetime, "%b %d, %Y")
      _ ->
        "unknown"
    end
  end
end
