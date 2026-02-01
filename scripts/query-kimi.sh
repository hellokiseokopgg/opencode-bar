#!/bin/bash
# Query Kimi for Coding usage via OpenCode auth
# Token: ~/.local/share/opencode/auth.json (kimi-for-coding.key)
# API: https://api.kimi.com/coding/v1/usages

set -e

AUTH_FILE="$HOME/.local/share/opencode/auth.json"

if [[ ! -f "$AUTH_FILE" ]]; then
    echo "Error: OpenCode auth file not found at $AUTH_FILE"
    exit 1
fi

TOKEN=$(jq -r '."kimi-for-coding".key // empty' "$AUTH_FILE")

if [[ -z "$TOKEN" ]]; then
    echo "Error: No Kimi token found in auth file (kimi-for-coding.key)"
    exit 1
fi

echo "=== Kimi for Coding Usage ==="
echo ""

RESPONSE=$(curl -s "https://api.kimi.com/coding/v1/usages" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json")

# Check for errors
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "Error: $(echo "$RESPONSE" | jq -r '.error.message // .error')"
    exit 1
fi

# Helper function to calculate time until reset
calculate_time_left() {
    local reset_time="$1"
    local now=$(date +%s)
    local reset_ts=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${reset_time%%.*}" +%s 2>/dev/null || echo 0)
    
    if [[ "$reset_ts" -eq 0 ]]; then
        echo "unknown"
        return
    fi
    
    local diff=$((reset_ts - now))
    if [[ "$diff" -le 0 ]]; then
        echo "now"
        return
    fi
    
    local days=$((diff / 86400))
    local hours=$(((diff % 86400) / 3600))
    local mins=$(((diff % 3600) / 60))
    
    if [[ "$days" -gt 0 ]]; then
        echo "${days}d ${hours}h ${mins}m"
    elif [[ "$hours" -gt 0 ]]; then
        echo "${hours}h ${mins}m"
    else
        echo "${mins}m"
    fi
}

# Helper function to convert duration to human readable label
duration_to_label() {
    local duration="$1"
    local unit="$2"
    
    case "$unit" in
        "TIME_UNIT_MINUTE")
            local hours=$((duration / 60))
            if [[ "$hours" -gt 0 ]]; then
                echo "${hours}h limit"
            else
                echo "${duration}m limit"
            fi
            ;;
        "TIME_UNIT_HOUR")
            echo "${duration}h limit"
            ;;
        "TIME_UNIT_DAY")
            echo "${duration}d limit"
            ;;
        *)
            echo "limit"
            ;;
    esac
}

echo "===[ User Information ]==="
echo ""

# User fields
USER_ID=$(echo "$RESPONSE" | jq -r '.user.userId // "null"')
USER_REGION=$(echo "$RESPONSE" | jq -r '.user.region // "null"')
USER_MEMBERSHIP_LEVEL=$(echo "$RESPONSE" | jq -r '.user.membership.level // "null"')
USER_BUSINESS_ID=$(echo "$RESPONSE" | jq -r '.user.businessId // "null"')

echo "user.userId:              $USER_ID"
echo "user.region:              $USER_REGION"
echo "user.membership.level:    $USER_MEMBERSHIP_LEVEL"
echo "user.businessId:          $USER_BUSINESS_ID"
echo ""

echo "===[ Weekly Usage (usage) ]==="
echo ""

# Usage fields
USAGE_LIMIT=$(echo "$RESPONSE" | jq -r '.usage.limit // "null"')
USAGE_USED=$(echo "$RESPONSE" | jq -r '.usage.used // "null"')
USAGE_REMAINING=$(echo "$RESPONSE" | jq -r '.usage.remaining // "null"')
USAGE_RESET_TIME=$(echo "$RESPONSE" | jq -r '.usage.resetTime // "null"')

echo "usage.limit:              $USAGE_LIMIT"
echo "usage.used:               $USAGE_USED"
echo "usage.remaining:          $USAGE_REMAINING"
echo "usage.resetTime:          $USAGE_RESET_TIME"

# Calculate percentage and time left
if [[ "$USAGE_LIMIT" != "null" && "$USAGE_REMAINING" != "null" && "$USAGE_LIMIT" -gt 0 ]]; then
    USAGE_PCT_LEFT=$((USAGE_REMAINING * 100 / USAGE_LIMIT))
    USAGE_TIME_LEFT=$(calculate_time_left "$USAGE_RESET_TIME")
    echo ""
    echo "  -> ${USAGE_PCT_LEFT}% left (resets in $USAGE_TIME_LEFT)"
fi
echo ""

echo "===[ Rate Limits (limits) ]==="
echo ""

