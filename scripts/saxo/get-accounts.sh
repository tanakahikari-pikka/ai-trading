#!/bin/bash
# Get account information from Saxo Bank API

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/auth.sh"

# Get user info
echo "=== User Info ===" >&2
USER_RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/port/v1/users/me" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

if echo "$USER_RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error fetching user info:" >&2
    echo "$USER_RESPONSE" | jq . >&2
    exit 1
fi

USER_ID=$(echo "$USER_RESPONSE" | jq -r '.UserId')
echo "UserId: $USER_ID" >&2

# Get client info
echo "" >&2
echo "=== Client Info ===" >&2
CLIENT_RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/port/v1/clients/me" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

if echo "$CLIENT_RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error fetching client info:" >&2
    echo "$CLIENT_RESPONSE" | jq . >&2
    exit 1
fi

CLIENT_KEY=$(echo "$CLIENT_RESPONSE" | jq -r '.ClientKey')
DEFAULT_ACCOUNT_ID=$(echo "$CLIENT_RESPONSE" | jq -r '.DefaultAccountId')
echo "ClientKey: $CLIENT_KEY" >&2
echo "DefaultAccountId: $DEFAULT_ACCOUNT_ID" >&2

# Get accounts info
echo "" >&2
echo "=== Accounts ===" >&2
ACCOUNTS_RESPONSE=$(curl -s -X GET "$SAXO_BASE_URL/port/v1/accounts/me" \
    -H "Authorization: Bearer $SAXO_ACCESS_TOKEN" \
    -H "Content-Type: application/json")

if echo "$ACCOUNTS_RESPONSE" | jq -e '.ErrorCode' > /dev/null 2>&1; then
    echo "Error fetching accounts:" >&2
    echo "$ACCOUNTS_RESPONSE" | jq . >&2
    exit 1
fi

# Find default account's AccountKey
ACCOUNT_KEY=$(echo "$ACCOUNTS_RESPONSE" | jq -r --arg id "$DEFAULT_ACCOUNT_ID" '.Data[] | select(.AccountId == $id) | .AccountKey')
echo "AccountKey (default): $ACCOUNT_KEY" >&2

# List all accounts
echo "" >&2
echo "Available Accounts:" >&2
echo "$ACCOUNTS_RESPONSE" | jq -r '.Data[] | "  - \(.AccountId): \(.AccountKey) (\(.Currency))"' >&2

# Output JSON for script consumption
echo ""
jq -n \
    --arg clientKey "$CLIENT_KEY" \
    --arg accountKey "$ACCOUNT_KEY" \
    --arg defaultAccountId "$DEFAULT_ACCOUNT_ID" \
    '{
        clientKey: $clientKey,
        accountKey: $accountKey,
        defaultAccountId: $defaultAccountId
    }'
