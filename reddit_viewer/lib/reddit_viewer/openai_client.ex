defmodule RedditViewer.OpenAIClient do
  @moduledoc """
  OpenAI client for extracting ticker symbols from Reddit posts using structured outputs.
  """

  require Logger

  @openai_url "https://api.openai.com/v1/chat/completions"
  # Using GPT-5 as requested
  @model "gpt-5"

  def extract_tickers(post_content) do
    api_key = System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, "OPENAI_API_KEY environment variable not set"}
    else
      # Acquire rate limit token
      :ok = RedditViewer.RateLimiter.acquire_token(RedditViewer.RateLimiter.OpenAI)

      request_body = build_request_body(post_content)

      headers = [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]

      Logger.debug("Calling OpenAI API with model: #{@model}")

      case Req.post(@openai_url, json: request_body, headers: headers, receive_timeout: 120_000) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          parse_response(body)

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error("OpenAI API error: #{status} - #{inspect(body)}")
          {:error, "OpenAI API returned status #{status}: #{inspect(body)}"}

        {:error, reason} ->
          Logger.error("Request to OpenAI failed: #{inspect(reason)}")
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  defp build_request_body(post_content) do
    %{
      "model" => @model,
      "messages" => [
        %{
          "role" => "system",
          "content" => """
          You are a financial analysis assistant that extracts stock ticker symbols from text and determines the sentiment/direction.

          For ticker extraction:
          - Extract only valid stock ticker symbols (e.g., AAPL, MSFT, GME, AMC, TSLA)
          - Only include tickers that are explicitly mentioned or strongly implied in the context
          - Do not include cryptocurrency symbols or made-up tickers
          - If no valid stock tickers are found, return an empty array

          For direction/sentiment:
          - "long": The post is bullish/positive on the stock(s), suggesting to buy or hold
          - "short": The post is bearish/negative on the stock(s), suggesting to sell or short
          - "neutral": The post discusses the stock(s) without clear bullish or bearish sentiment
          - "n/a": Cannot determine the direction (e.g., just mentioning tickers without opinion)
          """
        },
        %{
          "role" => "user",
          "content" => post_content
        }
      ],
      "response_format" => %{
        "type" => "json_schema",
        "json_schema" => %{
          "name" => "ticker_extraction",
          "schema" => %{
            "type" => "object",
            "properties" => %{
              "tickers" => %{
                "type" => "array",
                "items" => %{
                  "type" => "string",
                  "pattern" => "^[A-Z]{1,5}$",
                  "description" => "A valid stock ticker symbol (1-5 uppercase letters)"
                }
              },
              "confidence" => %{
                "type" => "string",
                "enum" => ["high", "medium", "low"],
                "description" => "Confidence level of the extraction"
              },
              "direction" => %{
                "type" => "string",
                "enum" => ["long", "short", "neutral", "n/a"],
                "description" =>
                  "The sentiment/direction of the stock pitch: long (bullish), short (bearish), neutral, or n/a if unclear"
              }
            },
            "required" => ["tickers", "confidence", "direction"],
            "additionalProperties" => false
          },
          "strict" => true
        }
      }
    }
  end

  defp parse_response(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    case Jason.decode(content) do
      {:ok, %{"tickers" => tickers, "confidence" => confidence, "direction" => direction}} ->
        {:ok, %{tickers: tickers, confidence: confidence, direction: direction}}

      {:error, reason} ->
        Logger.error("Failed to parse OpenAI response: #{inspect(reason)}")
        {:error, "Failed to parse response"}
    end
  end

  defp parse_response(_), do: {:error, "Unexpected response format"}
end