# Limits array
LIMITS_COUNT=$(echo "$RESPONSE" | jq '.limits | length')
echo "limits count:             $LIMITS_COUNT"
echo ""

if [[ "$LIMITS_COUNT" -gt 0 ]]; then
    for i in $(seq 0 $((LIMITS_COUNT - 1))); do
        echo "--- limits[$i] ---"
        
        # Window fields
        WINDOW_DURATION=$(echo "$RESPONSE" | jq -r ".limits[$i].window.duration // \"null\"")
        WINDOW_TIME_UNIT=$(echo "$RESPONSE" | jq -r ".limits[$i].window.timeUnit // \"null\"")
        
        echo "limits[$i].window.duration:       $WINDOW_DURATION"
        echo "limits[$i].window.timeUnit:       $WINDOW_TIME_UNIT"
        
        # Detail fields
        DETAIL_LIMIT=$(echo "$RESPONSE" | jq -r ".limits[$i].detail.limit // \"null\"")
        DETAIL_USED=$(echo "$RESPONSE" | jq -r ".limits[$i].detail.used // \"null\"")
        DETAIL_REMAINING=$(echo "$RESPONSE" | jq -r ".limits[$i].detail.remaining // \"null\"")
        DETAIL_RESET_TIME=$(echo "$RESPONSE" | jq -r ".limits[$i].detail.resetTime // \"null\"")
        
        echo "limits[$i].detail.limit:          $DETAIL_LIMIT"
        echo "limits[$i].detail.used:           $DETAIL_USED"
        echo "limits[$i].detail.remaining:      $DETAIL_REMAINING"
        echo "limits[$i].detail.resetTime:      $DETAIL_RESET_TIME"
        
        # Calculate human-readable summary
        LABEL=$(duration_to_label "$WINDOW_DURATION" "$WINDOW_TIME_UNIT")
        if [[ "$DETAIL_LIMIT" != "null" && "$DETAIL_REMAINING" != "null" && "$DETAIL_LIMIT" -gt 0 ]]; then
            DETAIL_PCT_LEFT=$((DETAIL_REMAINING * 100 / DETAIL_LIMIT))
            DETAIL_TIME_LEFT=$(calculate_time_left "$DETAIL_RESET_TIME")
            echo ""
            echo "  -> $LABEL: ${DETAIL_PCT_LEFT}% left (resets in $DETAIL_TIME_LEFT)"
        fi
        echo ""
    done
fi

echo "===[ Summary ]==="
echo ""

# Print summary like the kimi-cli image
if [[ "$USAGE_LIMIT" != "null" && "$USAGE_REMAINING" != "null" && "$USAGE_LIMIT" -gt 0 ]]; then
    USAGE_PCT_LEFT=$((USAGE_REMAINING * 100 / USAGE_LIMIT))
    USAGE_TIME_LEFT=$(calculate_time_left "$USAGE_RESET_TIME")
    printf "Weekly limit     %3d%% left    (resets in %s)\n" "$USAGE_PCT_LEFT" "$USAGE_TIME_LEFT"
fi

if [[ "$LIMITS_COUNT" -gt 0 ]]; then
    for i in $(seq 0 $((LIMITS_COUNT - 1))); do
        WINDOW_DURATION=$(echo "$RESPONSE" | jq -r ".limits[$i].window.duration // 0")
        WINDOW_TIME_UNIT=$(echo "$RESPONSE" | jq -r ".limits[$i].window.timeUnit // \"\"")
        DETAIL_LIMIT=$(echo "$RESPONSE" | jq -r ".limits[$i].detail.limit // 0")
        DETAIL_REMAINING=$(echo "$RESPONSE" | jq -r ".limits[$i].detail.remaining // 0")
        DETAIL_RESET_TIME=$(echo "$RESPONSE" | jq -r ".limits[$i].detail.resetTime // \"\"")
        
        LABEL=$(duration_to_label "$WINDOW_DURATION" "$WINDOW_TIME_UNIT")
        if [[ "$DETAIL_LIMIT" -gt 0 ]]; then
            DETAIL_PCT_LEFT=$((DETAIL_REMAINING * 100 / DETAIL_LIMIT))
            DETAIL_TIME_LEFT=$(calculate_time_left "$DETAIL_RESET_TIME")
            printf "%-16s %3d%% left    (resets in %s)\n" "$LABEL" "$DETAIL_PCT_LEFT" "$DETAIL_TIME_LEFT"
        fi
    done
fi

echo ""

# Raw JSON output option
if [[ "$1" == "--json" ]]; then
    echo "===[ Raw JSON Response ]==="
    echo ""
    echo "$RESPONSE" | jq .
fi
