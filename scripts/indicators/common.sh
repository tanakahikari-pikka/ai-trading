#!/bin/bash
# Common functions for technical indicators
# Source this file in other indicator scripts

# Calculate SMA (Simple Moving Average)
# Usage: calc_sma <period> <<< "[1,2,3,4,5,6,7,8,9,10]"
calc_sma() {
    local period=$1
    jq --arg period "$period" '
        ($period | tonumber) as $p |
        if length < $p then
            null
        else
            .[-$p:] | add / $p
        end
    '
}

# Determine signal based on RSI value
# Usage: determine_rsi_signal <rsi_value> [overbought] [oversold]
determine_rsi_signal() {
    local rsi=$1
    local overbought=${2:-70}
    local oversold=${3:-30}

    if (( $(echo "$rsi > $overbought" | bc -l) )); then
        echo "overbought"
    elif (( $(echo "$rsi < $oversold" | bc -l) )); then
        echo "oversold"
    else
        echo "neutral"
    fi
}

# Determine trade signal based on RSI
# Usage: determine_trade_signal <rsi_value> [overbought] [oversold]
determine_trade_signal() {
    local rsi=$1
    local overbought=${2:-70}
    local oversold=${3:-30}

    if (( $(echo "$rsi > $overbought" | bc -l) )); then
        echo "Sell"
    elif (( $(echo "$rsi < $oversold" | bc -l) )); then
        echo "Buy"
    else
        echo "Wait"
    fi
}
