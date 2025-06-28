#!/bin/bash

# This is a wrapper that calls the staged setup script
# The staged version provides resume capability and better error handling

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGED_SCRIPT="$SCRIPT_DIR/setup-staged.sh"

if [ ! -f "$STAGED_SCRIPT" ]; then
    echo "Error: Staged setup script not found at $STAGED_SCRIPT"
    exit 1
fi

# Pass all arguments to the staged script
exec "$STAGED_SCRIPT" "$@"