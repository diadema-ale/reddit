# REST
## Stocks

### Custom Bars (OHLC)

**Endpoint:** `GET /v2/aggs/ticker/{stocksTicker}/range/{multiplier}/{timespan}/{from}/{to}`

**Description:**

Retrieve aggregated historical OHLC (Open, High, Low, Close) and volume data for a specified stock ticker over a custom date range and time interval in Eastern Time (ET). Aggregates are constructed exclusively from qualifying trades that meet specific conditions. If no eligible trades occur within a given timeframe, no aggregate bar is produced, resulting in an empty interval that indicates a lack of trading activity during that period. Users can tailor their data by adjusting the multiplier and timespan parameters (e.g., a 5-minute bar), covering pre-market, regular market, and after-hours sessions. This flexibility supports a broad range of analytical and visualization needs.

Use Cases: Data visualization, technical analysis, backtesting strategies, market research.

## Path Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `stocksTicker` | string | Yes | Specify a case-sensitive ticker symbol. For example, AAPL represents Apple Inc. |
| `multiplier` | integer | Yes | The size of the timespan multiplier. |
| `timespan` | string | Yes | The size of the time window. |
| `from` | string | Yes | The start of the aggregate time window. Either a date with the format YYYY-MM-DD or a millisecond timestamp. |
| `to` | string | Yes | The end of the aggregate time window. Either a date with the format YYYY-MM-DD or a millisecond timestamp. |

## Query Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `adjusted` | boolean | No | Whether or not the results are adjusted for splits.  By default, results are adjusted. Set this to false to get results that are NOT adjusted for splits.  |
| `sort` | N/A | No | Sort the results by timestamp. `asc` will return results in ascending order (oldest at the top), `desc` will return results in descending order (newest at the top).  |
| `limit` | integer | No | Limits the number of base aggregates queried to create the aggregate results. Max 50000 and Default 5000. Read more about how limit is used to calculate aggregate results in our article on <a href="https://polygon.io/blog/aggs-api-updates/" target="_blank" alt="Aggregate Data API Improvements">Aggregate Data API Improvements</a>.  |

## Sample Response

```json
{
  "adjusted": true,
  "next_url": "https://api.polygon.io/v2/aggs/ticker/AAPL/range/1/day/1578114000000/2020-01-10?cursor=bGltaXQ9MiZzb3J0PWFzYw",
  "queryCount": 2,
  "request_id": "6a7e466379af0a71039d60cc78e72282",
  "results": [
    {
      "c": 75.0875,
      "h": 75.15,
      "l": 73.7975,
      "n": 1,
      "o": 74.06,
      "t": 1577941200000,
      "v": 135647456,
      "vw": 74.6099
    },
    {
      "c": 74.3575,
      "h": 75.145,
      "l": 74.125,
      "n": 1,
      "o": 74.2875,
      "t": 1578027600000,
      "v": 146535512,
      "vw": 74.7026
    }
  ],
  "resultsCount": 2,
  "status": "OK",
  "ticker": "AAPL"
}
```