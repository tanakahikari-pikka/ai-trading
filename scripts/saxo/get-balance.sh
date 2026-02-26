#!/bin/bash
# Get account balance from Saxo Bank API
# Usage: get-balance.sh [percentage]
# Returns available cash and calculated trade amount

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

PERCENTAGE="${1:-10}"  # Default: 10%

# Get account info first
ACCOUNT_INFO=$("$SCRIPT_DIR/get-accounts.sh" 2>/dev/null)
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to get account info" >&2
    exit 1
fi

CLIENT_KEY=$(echo "$ACCOUNT_INFO" | jq -r '.clientKey')
ACCOUNT_KEY=$(echo "$ACCOUNT_INFO" | jq -r '.accountKey')

if [[ -z "$CLIENT_KEY" || -z "$ACCOUNT_KEY" ]]; then
    echo "Error: Could not extract clientKey or accountKey" >&2
    exit 1
fi

# URL encode the keys
ENCODED_CLIENT_KEY=$(printf '%s' "$CLIENT_KEY" | jq -sRr @uri)
ENCODED_ACCOUNT_KEY=$(printf '%s' "$ACCOUNT_KEY" | jq -sRr @uri)

echo "Fetching balance for account..." >&2

# Get balance
RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/port/v1/balances?ClientKey=$ENCODED_CLIENT_KEY&AccountKey=$ENCODED_ACCOUNT_KEY" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

if echo "$RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error fetching balance:" >&2
    echo "$RESPONSE" | jq . >&2
    exit 1
fi

# Extract cash balance
CASH_BALANCE=$(echo "$RESPONSE" | jq -r '.CashBalance // 0')
CURRENCY=$(echo "$RESPONSE" | jq -r '.Currency // "USD"')

# Calculate trade amount
TRADE_AMOUNT=$(echo "$CASH_BALANCE $PERCENTAGE" | awk '{printf "%.2f", $1 * $2 / 100}')

echo "" >&2
echo "=== Balance ===" >&2
echo "Cash Balance: $CASH_BALANCE $CURRENCY" >&2
echo "Trade Amount ($PERCENTAGE%): $TRADE_AMOUNT $CURRENCY" >&2

# Output JSON for script consumption
jq -n \
    --argjson cashBalance "$CASH_BALANCE" \
    --arg currency "$CURRENCY" \
    --argjson percentage "$PERCENTAGE" \
    --argjson tradeAmount "$TRADE_AMOUNT" \
    --arg accountKey "$ACCOUNT_KEY" \
    --arg clientKey "$CLIENT_KEY" \
    '{
        cashBalance: $cashBalance,
        currency: $currency,
        percentage: $percentage,
        tradeAmount: $tradeAmount,
        accountKey: $accountKey,
        clientKey: $clientKey
    }'
