defmodule RedditViewer.Posts do
  @moduledoc """
  The Posts context for managing cached Reddit posts and AI enrichments.
  """

  import Ecto.Query, warn: false
  alias RedditViewer.Repo
  alias RedditViewer.Posts.Post

  @doc """
  Gets a single post by reddit post ID.

  Returns `nil` if the Post does not exist.

  ## Examples

      iex> get_post_by_reddit_id("abc123")
      %Post{}

      iex> get_post_by_reddit_id("unknown")
      nil

  """
  def get_post_by_reddit_id(reddit_post_id) do
    Repo.get_by(Post, reddit_post_id: reddit_post_id)
  end

  @doc """
  Creates a post.

  ## Examples

      iex> create_post(%{field: value})
      {:ok, %Post{}}

      iex> create_post(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_post(attrs \\ %{}) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a post.

  ## Examples

      iex> update_post(post, %{field: new_value})
      {:ok, %Post{}}

      iex> update_post(post, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates or updates a post based on the reddit_post_id.
  """
  def upsert_post(attrs) do
    case get_post_by_reddit_id(attrs["reddit_post_id"] || attrs[:reddit_post_id]) do
      nil -> create_post(attrs)
      post -> update_post(post, attrs)
    end
  end

  @doc """
  Returns the list of posts.

  ## Examples

      iex> list_posts()
      [%Post{}, ...]

  """
  def list_posts do
    Repo.all(Post)
  end

  @doc """
  Returns posts by a specific author.

  ## Examples

      iex> list_posts_by_author("username")
      [%Post{}, ...]

  """
  def list_posts_by_author(author) do
    Post
    |> where([p], p.author == ^author)
    |> order_by([p], desc: p.created_utc)
    |> Repo.all()  # No limit - returns ALL posts for the author
  end

  @doc """
  Deletes a post.

  ## Examples

      iex> delete_post(post)
      {:ok, %Post{}}

      iex> delete_post(post)
      {:error, %Ecto.Changeset{}}

  """
  def delete_post(%Post{} = post) do
    Repo.delete(post)
  end
end
