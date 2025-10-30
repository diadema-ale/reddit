defmodule RedditViewerWeb.PageController do
  use RedditViewerWeb, :controller

  alias RedditViewer.PostProcessor

  def home(conn, params) do
    # Check if we have a URL parameter
    case Map.get(params, "reddit_url") do
      nil ->
        # Just show the form
        render(conn, :home,
          reddit_url: "",
          post: nil,
          user_posts: [],
          error: nil
        )

      "" ->
        # Empty URL submitted
        render(conn, :home,
          reddit_url: "",
          post: nil,
          user_posts: [],
          error: "Please enter a Reddit post URL"
        )

      url ->
        # Process the Reddit URL using PostProcessor (handles caching and AI enrichment)
        case PostProcessor.get_or_process_post_from_url(url) do
          {:ok, post} ->
            # Get the author's posts
            author = Map.get(post, "author", "")

            case PostProcessor.get_or_process_user_posts(author) do
              {:ok, user_posts} ->
                render(conn, :home,
                  reddit_url: url,
                  post: post,
                  user_posts: user_posts,
                  error: nil
                )

              {:error, reason} ->
                # Show post but with error for user posts
                render(conn, :home,
                  reddit_url: url,
                  post: post,
                  user_posts: [],
                  error: "Failed to load user posts: #{reason}"
                )
            end

          {:error, reason} ->
            render(conn, :home,
              reddit_url: url,
              post: nil,
              user_posts: [],
              error: "Failed to load post: #{reason}"
            )
        end
    end
  end

  def retry_failed(conn, %{"author" => author}) do
    # Retry all failed posts for this author
    case PostProcessor.retry_failed_posts(author) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Retrying failed posts...")
        |> redirect(to: ~p"/")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to retry: #{reason}")
        |> redirect(to: ~p"/")
    end
  end
end
