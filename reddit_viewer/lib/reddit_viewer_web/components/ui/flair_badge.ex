defmodule RedditViewerWeb.Components.UI.FlairBadge do
  @moduledoc """
  A reusable flair badge component for Reddit posts
  """
  use Phoenix.Component

  @doc """
  Renders a flair badge with normalized text
  """
  attr :text, :string, required: true

  def flair_badge(assigns) do
    assigns = assign(assigns, :normalized_text, normalize_flair_text(assigns.text))

    ~H"""
    <%= if @text == nil do %>
      <span class="text-gray-400 text-sm">No flair</span>
    <% else %>
      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800 uppercase">
        {@normalized_text}
      </span>
    <% end %>
    """
  end

  defp normalize_flair_text(nil), do: nil

  defp normalize_flair_text(text) do
    text
    # Remove emoji patterns like :DDNerd: or :any_text:
    |> String.replace(~r/:[^:]+:/, "")
    # Trim whitespace
    |> String.trim()
    # Apply text replacements (case insensitive)
    |> String.replace(~r/🄳🄳/i, "dd")
    |> String.replace(~r/General Discussion/i, "general discussion")
    |> String.replace(~r/𝑺𝒕𝒐𝒄𝒌 𝑰𝒏𝒇𝒐/i, "stock info")
    |> String.replace(~r/Non-\s*lounge Question/i, "non-lounge question")
    |> String.replace(~r/𝗢𝗧𝗖/i, "otc")
    |> String.replace(~r/MΣMΣ/i, "meme")
    |> String.replace(~r/ꉓꍏ꓄ꍏ꒒ꌩꌗ꓄/i, "catalyst")
    |> String.replace(~r/Technical Analysis/i, "technical analysis")
    |> String.replace(~r/Graduating Penny Stock/i, "graduation penny stock")
    |> String.replace(~r/BagHolding/i, "bagholding")
    |> String.replace(~r/𝗕𝘂𝗹𝗹𝗶𝘀𝗵/i, "bullish")
    |> String.replace(~r/𝘽𝙚𝙖𝙧𝙞𝙨𝙝/i, "bearish")
    # Final trim to ensure no extra spaces
    |> String.trim()
  end
end
