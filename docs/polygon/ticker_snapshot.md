# REST
## Stocks

### Single Ticker Snapshot

**Endpoint:** `GET /v2/snapshot/locale/us/markets/stocks/tickers/{stocksTicker}`

**Description:**

Retrieve the most recent market data snapshot for a single ticker. This endpoint consolidates the latest trade, quote, and aggregated data (minute, day, and previous day) for the specified ticker. Snapshot data is cleared at 3:30 AM EST and begins updating as exchanges report new information, which can start as early as 4:00 AM EST. By focusing on a single ticker, users can closely monitor real-time developments and incorporate up-to-date information into trading strategies, alerts, or company-level reporting.

Use Cases: Focused monitoring, real-time analysis, price alerts, investor relations.

## Path Parameters

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `stocksTicker` | string | Yes | Specify a case-sensitive ticker symbol. For example, AAPL represents Apple Inc. |

## Sample Response

```json
{
  "request_id": "657e430f1ae768891f018e08e03598d8",
  "status": "OK",
  "ticker": {
    "day": {
      "c": 120.4229,
      "h": 120.53,
      "l": 118.81,
      "o": 119.62,
      "v": 28727868,
      "vw": 119.725
    },
    "lastQuote": {
      "P": 120.47,
      "S": 4,
      "p": 120.46,
      "s": 8,
      "t": 1605195918507251700
    },
    "lastTrade": {
      "c": [
        14,
        41
      ],
      "i": "4046",
      "p": 120.47,
      "s": 236,
      "t": 1605195918306274000,
      "x": 10
    },
    "min": {
      "av": 28724441,
      "c": 120.4201,
      "h": 120.468,
      "l": 120.37,
      "n": 762,
      "o": 120.435,
      "t": 1684428720000,
      "v": 270796,
      "vw": 120.4129
    },
    "prevDay": {
      "c": 119.49,
      "h": 119.63,
      "l": 116.44,
      "o": 117.19,
      "v": 110597265,
      "vw": 118.4998
    },
    "ticker": "AAPL",
    "todaysChange": 0.98,
    "todaysChangePerc": 0.82,
    "updated": 1605195918306274000
  }
}
```