defmodule RedditViewer.RateLimiter do
  @moduledoc """
  Rate limiter for API requests using a token bucket algorithm
  """
  use GenServer

  # requests per second
  @default_rate 10

  # Client API
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    rate = Keyword.get(opts, :rate, @default_rate)
    GenServer.start_link(__MODULE__, rate, name: name)
  end

  def acquire_token(name \\ __MODULE__) do
    GenServer.call(name, :acquire_token, :infinity)
  end

  # Server callbacks
  def init(rate) do
    # Schedule token refill
    Process.send_after(self(), :refill, 1000)

    {:ok,
     %{
       rate: rate,
       tokens: rate,
       max_tokens: rate,
       waiting: []
     }}
  end

  def handle_call(:acquire_token, from, %{tokens: 0} = state) do
    # No tokens available, queue the request
    state = Map.update(state, :waiting, [{from, 1}], &(&1 ++ [{from, 1}]))
    {:noreply, state}
  end

  def handle_call(:acquire_token, _from, %{tokens: tokens} = state) do
    # Token available, consume it
    {:reply, :ok, %{state | tokens: tokens - 1}}
  end

  def handle_info(:refill, state) do
    # Refill tokens
    new_tokens = min(state.tokens + state.rate, state.max_tokens)

    # Process waiting requests
    {to_process, remaining} =
      case Map.get(state, :waiting, []) do
        [] ->
          {[], []}

        waiting ->
          Enum.split(waiting, new_tokens - state.tokens)
      end

    # Reply to waiting requests
    Enum.each(to_process, fn {from, _} ->
      GenServer.reply(from, :ok)
    end)

    # Schedule next refill
    Process.send_after(self(), :refill, 1000)

    {:noreply, %{state | tokens: new_tokens - length(to_process), waiting: remaining}}
  end
end
