#!/bin/bash
# Strategy Registry
# Lists and validates available trading strategies
#
# Usage: ./registry.sh [--list|--validate <strategy>|--help]

REGISTRY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$REGISTRY_DIR/base/strategy.sh"

show_help() {
    echo "Strategy Registry"
    echo ""
    echo "Usage: registry.sh [command]"
    echo ""
    echo "Commands:"
    echo "  --list              List all available strategies"
    echo "  --validate <name>   Validate a strategy exists and is properly configured"
    echo "  --help              Show this help message"
    echo ""
    echo "Available strategies:"
    list_strategies
}

validate_strategy() {
    local strategy="$1"

    if ! strategy_exists "$strategy"; then
        echo "Error: Strategy '$strategy' not found" >&2
        echo "" >&2
        list_strategies >&2
        return 1
    fi

    local script_path
    script_path=$(get_strategy_script "$strategy")

    if [[ ! -x "$script_path" ]]; then
        echo "Warning: Strategy script is not executable: $script_path" >&2
        echo "Run: chmod +x $script_path" >&2
    fi

    local config_file="$REGISTRY_DIR/$strategy/config.json"
    if [[ ! -f "$config_file" ]]; then
        echo "Warning: Strategy config not found: $config_file" >&2
    else
        # Validate JSON syntax
        if ! jq empty "$config_file" 2>/dev/null; then
            echo "Error: Invalid JSON in config: $config_file" >&2
            return 1
        fi
    fi

    echo "Strategy '$strategy' is valid"
    echo "  Script: $script_path"
    [[ -f "$config_file" ]] && echo "  Config: $config_file"

    return 0
}

# Main
case "${1:-}" in
    --list)
        list_strategies
        ;;
    --validate)
        if [[ -z "${2:-}" ]]; then
            echo "Error: Strategy name required" >&2
            exit 1
        fi
        validate_strategy "$2"
        ;;
    --help|"")
        show_help
        ;;
    *)
        echo "Error: Unknown command: $1" >&2
        show_help >&2
        exit 1
        ;;
esac
