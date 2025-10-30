defmodule RedditViewer.Repo do
  use Ecto.Repo,
    otp_app: :reddit_viewer,
    adapter: Ecto.Adapters.Postgres
end
