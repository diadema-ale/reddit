defmodule RedditViewer.PostProcessor do
  @moduledoc """
  Service module for processing Reddit posts with caching and AI enrichment.
  """

  alias RedditViewer.{Posts, RedditAPI, OpenAIClient}
  alias RedditViewer.Posts.Post
  alias RedditViewer.Repo
  alias Phoenix.PubSub
  import Ecto.Query
  require Logger

  @doc """
  Gets a post by URL, using cache if available, otherwise fetching from Reddit and processing with AI.
  """
  def get_or_process_post_from_url(url) do
    with {:ok, post_id} <- extract_post_id_from_url(url),
         {:ok, post} <- get_or_process_post(post_id) do
      {:ok, post}
    else
      error -> error
    end
  end

  @doc """
  Gets posts by an author, using cache when available.
  """
  def get_or_process_user_posts(username, limit \\ nil) do
    # First, load ALL posts we have from DB for this author
    db_posts = Posts.list_posts_by_author(username)

    # Convert DB posts to map format
    db_posts_maps = Enum.map(db_posts, &post_to_map/1)

    # Get the most recent post ID to check if we need to fetch new ones
    most_recent_db_id =
      case db_posts do
        [] ->
          nil

        posts ->
          posts
          |> Enum.max_by(& &1.created_utc, fn -> nil end)
          |> case do
            nil -> nil
            post -> post.reddit_post_id
          end
      end

    # Now fetch from Reddit API to check for new posts
    # Use a reasonable limit for checking new posts (100 if no limit specified)
    api_limit = limit || 100

    case RedditAPI.get_user_posts(username, api_limit) do
      {:ok, reddit_posts, _after_token} ->
        # Filter out posts we already have, stopping when we hit a known post
        new_reddit_posts =
          if most_recent_db_id do
            Enum.take_while(reddit_posts, fn reddit_post ->
              Map.get(reddit_post, "id") != most_recent_db_id
            end)
          else
            reddit_posts
          end

        # Process only the new posts
        new_posts_to_process =
          new_reddit_posts
          |> Enum.map(fn reddit_post ->
            attrs = RedditAPI.reddit_post_to_db_attrs(reddit_post)

            case Posts.upsert_post(attrs) do
              {:ok, post} -> post
              {:error, _} -> nil
            end
          end)
          |> Enum.filter(& &1)

        # Process new posts for AI enrichment in the background
        new_posts_to_process
        |> Enum.each(fn post ->
          if post.ai_processed_at == nil && post.ai_processing_error == nil do
            Task.start(fn ->
              enrich_post_with_ai(post)
            end)
          end
        end)

        # Combine all posts: new posts first, then existing DB posts
        all_posts =
          new_posts_to_process
          |> Enum.map(&post_to_map/1)
          |> Kernel.++(db_posts_maps)
          |> Enum.uniq_by(fn p -> Map.get(p, "id") end)
          |> Enum.sort_by(fn p -> Map.get(p, "created_utc", 0) end, :desc)

        # Also queue AI processing for any existing posts that need it
        db_posts
        |> Enum.filter(fn post ->
          post.ai_processed_at == nil && post.ai_processing_error == nil
        end)
        |> Enum.each(fn post ->
          Task.start(fn ->
            enrich_post_with_ai(post)
          end)
        end)

        Logger.info(
          "[PostProcessor] Returning #{length(all_posts)} posts for author #{username} (#{length(db_posts_maps)} from DB, #{length(new_posts_to_process)} new)"
        )

        {:ok, all_posts}

      error ->
        # If Reddit API fails, at least return what we have in DB
        if db_posts_maps != [] do
          {:ok, db_posts_maps}
        else
          error
        end
    end
  end

  defp get_or_process_post(post_id, reddit_post_data \\ nil) do
    case Posts.get_post_by_reddit_id(post_id) do
      nil ->
        # Not in cache, need to fetch and process
        reddit_data = reddit_post_data || fetch_reddit_post(post_id)

        case reddit_data do
          {:ok, data} -> process_and_save_post(data)
          nil when reddit_post_data != nil -> process_and_save_post(reddit_post_data)
          _ -> {:error, "Failed to fetch post from Reddit"}
        end

      %Post{} = post ->
        # Found in cache, maybe enrich with AI if not already processed
        if is_nil(post.ai_processed_at) and is_nil(post.ai_processing_error) do
          enrich_post_with_ai(post)
        else
          {:ok, post_to_map(post)}
        end
    end
  end

  defp fetch_reddit_post(post_id) do
    case RedditAPI.get_post(post_id) do
      {:ok, post} -> {:ok, post}
      error -> error
    end
  end

  defp process_and_save_post(reddit_post) do
    # Convert Reddit data to DB format
    attrs = RedditAPI.reddit_post_to_db_attrs(reddit_post)

    # Save to database
    case Posts.upsert_post(attrs) do
      {:ok, post} ->
        # Enrich with AI
        enrich_post_with_ai(post)

      error ->
        Logger.error("Failed to save post: #{inspect(error)}")
        error
    end
  end

  @doc """
  Enriches a post with AI-extracted data (tickers and direction)
  """
  def enrich_post_with_ai(%Post{} = post) do
    # Combine title and text for AI analysis
    content = "#{post.title}\n\n#{post.selftext}"

    case OpenAIClient.extract_tickers(content) do
      {:ok, %{tickers: tickers, direction: direction}} ->
        # Update post with ticker information
        attrs = %{
          ticker_symbols: tickers,
          ticker_direction: direction,
          ai_processed_at: DateTime.utc_now()
        }

        case Posts.update_post(post, attrs) do
          {:ok, updated_post} ->
            # Broadcast the update
            PubSub.broadcast(RedditViewer.PubSub, "post_updates", {:post_updated, updated_post})
            {:ok, post_to_map(updated_post)}

          error ->
            error
        end

      {:error, reason} ->
        # Log the error and update the post
        Logger.error("AI processing failed for post #{post.reddit_post_id}: #{reason}")

        attrs = %{
          ai_processing_error: to_string(reason),
          ai_processed_at: DateTime.utc_now()
        }

        case Posts.update_post(post, attrs) do
          {:ok, updated_post} ->
            # Broadcast the update
            PubSub.broadcast(RedditViewer.PubSub, "post_updates", {:post_updated, updated_post})
            {:ok, post_to_map(updated_post)}

          error ->
            error
        end
    end
  end

  defp extract_post_id_from_url(url) do
    case Regex.run(~r/reddit\.com\/r\/\w+\/comments\/(\w+)/, url) do
      [_, post_id] -> {:ok, post_id}
      _ -> {:error, "Invalid Reddit URL format"}
    end
  end

  # Convert Post struct to map format expected by the UI
  @doc """
  Converts a Post struct to a map format suitable for display
  """
  def post_to_map(%Post{} = post) do
    %{
      "id" => post.reddit_post_id,
      "title" => post.title,
      "author" => post.author,
      "subreddit" => post.subreddit,
      "selftext" => post.selftext,
      "link_flair_text" => post.link_flair_text,
      "score" => post.score,
      "num_comments" => post.num_comments,
      "permalink" => post.permalink,
      "created_utc" => if(post.created_utc, do: DateTime.to_unix(post.created_utc), else: nil),
      "title_length" => post.title_length,
      "post_length" => post.post_length,
      "ticker_symbols" => post.ticker_symbols || [],
      "ticker_direction" => post.ticker_direction,
      "ai_processed_at" => post.ai_processed_at,
      "ai_processing_error" => post.ai_processing_error,
      "cached" => true
    }
  end

  @doc """
  Get all failed posts for a given author
  """
  def get_failed_posts(author) do
    Post
    |> where([p], p.author == ^author and not is_nil(p.ai_processing_error))
    |> order_by([p], desc: p.created_utc)
    |> Repo.all()
  end

  @doc """
  Retry all failed posts for a given author and return the retried posts
  """
  def retry_failed_posts(author) do
    # Get all posts with ai_processing_error for this author
    failed_posts = get_failed_posts(author)

    # Clear the error and process them again
    tasks =
      failed_posts
      |> Enum.map(fn post ->
        # Clear the error flag
        {:ok, post} =
          Posts.update_post(post, %{
            ai_processing_error: nil,
            ai_processed_at: nil
          })

        # Process asynchronously and return post id
        task = Task.async(fn ->
          enrich_post_with_ai(post)
          post.id
        end)

        {task, post.id}
      end)

    # Wait for all to complete and collect the post IDs
    post_ids =
      tasks
      |> Enum.map(fn {task, _post_id} ->
        Task.await(task, 120_000)
      end)

    # Re-fetch the posts with updated data
    retried_posts =
      post_ids
      |> Enum.map(&Repo.get!(Post, &1))

    Logger.info("[PostProcessor] Retried #{length(failed_posts)} failed posts for author: #{author}")

    retried_posts
  rescue
    e ->
      Logger.error("Error retrying failed posts: #{Exception.message(e)}")
      []
  end
end
