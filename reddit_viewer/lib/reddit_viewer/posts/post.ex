defmodule RedditViewer.Posts.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    # Reddit data
    field(:reddit_post_id, :string)
    field(:title, :string)
    field(:author, :string)
    field(:subreddit, :string)
    field(:selftext, :string)
    field(:link_flair_text, :string)
    field(:score, :integer)
    field(:num_comments, :integer)
    field(:permalink, :string)
    field(:created_utc, :utc_datetime)

    # Calculated fields
    field(:title_length, :integer)
    field(:post_length, :integer)

    # AI enrichments
    # ticker_symbols can be:
    # - [] (empty array) if processed but no tickers found
    # - [] with ai_processed_at = nil if not yet processed
    # - ["AAPL", "MSFT"] if tickers were found
    field(:ticker_symbols, {:array, :string}, default: [])
    # Direction of the stock pitch: "long", "short", "neutral", "n/a"
    field(:ticker_direction, :string)
    # Set when AI processing completes (success or no tickers)
    field(:ai_processed_at, :utc_datetime)
    # Set when AI processing fails
    field(:ai_processing_error, :string)

    # Raw Reddit API response
    field(:raw_data, :map)

    timestamps()
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :reddit_post_id,
      :title,
      :author,
      :subreddit,
      :selftext,
      :link_flair_text,
      :score,
      :num_comments,
      :permalink,
      :created_utc,
      :title_length,
      :post_length,
      :ticker_symbols,
      :ticker_direction,
      :ai_processed_at,
      :ai_processing_error,
      :raw_data
    ])
    |> validate_required([:reddit_post_id, :title, :author, :subreddit])
    |> unique_constraint(:reddit_post_id)
    |> calculate_lengths()
  end

  defp calculate_lengths(changeset) do
    title = get_field(changeset, :title)
    selftext = get_field(changeset, :selftext)

    changeset
    |> put_change(:title_length, if(title, do: String.length(title), else: 0))
    |> put_change(:post_length, if(selftext, do: String.length(selftext), else: 0))
  end
end
