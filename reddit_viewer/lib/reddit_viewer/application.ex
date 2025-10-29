defmodule RedditViewer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RedditViewerWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:reddit_viewer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: RedditViewer.PubSub},
      # Start a worker by calling: RedditViewer.Worker.start_link(arg)
      # {RedditViewer.Worker, arg},
      # Start to serve requests, typically the last entry
      RedditViewerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RedditViewer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RedditViewerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
