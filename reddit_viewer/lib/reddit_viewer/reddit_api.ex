defmodule RedditViewer.RedditAPI do
  @moduledoc """
  Module to interact with Reddit API
  """

  @reddit_base_url "https://oauth.reddit.com"
  @reddit_auth_url "https://www.reddit.com/api/v1/access_token"
  @user_agent "elixir:reddit_viewer:v1.0.0 (by /u/obi)"

  # Rate limiting: 100 QPM, we'll stay under 50
  @rate_limit_delay 1200 # 1.2 seconds between requests to stay under 50 QPM

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

  def get_user_posts(username, limit \\ 25) do
    # Add delay for rate limiting
    Process.sleep(@rate_limit_delay)

    case get_access_token() do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"User-Agent", @user_agent}
        ]

        url = "#{@reddit_base_url}/user/#{username}/submitted?limit=#{limit}&sort=new"

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"data" => %{"children" => posts}}} ->
                posts = Enum.map(posts, fn %{"data" => post} -> post end)
                {:ok, posts}
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

  def format_title(title, max_length \\ 50) do
    if String.length(title) > max_length do
      String.slice(title, 0, max_length) <> "..."
    else
      title
    end
  end
end
