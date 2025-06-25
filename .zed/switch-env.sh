#!/bin/bash
# Script to switch Zed editor Python environment between different Pixi environments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$SCRIPT_DIR/settings.json"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Available environments
ENVIRONMENTS=("default" "update")

usage() {
    echo "Usage: $0 [environment]"
    echo "Available environments:"
    for env in "${ENVIRONMENTS[@]}"; do
        echo "  - $env"
    done
    echo ""
    echo "If no environment is specified, you'll be prompted to choose."
}

# Function to update settings.json
update_settings() {
    local env_name="$1"
    local python_path=".pixi/envs/$env_name/bin/python"
    local pyright_path=".pixi/envs/$env_name/bin/pyright-langserver"
    local ruff_path=".pixi/envs/$env_name/bin/ruff"
    local site_packages=".pixi/envs/$env_name/lib/python3.12/site-packages"

    # Check if environment exists
    if [ ! -d "$PROJECT_ROOT/.pixi/envs/$env_name" ]; then
        echo "Error: Environment '$env_name' does not exist."
        echo "Available environments:"
        ls -1 "$PROJECT_ROOT/.pixi/envs/" 2>/dev/null || echo "  No environments found"
        exit 1
    fi

    # Check if Python exists in the environment
    if [ ! -f "$PROJECT_ROOT/$python_path" ]; then
        echo "Error: Python not found in environment '$env_name' at $python_path"
        exit 1
    fi

    # For update environment, check if language servers exist
    if [ "$env_name" = "update" ]; then
        if [ ! -f "$PROJECT_ROOT/$pyright_path" ]; then
            echo "Warning: Pyright not found in '$env_name' environment."
            echo "You may need to install it with: pixi add -e update pyright"
        fi
        if [ ! -f "$PROJECT_ROOT/$ruff_path" ]; then
            echo "Warning: Ruff not found in '$env_name' environment."
            echo "You may need to install it with: pixi add -e update ruff"
        fi
        # Use Python 3.12 for update environment
        site_packages=".pixi/envs/$env_name/lib/python3.12/site-packages"
    else
        # For default environment, use Python 3.13
        site_packages=".pixi/envs/$env_name/lib/python3.13/site-packages"
    fi

    # Create backup
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%Y%m%d_%H%M%S)"

    # Update settings using Python to manipulate JSON
    python3 << EOF
import json
import sys

settings_file = "$SETTINGS_FILE"
env_name = "$env_name"
python_path = "$python_path"
pyright_path = "$pyright_path"
ruff_path = "$ruff_path"
site_packages = "$site_packages"

try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

# Ensure required structure exists
if 'python' not in settings:
    settings['python'] = {}
if 'interpreter' not in settings['python']:
    settings['python']['interpreter'] = {}

if 'lsp' not in settings:
    settings['lsp'] = {}
if 'pyright' not in settings['lsp']:
    settings['lsp']['pyright'] = {}
if 'ruff' not in settings['lsp']:
    settings['lsp']['ruff'] = {}

if 'env' not in settings:
    settings['env'] = {}

if 'terminal' not in settings:
    settings['terminal'] = {}
if 'shell' not in settings['terminal']:
    settings['terminal']['shell'] = {}

# Update Python interpreter
settings['python']['interpreter']['path'] = python_path

# Update LSP settings
settings['lsp']['pyright'] = {
    'binary': {
        'path': pyright_path,
        'arguments': ['--stdio']
    } if env_name == 'update' else settings['lsp']['pyright'].get('binary', {}),
    'initialization_options': {
        'settings': {
            'python': {
                'pythonPath': python_path,
                'venvPath': '.pixi/envs',
                'defaultInterpreterPath': python_path,
                'analysis': {
                    'extraPaths': [site_packages],
                    'autoSearchPaths': True,
                    'useLibraryCodeForTypes': True
                }
            }
        }
    }
}

if env_name == 'update':
    settings['lsp']['ruff'] = {
        'binary': {
            'path': ruff_path,
            'arguments': ['server']
        },
        'initialization_options': {
            'settings': {
                'interpreter': [python_path],
                'configuration': {
                    'lineLength': 88
                }
            }
        }
    }

# Update environment variables
settings['env']['PIXI_ENVIRONMENT'] = env_name
settings['env']['PYTHONPATH'] = site_packages

# Update terminal to use the selected environment
settings['terminal']['shell'] = {
    'with_arguments': {
        'program': 'bash',
        'args': ['-c', f'cd $(pwd) && pixi shell -e {env_name}']
    }
}

# Write back to file
with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)

print(f"Successfully updated Zed settings to use '{env_name}' environment")
EOF
}

# Function to show current environment
show_current() {
    if [ -f "$SETTINGS_FILE" ]; then
        current_env=$(python3 -c "
import json
try:
    with open('$SETTINGS_FILE') as f:
        settings = json.load(f)
    env = settings.get('env', {}).get('PIXI_ENVIRONMENT', 'unknown')
    python_path = settings.get('python', {}).get('interpreter', {}).get('path', 'unknown')
    print(f'Current environment: {env}')
    print(f'Python path: {python_path}')
except:
    print('Unable to read current settings')
")
        echo "$current_env"
    else
        echo "No Zed settings found"
    fi
}

# Function to choose environment interactively
choose_environment() {
    echo "Available Pixi environments:"
    for i in "${!ENVIRONMENTS[@]}"; do
        echo "  $((i+1)). ${ENVIRONMENTS[$i]}"
    done
    echo ""

    while true; do
        read -p "Choose environment (1-${#ENVIRONMENTS[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#ENVIRONMENTS[@]}" ]; then
            selected_env="${ENVIRONMENTS[$((choice-1))]}"
            break
        else
            echo "Invalid choice. Please enter a number between 1 and ${#ENVIRONMENTS[@]}."
        fi
    done

    echo "Selected: $selected_env"
    update_settings "$selected_env"
}

# Main script logic
case "${1:-}" in
    -h|--help)
        usage
        ;;
    -s|--show)
        show_current
        ;;
    "")
        echo "Current Zed Python environment:"
        show_current
        echo ""
        choose_environment
        ;;
    *)
        env_name="$1"
        # Validate environment name
        valid=false
        for env in "${ENVIRONMENTS[@]}"; do
            if [ "$env" = "$env_name" ]; then
                valid=true
                break
            fi
        done

        if [ "$valid" = false ]; then
            echo "Error: Invalid environment '$env_name'"
            usage
            exit 1
        fi

        update_settings "$env_name"
        ;;
esac
