#!/bin/bash
# Trade Matcher - FIFO matching for round-trip trade analysis
# Usage: source this file and call match_trades_fifo()
#
# Matches Buy and Sell orders using FIFO (First-In-First-Out) logic
# to create round-trip trades with entry/exit prices and P/L calculation.

TRADE_MATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TRADE_MATCHER_DIR/../../.." && pwd)"

# Build UIC to pip_size mapping from config files
# Returns JSON object: {"4": 0.0001, "42": 0.01, ...}
build_pip_size_map() {
    local config_dir="$PROJECT_ROOT/scripts/config/currencies"

    if [[ ! -d "$config_dir" ]]; then
        echo "{}" >&2
        return 1
    fi

    # Read all currency configs and build UIC -> pip_size map
    find "$config_dir" -name "*.json" -type f | while read -r config_file; do
        jq -r '"\(.saxo_uic):\(.pip_size)"' "$config_file" 2>/dev/null
    done | jq -Rs '
        split("\n") |
        map(select(length > 0)) |
        map(split(":") | {(.[0]): (.[1] | tonumber)}) |
        add // {}
    '
}

# Match trades using FIFO algorithm
# Input: Raw order activities JSON from Saxo API
# Output: Detailed trade analysis JSON with round_trips, by_instrument, summary
match_trades_fifo() {
    local raw_json="$1"
    local pip_size_map

    pip_size_map=$(build_pip_size_map)

    echo "$raw_json" | jq --argjson pip_sizes "$pip_size_map" '
# UIC to Symbol mapping
def uic_to_symbol:
  {
    "4": "AUDUSD",
    "18": "EURJPY",
    "21": "EURUSD",
    "26": "GBPJPY",
    "31": "GBPUSD",
    "38": "USDCAD",
    "42": "USDJPY",
    "47": "USDPLN",
    "8176": "XAUUSD",
    "8177": "XAGUSD",
    "107830": "XPTUSD"
  }[tostring] // "UIC:\(.)";

# Get pip size for a UIC
def get_pip_size:
  . as $uic |
  ($pip_sizes[($uic | tostring)] // 0.0001);

# Calculate pips from price difference
def calc_pips($entry; $exit; $pip_size; $direction):
  if $direction == "long" then
    (($exit - $entry) / $pip_size) | . * 10 | round / 10
  else
    (($entry - $exit) / $pip_size) | . * 10 | round / 10
  end;

# Determine trading session from UTC time string
# Tokyo: 00:00-08:00 UTC, London: 08:00-13:00 UTC, NY: 13:00-22:00 UTC
def get_session:
  (.[11:13] | tonumber) as $hour |
  if $hour >= 0 and $hour < 8 then "tokyo"
  elif $hour >= 8 and $hour < 13 then "london"
  elif $hour >= 13 and $hour < 22 then "ny"
  else "other"
  end;

# Calculate holding time in minutes from two ISO timestamps
def calc_holding_minutes($entry; $exit):
  # Parse timestamps and calculate difference in minutes
  # Format: 2026-03-04T01:24:41.315000Z
  (($exit[0:19] + "Z") | fromdateiso8601) as $exit_ts |
  (($entry[0:19] + "Z") | fromdateiso8601) as $entry_ts |
  (($exit_ts - $entry_ts) / 60) | floor;

# FIFO matching algorithm - handles both long and short positions
def fifo_match:
  # Group by Uic and process each group
  group_by(.Uic) | map(
    . as $trades |
    .[0].Uic as $uic |
    ($uic | uic_to_symbol) as $symbol |
    ($uic | get_pip_size) as $pip_size |

    # Sort all trades by time
    ($trades | sort_by(.ActivityTime)) as $sorted_trades |

    # Process trades chronologically, tracking position
    {
      position: 0,
      avg_entry_price: 0,
      entry_time: null,
      round_trips: [],
      open_entries: []
    } |

    reduce $sorted_trades[] as $trade (
      .;
      # Determine if opening or closing
      (if $trade.BuySell == "Buy" then $trade.Amount else -$trade.Amount end) as $delta |
      .position as $old_pos |
      ($old_pos + $delta) as $new_pos |

      # Case 1: Opening or adding to position
      if ($old_pos >= 0 and $delta > 0) or ($old_pos <= 0 and $delta < 0) then
        # Calculate new average entry price
        (if $old_pos == 0 then
          $trade.AveragePrice
        else
          (((.avg_entry_price * ($old_pos | fabs)) + ($trade.AveragePrice * ($delta | fabs))) / (($old_pos | fabs) + ($delta | fabs)))
        end) as $new_avg |
        .position = $new_pos |
        .avg_entry_price = $new_avg |
        .entry_time = (if $old_pos == 0 then $trade.ActivityTime else .entry_time end)

      # Case 2: Closing position (partial or full)
      elif ($old_pos > 0 and $delta < 0) or ($old_pos < 0 and $delta > 0) then
        ([$old_pos | fabs, $delta | fabs] | min) as $close_amount |
        (if $old_pos > 0 then "long" else "short" end) as $direction |
        .avg_entry_price as $entry_price |
        $trade.AveragePrice as $exit_price |

        # Calculate P/L
        (if $direction == "long" then
          ($exit_price - $entry_price) * $close_amount
        else
          ($entry_price - $exit_price) * $close_amount
        end) as $pnl |

        (calc_pips($entry_price; $exit_price; $pip_size; $direction)) as $pips |

        (.entry_time | get_session) as $session |
        (calc_holding_minutes(.entry_time; $trade.ActivityTime)) as $holding_mins |

        .round_trips += [{
          symbol: $symbol,
          uic: $uic,
          direction: $direction,
          session: $session,
          holding_minutes: $holding_mins,
          entry_time: .entry_time,
          exit_time: $trade.ActivityTime,
          entry_price: $entry_price,
          exit_price: $exit_price,
          amount: $close_amount,
          pnl: ($pnl | . * 100 | round / 100),
          pips: $pips,
          is_winner: ($pnl > 0)
        }] |

        # Update position
        .position = $new_pos |

        # If position flipped, reset entry
        if ($old_pos > 0 and $new_pos < 0) or ($old_pos < 0 and $new_pos > 0) then
          .avg_entry_price = $trade.AveragePrice |
          .entry_time = $trade.ActivityTime
        elif $new_pos == 0 then
          .avg_entry_price = 0 |
          .entry_time = null
        else
          .
        end
      else
        .
      end
    ) |

    # Record any remaining open position
    (if .position != 0 then
      .open_entries = [{
        symbol: $symbol,
        uic: $uic,
        direction: (if .position > 0 then "long" else "short" end),
        entry_time: .entry_time,
        entry_price: .avg_entry_price,
        amount: (.position | fabs)
      }]
    else
      .
    end) |

    {
      round_trips: .round_trips,
      open_entries: .open_entries
    }
  ) | {
    round_trips: [.[].round_trips[]] ,
    open_entries: [.[].open_entries[]]
  };

# Calculate instrument-level statistics
def calc_instrument_stats:
  group_by(.symbol) | map(
    . as $trades |
    .[0].symbol as $symbol |

    ([$trades[] | select(.is_winner == true)] | length) as $win_count |
    ([$trades[] | select(.is_winner == false)] | length) as $loss_count |
    ($win_count + $loss_count) as $total |

    ([$trades[] | select(.is_winner == true) | .pnl] | add // 0) as $total_wins |
    ([$trades[] | select(.is_winner == false) | .pnl] | add // 0) as $total_losses |

    (if $win_count > 0 then $total_wins / $win_count else 0 end) as $avg_winner |
    (if $loss_count > 0 then $total_losses / $loss_count else 0 end) as $avg_loser |

    # Profit factor = gross profit / gross loss (absolute value)
    (if $total_losses != 0 then ($total_wins / (- $total_losses)) else
      (if $total_wins > 0 then 999 else 0 end)
    end) as $profit_factor |

    {
      symbol: $symbol,
      trade_count: $total,
      win_count: $win_count,
      loss_count: $loss_count,
      win_rate: (if $total > 0 then ($win_count * 100 / $total) | . * 10 | round / 10 else 0 end),
      total_pnl: ([$trades[].pnl] | add // 0 | . * 100 | round / 100),
      avg_winner: ($avg_winner | . * 100 | round / 100),
      avg_loser: ($avg_loser | . * 100 | round / 100),
      profit_factor: ($profit_factor | . * 100 | round / 100)
    }
  );

# Calculate session statistics
def calc_session_stats:
  group_by(.session) | map(
    . as $trades |
    .[0].session as $session |

    ([$trades[] | select(.is_winner == true)] | length) as $win_count |
    ([$trades[] | select(.is_winner == false)] | length) as $loss_count |
    ($win_count + $loss_count) as $total |

    ([$trades[].pnl] | add // 0) as $total_pnl |

    {
      session: $session,
      trade_count: $total,
      win_count: $win_count,
      loss_count: $loss_count,
      win_rate: (if $total > 0 then ($win_count * 100 / $total) | . * 10 | round / 10 else 0 end),
      total_pnl: ($total_pnl | . * 100 | round / 100)
    }
  ) | sort_by(.session);

# Calculate session stats by instrument
def calc_session_by_instrument:
  group_by(.symbol) | map(
    . as $inst_trades |
    .[0].symbol as $symbol |
    ($inst_trades | group_by(.session) | map(
      . as $sess_trades |
      .[0].session as $session |
      ([$sess_trades[] | select(.is_winner == true)] | length) as $win_count |
      (length) as $total |
      ([$sess_trades[].pnl] | add // 0) as $pnl |
      {
        session: $session,
        trades: $total,
        win_rate: (if $total > 0 then ($win_count * 100 / $total) | . * 10 | round / 10 else 0 end),
        pnl: ($pnl | . * 100 | round / 100)
      }
    )) as $sessions |
    {
      symbol: $symbol,
      sessions: $sessions
    }
  );

# Calculate holding time distribution
def calc_holding_distribution:
  # Categories: scalp (<5min), short (5-30min), medium (30-120min), long (>120min)
  {
    scalp: [.[] | select(.holding_minutes < 5)],
    short_term: [.[] | select(.holding_minutes >= 5 and .holding_minutes < 30)],
    medium: [.[] | select(.holding_minutes >= 30 and .holding_minutes < 120)],
    long_term: [.[] | select(.holding_minutes >= 120)]
  } |
  to_entries | map(
    .key as $category |
    .value as $trades |
    ($trades | length) as $count |
    ([$trades[] | select(.is_winner == true)] | length) as $wins |
    ([$trades[].pnl] | add // 0) as $pnl |
    (if $count > 0 then ([$trades[].holding_minutes] | add / $count) else 0 end) as $avg_hold |
    {
      category: $category,
      trade_count: $count,
      win_count: $wins,
      win_rate: (if $count > 0 then ($wins * 100 / $count) | . * 10 | round / 10 else 0 end),
      total_pnl: ($pnl | . * 100 | round / 100),
      avg_holding_minutes: ($avg_hold | round)
    }
  );

# Calculate overall summary statistics
def calc_summary:
  . as $round_trips |
  ([$round_trips[] | select(.is_winner == true)] | length) as $win_count |
  ([$round_trips[] | select(.is_winner == false)] | length) as $loss_count |
  ($win_count + $loss_count) as $total |

  ([$round_trips[] | select(.is_winner == true) | .pnl] | add // 0) as $total_wins |
  ([$round_trips[] | select(.is_winner == false) | .pnl] | add // 0) as $total_losses |

  (if $win_count > 0 then $total_wins / $win_count else 0 end) as $avg_winner |
  (if $loss_count > 0 then $total_losses / $loss_count else 0 end) as $avg_loser |

  # Profit factor
  (if $total_losses != 0 then ($total_wins / (- $total_losses)) else
    (if $total_wins > 0 then 999 else 0 end)
  end) as $profit_factor |

  # Risk-reward ratio (avg winner / abs(avg loser))
  (if $avg_loser != 0 then ($avg_winner / (- $avg_loser)) else
    (if $avg_winner > 0 then 999 else 0 end)
  end) as $risk_reward |

  {
    total_trades: $total,
    win_count: $win_count,
    loss_count: $loss_count,
    win_rate: (if $total > 0 then ($win_count * 100 / $total) | . * 10 | round / 10 else 0 end),
    total_pnl: ([$round_trips[].pnl] | add // 0 | . * 100 | round / 100),
    avg_winner: ($avg_winner | . * 100 | round / 100),
    avg_loser: ($avg_loser | . * 100 | round / 100),
    profit_factor: ($profit_factor | . * 100 | round / 100),
    risk_reward_ratio: ($risk_reward | . * 100 | round / 100)
  };

# Main processing
[.Data[] | select(.Status == "FinalFill")] |
if length == 0 then
  {
    round_trips: [],
    open_entries: [],
    by_instrument: [],
    summary: {
      total_trades: 0,
      win_count: 0,
      loss_count: 0,
      win_rate: 0,
      total_pnl: 0,
      avg_winner: 0,
      avg_loser: 0,
      profit_factor: 0,
      risk_reward_ratio: 0
    }
  }
else
  fifo_match as $matched |
  $matched.round_trips as $round_trips |
  $matched.open_entries as $open_entries |

  {
    round_trips: ($round_trips | sort_by(.exit_time) | reverse),
    open_entries: $open_entries,
    by_instrument: ($round_trips | calc_instrument_stats),
    by_session: ($round_trips | calc_session_stats),
    session_by_instrument: ($round_trips | calc_session_by_instrument),
    holding_distribution: ($round_trips | calc_holding_distribution),
    summary: ($round_trips | calc_summary)
  }
end
'
}
