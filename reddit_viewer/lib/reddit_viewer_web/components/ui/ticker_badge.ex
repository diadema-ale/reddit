defmodule RedditViewerWeb.Components.UI.TickerBadge do
  @moduledoc """
  Component for displaying ticker symbols with direction-based coloring.

  ## Examples

      <UI.TickerBadge ticker="AAPL" direction="long" />
      <UI.TickerBadge ticker="TSLA" direction="short" />
      <UI.TickerBadge ticker="MSFT" /> # defaults to neutral coloring
  """
  use Phoenix.Component

  attr :ticker, :string, required: true
  attr :direction, :string, default: nil
  attr :size, :string, default: "sm", values: ~w(xs sm md lg)
  attr :class, :string, default: ""

  def ticker_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded font-medium",
      get_size_classes(@size),
      get_direction_colors(@direction),
      @class
    ]}>
      ${@ticker}
    </span>
    """
  end

  defp get_direction_colors(direction) do
    case direction do
      "long" -> "bg-green-100 text-green-800"
      "short" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp get_size_classes(size) do
    case size do
      "xs" -> "px-2 py-0.5 text-xs"
      "sm" -> "px-2.5 py-0.5 text-xs"
      "md" -> "px-3 py-1 text-sm"
      "lg" -> "px-3.5 py-1.5 text-sm"
    end
  end
end
