defmodule RedditViewer.RateLimiter.Polygon do
  @moduledoc """
  Rate limiter specifically for Polygon API requests.
  10 requests per second limit.
  """
  use GenServer

  # 10 requests per second
  @max_tokens 10
  @refill_interval :timer.seconds(1)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def acquire_token do
    GenServer.call(__MODULE__, :acquire_token, :infinity)
  end

  @impl true
  def init(_) do
    # Schedule first refill
    Process.send_after(self(), :refill, @refill_interval)

    {:ok, %{
      tokens: @max_tokens,
      max_tokens: @max_tokens,
      waiting: []
    }}
  end

  @impl true
  def handle_call(:acquire_token, from, %{tokens: 0} = state) do
    # No tokens available, queue the request
    {:noreply, %{state | waiting: state.waiting ++ [from]}}
  end

  @impl true
  def handle_call(:acquire_token, _from, %{tokens: tokens} = state) do
    {:reply, :ok, %{state | tokens: tokens - 1}}
  end

  @impl true
  def handle_info(:refill, state) do
    # Refill tokens
    new_tokens = min(state.tokens + @max_tokens, state.max_tokens)

    # Process waiting requests
    {to_process, remaining} = Enum.split(state.waiting, new_tokens - state.tokens)

    Enum.each(to_process, fn from ->
      GenServer.reply(from, :ok)
    end)

    # Schedule next refill
    Process.send_after(self(), :refill, @refill_interval)

    {:noreply, %{state | tokens: new_tokens - length(to_process), waiting: remaining}}
  end
end
