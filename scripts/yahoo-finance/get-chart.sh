#!/bin/bash
# Get price history (OHLC) from Yahoo Finance API
# Usage: get-chart.sh <symbol> [interval] [range]
#
# Note: Using Yahoo Finance as external data source.
# Saxo Bank sim environment doesn't provide Chart API.
# TODO: Replace with Saxo Bank Chart API when using production environment.

SYMBOL="$1"
INTERVAL="${2:-1h}"   # 1m, 5m, 15m, 30m, 1h, 1d, 1wk, 1mo
RANGE="${3:-10d}"     # 1d, 5d, 1mo, 3mo, 6mo, 1y, 2y, 5y, 10y, ytd, max

if [[ -z "$SYMBOL" ]]; then
    echo "Usage: $0 <symbol> [interval] [range]" >&2
    echo "" >&2
    echo "Arguments:" >&2
    echo "  symbol   - Yahoo Finance symbol" >&2
    echo "  interval - Candle interval (default: 1h)" >&2
    echo "             Options: 1m, 5m, 15m, 30m, 1h, 1d, 1wk, 1mo" >&2
    echo "  range    - Data range (default: 10d)" >&2
    echo "             Options: 1d, 5d, 10d, 1mo, 3mo, 6mo, 1y, 2y, 5y, 10y, ytd, max" >&2
    echo "" >&2
    echo "Common symbols:" >&2
    echo "  GC=F     - Gold Futures" >&2
    echo "  XAUUSD=X - Gold/USD Spot" >&2
    echo "  EURUSD=X - EUR/USD" >&2
    echo "  USDJPY=X - USD/JPY" >&2
    echo "  GBPUSD=X - GBP/USD" >&2
    echo "  ^DJI     - Dow Jones" >&2
    echo "  ^GSPC    - S&P 500" >&2
    exit 1
fi

echo "Fetching $SYMBOL ($INTERVAL, $RANGE)..." >&2

RESPONSE=$(curl -s -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" \
    "https://query1.finance.yahoo.com/v8/finance/chart/${SYMBOL}?interval=${INTERVAL}&range=${RANGE}")

# Check for errors
if echo "$RESPONSE" | jq -e '.chart.error != null' > /dev/null 2>&1; then
    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.chart.error.description // "Unknown error"')
    echo "Error: $ERROR_MSG" >&2
    exit 1
fi

# Check if we got valid data
if ! echo "$RESPONSE" | jq -e '.chart.result[0]' > /dev/null 2>&1; then
    echo "Error: No data returned for symbol $SYMBOL" >&2
    exit 1
fi

# Extract and format data
FORMATTED=$(echo "$RESPONSE" | jq '{
    symbol: .chart.result[0].meta.symbol,
    currency: .chart.result[0].meta.currency,
    exchangeName: .chart.result[0].meta.exchangeName,
    regularMarketPrice: .chart.result[0].meta.regularMarketPrice,
    previousClose: .chart.result[0].meta.previousClose,
    interval: .chart.result[0].meta.dataGranularity,
    range: .chart.result[0].meta.range,
    timestamps: .chart.result[0].timestamp,
    open: .chart.result[0].indicators.quote[0].open,
    high: .chart.result[0].indicators.quote[0].high,
    low: .chart.result[0].indicators.quote[0].low,
    close: .chart.result[0].indicators.quote[0].close,
    volume: .chart.result[0].indicators.quote[0].volume
}')

# Display summary
SYMBOL_NAME=$(echo "$FORMATTED" | jq -r '.symbol')
CURRENT_PRICE=$(echo "$FORMATTED" | jq -r '.regularMarketPrice')
CANDLE_COUNT=$(echo "$FORMATTED" | jq '.timestamps | length')

echo "" >&2
echo "=== $SYMBOL_NAME ===" >&2
echo "Current Price: $CURRENT_PRICE" >&2
echo "Candles: $CANDLE_COUNT" >&2

# Output JSON
echo ""
echo "$FORMATTED"
