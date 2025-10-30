defmodule RedditViewer.RedditAPI do
  @moduledoc """
  Module to interact with Reddit API
  """

  require Logger

  @reddit_base_url "https://oauth.reddit.com"
  @reddit_auth_url "https://www.reddit.com/api/v1/access_token"
  @user_agent "elixir:reddit_viewer:v1.0.0 (by /u/obi)"

  # Rate limiting: 100 QPM, we'll stay under 50
  # 1.2 seconds between requests to stay under 50 QPM
  @rate_limit_delay 1200

  def get_access_token do
    app_id = System.get_env("REDDIT_APP_ID") || "3CciIDCSNUsgUuwfkls2NQ"
    app_secret = System.get_env("REDDIT_APP_SECRET") || "YGe_-Xyw4n4_7dAxI5jOwGabUDPMfQ"

    auth_string = Base.encode64("#{app_id}:#{app_secret}")

    headers = [
      {"Authorization", "Basic #{auth_string}"},
      {"User-Agent", @user_agent},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    body = "grant_type=client_credentials"

    case HTTPoison.post(@reddit_auth_url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"access_token" => token}} -> {:ok, token}
          _ -> {:error, "Failed to parse token response"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "Auth failed with status: #{status_code}"}

      {:error, error} ->
        {:error, "Request failed: #{inspect(error)}"}
    end
  end

  def get_post_from_url(url) do
    # Extract post ID from URL
    # URL format: https://www.reddit.com/r/subreddit/comments/post_id/title/
    case parse_reddit_url(url) do
      {:ok, post_id} ->
        get_post(post_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_reddit_url(url) do
    case Regex.run(~r/reddit\.com\/r\/\w+\/comments\/(\w+)/, url) do
      [_, post_id] -> {:ok, post_id}
      _ -> {:error, "Invalid Reddit URL format"}
    end
  end

  def get_post(post_id) do
    # Add delay for rate limiting
    Process.sleep(@rate_limit_delay)

    case get_access_token() do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"User-Agent", @user_agent}
        ]

        url = "#{@reddit_base_url}/api/info?id=t3_#{post_id}"

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"data" => %{"children" => [%{"data" => post} | _]}}} ->
                {:ok, post}

              {:ok, %{"data" => %{"children" => []}}} ->
                {:error, "Post not found"}

              _ ->
                {:error, "Failed to parse post response"}
            end

          {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
            {:error, "Failed to get post: #{status_code} - #{body}"}

          {:error, error} ->
            {:error, "Request failed: #{inspect(error)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_user_posts(username, limit \\ 100, after_token \\ nil) do
    # Add delay for rate limiting
    Process.sleep(@rate_limit_delay)

    case get_access_token() do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"User-Agent", @user_agent}
        ]

        base_url = "#{@reddit_base_url}/user/#{username}/submitted?limit=#{limit}&sort=new"
        url = if after_token, do: "#{base_url}&after=#{after_token}", else: base_url

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"data" => %{"children" => posts, "after" => after_val}}} ->
                posts = Enum.map(posts, fn %{"data" => post} -> post end)
                Logger.info("[RedditAPI] get_user_posts for #{username}: found #{length(posts)} posts, next_after=#{inspect(after_val)}")
                {:ok, posts, after_val}

              _ ->
                {:error, "Failed to parse user posts response"}
            end

          {:ok, %HTTPoison.Response{status_code: 404}} ->
            {:error, "User not found"}

          {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
            {:error, "Failed to get user posts: #{status_code} - #{body}"}

          {:error, error} ->
            {:error, "Request failed: #{inspect(error)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def calculate_post_length(post) do
    selftext = Map.get(post, "selftext", "")
    String.length(selftext)
  end

  def calculate_title_length(post) do
    title = Map.get(post, "title", "")
    String.length(title)
  end

  def format_title(title, max_length \\ 50) do
    if String.length(title) > max_length do
      String.slice(title, 0, max_length) <> "..."
    else
      title
    end
  end

  @doc """
  Converts Reddit API post data to a format suitable for database storage
  """
  def reddit_post_to_db_attrs(reddit_post) do
    title = Map.get(reddit_post, "title", "")
    selftext = Map.get(reddit_post, "selftext", "")

    %{
      reddit_post_id: Map.get(reddit_post, "id"),
      title: title,
      author: Map.get(reddit_post, "author"),
      subreddit: Map.get(reddit_post, "subreddit"),
      selftext: selftext,
      link_flair_text: Map.get(reddit_post, "link_flair_text"),
      score: Map.get(reddit_post, "score", 0),
      num_comments: Map.get(reddit_post, "num_comments", 0),
      permalink: Map.get(reddit_post, "permalink"),
      created_utc: reddit_post |> Map.get("created_utc", 0) |> round() |> DateTime.from_unix!(),
      raw_data: reddit_post,
      title_length: String.length(title),
      post_length: String.length(selftext)
    }
  end
end
