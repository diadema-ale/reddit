defmodule RedditViewerWeb.Components.UI.ProgressBar do
  @moduledoc """
  Component for displaying fetch progress with different states.

  ## Examples

      <UI.ProgressBar
        status={:fetching}
        message="Fetching posts from Reddit..."
        posts_fetched={42}
        oldest_date="Jan 15, 2024"
        newest_date="Oct 30, 2024"
      />
  """
  use Phoenix.Component
  import RedditViewerWeb.CoreComponents

  attr :status, :atom, default: :fetching, values: [:fetching, :complete, :error]
  attr :message, :string, required: true
  attr :posts_fetched, :integer, default: 0
  attr :oldest_date, :string, default: nil
  attr :newest_date, :string, default: nil
  attr :class, :string, default: ""

  def progress_bar(assigns) do
    ~H"""
    <div class={[
      "bg-blue-50 border border-blue-200 rounded-lg p-4",
      @class
    ]}>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <%= case @status do %>
            <% :fetching -> %>
              <.icon name="hero-arrow-path" class="size-5 text-blue-600 animate-spin" />
              <span class="text-blue-800 font-medium">Fetching Historical Posts</span>
            <% :complete -> %>
              <.icon name="hero-check-circle" class="size-5 text-green-600" />
              <span class="text-green-800 font-medium">Fetch Complete</span>
            <% :error -> %>
              <.icon name="hero-exclamation-circle" class="size-5 text-red-600" />
              <span class="text-red-800 font-medium">Fetch Error</span>
          <% end %>
          <span class="text-sm text-gray-600">{@message}</span>
        </div>
        <div class="text-sm text-gray-500">
          <span class="font-medium">{@posts_fetched}</span>
          posts
          <%= if @oldest_date && @newest_date do %>
            <span class="mx-1">·</span>
            <span class="text-gray-600">
              from {@oldest_date} to {@newest_date}
            </span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
