defmodule RedditViewerWeb.Components.UI.AIStatus do
  @moduledoc """
  Component for displaying AI processing status for posts.

  Shows different states:
  - Processing (with spinner)
  - Failed (with error indicator)
  - Processed with tickers (with direction-based coloring)
  - Processed without tickers

  ## Examples

      <UI.AIStatus
        processing_error={@post.ai_processing_error}
        processed_at={@post.ai_processed_at}
        tickers={@post.ticker_symbols}
        direction={@post.ticker_direction}
      />
  """
  use Phoenix.Component
  import RedditViewerWeb.CoreComponents

  attr :processing_error, :string, default: nil
  attr :processed_at, :any, default: nil
  attr :tickers, :list, default: []
  attr :direction, :string, default: nil
  attr :max_display, :integer, default: 3, doc: "Maximum tickers to display before showing +N"

  def ai_status(assigns) do
    ~H"""
    <%= cond do %>
      <% @processing_error != nil -> %>
        <div class="flex items-center gap-2">
          <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800">
            <.icon name="hero-exclamation-triangle" class="size-3 mr-1" /> Failed
          </span>
        </div>
      <% @processed_at == nil -> %>
        <div class="flex items-center gap-1">
          <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800">
            <.icon name="hero-arrow-path" class="size-3 mr-1 animate-spin" /> Processing...
          </span>
        </div>
      <% @tickers != [] -> %>
        <% badge_colors = get_direction_colors(@direction) %>
        <div class="flex flex-wrap gap-1">
          <%= for ticker <- Enum.take(@tickers, @max_display) do %>
            <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{badge_colors}"}>
              ${ticker}
            </span>
          <% end %>
          <%= if length(@tickers) > @max_display do %>
            <span class="text-xs text-gray-400">+{length(@tickers) - @max_display}</span>
          <% end %>
        </div>
      <% true -> %>
        <span class="text-gray-400 text-xs">No tickers</span>
    <% end %>
    """
  end

  defp get_direction_colors(direction) do
    case direction do
      "long" -> "bg-green-100 text-green-800"
      "short" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end
end
