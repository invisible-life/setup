#!/bin/bash

# =====================================================================================
#
#  Invisible - Get Auth Code Script
#
#  This script retrieves the latest authentication link (e.g., email confirmation or
#  password reset) for a specific user from the Mailpit service.
#
#  It requires 'jq' to be installed for parsing JSON.
#
#  --- How to use this script ---
#
#  1. SSH into the server as a user with sudo privileges.
#  2. Run this script, passing the user's email address as an argument.
#
#  Example:
#     ./get-auth-code.sh user@example.com
#
# =====================================================================================

set -e

# --- Argument Check ---
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <user-email>"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: 'jq' is not installed. Please run 'sudo apt-get install -y jq' to install it."
    exit 1
fi

USER_EMAIL="$1"
MAILPIT_API="http://127.0.0.1:8025/api/v1/messages"

echo "--> Searching for the latest email sent to: $USER_EMAIL"

# 1. Get the latest message ID for the specified email address
MESSAGE_ID=$(curl -s "$MAILPIT_API" | jq -r --arg EMAIL "$USER_EMAIL" '.messages[] | select(.To[0].Address == $EMAIL) | .ID' | head -n 1)

if [ -z "$MESSAGE_ID" ]; then
    echo "No emails found for $USER_EMAIL."
    exit 0
fi

echo "--> Found message ID: $MESSAGE_ID"

# 2. Get the HTML body of that message
HTML_BODY=$(curl -s "$MAILPIT_API/$MESSAGE_ID" | jq -r '.HTML')

# 3. Extract the confirmation link
# This regex looks for a URL starting with https:// within an href attribute.
CONFIRMATION_LINK=$(echo "$HTML_BODY" | grep -o 'href=\"https://[^\"]*\"' | head -n 1 | cut -d'"' -f2)

if [ -z "$CONFIRMATION_LINK" ]; then
    echo "Could not find a confirmation link in the latest email."
    exit 1
fi

echo ""
echo "======================================================================="
echo "  Latest Authentication Link for $USER_EMAIL:"
echo "======================================================================="
echo "$CONFIRMATION_LINK"
echo ""
