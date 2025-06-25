#!/bin/bash
# Convenient aliases for Zed environment switching
# Source this file in your shell: source .zed/aliases.sh

# Get the directory where this script is located
ZED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$ZED_DIR")"

# Aliases for switching Zed Python environments
alias zed-env-update="$ZED_DIR/switch-env.sh update && echo '✅ Zed configured for Python development (update environment)'"
alias zed-env-default="$ZED_DIR/switch-env.sh default && echo '✅ Zed configured for basic environment (default)'"
alias zed-env-show="$ZED_DIR/switch-env.sh --show"
alias zed-env-switch="$ZED_DIR/switch-env.sh"

# Quick aliases
alias zed-py="zed-env-update"  # Quick switch to Python development environment
alias zed-basic="zed-env-default"  # Quick switch to basic environment

# Function to show available environments with descriptions
zed-env-help() {
    echo "🔧 Zed Environment Management"
    echo "=============================="
    echo ""
    echo "Available commands:"
    echo "  zed-env-update    - Switch to Python development environment (recommended)"
    echo "  zed-env-default   - Switch to basic/minimal environment"
    echo "  zed-env-show      - Show current environment configuration"
    echo "  zed-env-switch    - Interactive environment switcher"
    echo "  zed-env-help      - Show this help"
    echo ""
    echo "Quick aliases:"
    echo "  zed-py           - Same as zed-env-update"
    echo "  zed-basic        - Same as zed-env-default"
    echo ""
    echo "Current configuration:"
    zed-env-show
    echo ""
    echo "💡 Tip: After switching environments, restart Zed for best results"
}

# Auto-completion for environment names (if running in bash)
if [ -n "$BASH_VERSION" ]; then
    _zed_env_complete() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        COMPREPLY=($(compgen -W "default update" -- "$cur"))
    }
    complete -F _zed_env_complete "$ZED_DIR/switch-env.sh"
fi

echo "🚀 Zed environment aliases loaded!"
echo "   Run 'zed-env-help' for available commands"
echo "   Quick start: 'zed-py' for Python development"
