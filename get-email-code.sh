#!/bin/bash

# =====================================================================================
#
#  Invisible - Get Email Code Script (Enhanced)
#
#  This script retrieves the latest authentication code or link from Mailpit.
#  Works both locally on the server and remotely.
#
#  Features:
#  - Retrieves verification codes (6-digit OTP)
#  - Retrieves authentication links
#  - Works remotely via IP or domain
#  - Shows recent emails if no code found
#
#  Usage:
#     ./get-email-code.sh user@example.com [server-address]
#
#  Examples:
#     ./get-email-code.sh user@example.com                    # Local server
#     ./get-email-code.sh user@example.com 192.168.1.100     # Remote via IP
#     ./get-email-code.sh user@example.com example.com        # Remote via domain
#
# =====================================================================================

set -e

# --- Argument Check ---
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 <user-email> [server-address]"
    echo ""
    echo "Examples:"
    echo "  $0 user@example.com                 # Run on local server"
    echo "  $0 user@example.com 192.168.1.100  # Remote server via IP"
    echo "  $0 user@example.com example.com     # Remote server via domain"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: 'jq' is not installed. Please install it:"
    echo "  Ubuntu/Debian: sudo apt-get install -y jq"
    echo "  macOS: brew install jq"
    exit 1
fi

USER_EMAIL="$1"
SERVER="${2:-127.0.0.1}"

# Determine the Mailpit URL based on server address
if [ "$SERVER" = "127.0.0.1" ] || [ "$SERVER" = "localhost" ]; then
    # For local access, try kubectl exec first if kubectl is available
    if command -v kubectl >/dev/null 2>&1 && kubectl get pod -n invisible -l app.kubernetes.io/name=mailpit >/dev/null 2>&1; then
        # Use kubectl exec instead of port-forward for reliability
        USE_KUBECTL_EXEC=true
        MAILPIT_API="http://localhost:8025/api/v1/messages"
        MAILPIT_UI="http://127.0.0.1:8025"
    else
        MAILPIT_API="http://127.0.0.1:8025/api/v1/messages"
        MAILPIT_UI="http://127.0.0.1:8025"
    fi
elif [[ "$SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # IP address - use port 54324 (mapped port)
    MAILPIT_API="http://$SERVER:54324/api/v1/messages"
    MAILPIT_UI="http://$SERVER:54324"
else
    # Domain name - use subdomain (if configured) or port
    MAILPIT_API="http://$SERVER:54324/api/v1/messages"
    MAILPIT_UI="http://$SERVER:54324"
fi

echo "--> Connecting to Mailpit at: $MAILPIT_API"
echo "--> Searching for emails sent to: $USER_EMAIL"
echo ""

# Get all messages
if [ "$USE_KUBECTL_EXEC" = "true" ]; then
    MESSAGES=$(kubectl exec -n invisible deployment/mailpit -- wget -q -O - "$MAILPIT_API" 2>/dev/null || echo '{"messages":[]}')
else
    MESSAGES=$(curl -s "$MAILPIT_API" 2>/dev/null || echo '{"messages":[]}')
fi

if [ "$MESSAGES" = '{"messages":[]}' ]; then
    echo "❌ Could not connect to Mailpit at $MAILPIT_API"
    echo ""
    echo "Troubleshooting:"
    echo "1. If running locally, ensure you're on the server"
    echo "2. If running remotely, ensure:"
    echo "   - The server IP/domain is correct"
    echo "   - Port 54324 is accessible"
    echo "   - Mailpit container is running"
    exit 1
fi

# Get the latest message for the user
MESSAGE_DATA=$(echo "$MESSAGES" | jq -r --arg EMAIL "$USER_EMAIL" '
    .messages[] | 
    select(.To[0].Address == $EMAIL) | 
    {id: .ID, subject: .Subject, date: .Date}' | head -n 5)

if [ -z "$MESSAGE_DATA" ]; then
    echo "No emails found for $USER_EMAIL."
    echo ""
    echo "Recent emails in Mailpit:"
    echo "$MESSAGES" | jq -r '.messages[0:5] | .[] | "  • \(.To[0].Address) - \(.Subject)"'
    exit 0
fi

# Get the first (latest) message ID
MESSAGE_ID=$(echo "$MESSAGE_DATA" | jq -r '.id' | head -n 1)
MESSAGE_SUBJECT=$(echo "$MESSAGE_DATA" | jq -r '.subject' | head -n 1)

echo "Found email: $MESSAGE_SUBJECT"
echo "--> Message ID: $MESSAGE_ID"
echo ""

# Get the full message (note: singular 'message' not 'messages')
if [ "$USE_KUBECTL_EXEC" = "true" ]; then
    MESSAGE=$(kubectl exec -n invisible deployment/mailpit -- wget -q -O - "http://localhost:8025/api/v1/message/$MESSAGE_ID" 2>/dev/null)
else
    MESSAGE=$(curl -s "${MAILPIT_API%/messages}/message/$MESSAGE_ID")
fi

# Extract HTML and Text bodies
HTML_BODY=$(echo "$MESSAGE" | jq -r '.HTML // empty')
TEXT_BODY=$(echo "$MESSAGE" | jq -r '.Text // empty')

# Try to find a 6-digit code first
CODE=""
if [ -n "$HTML_BODY" ]; then
    # Look for 6-digit codes in HTML
    CODE=$(echo "$HTML_BODY" | grep -oE '[0-9]{6}' | head -n 1)
fi

if [ -z "$CODE" ] && [ -n "$TEXT_BODY" ]; then
    # Look for 6-digit codes in text
    CODE=$(echo "$TEXT_BODY" | grep -oE '[0-9]{6}' | head -n 1)
fi

# Try to find a confirmation/authentication link
LINK=""
if [ -n "$HTML_BODY" ]; then
    # Look for links in href attributes
    LINK=$(echo "$HTML_BODY" | grep -oE 'href="https://[^"]*"' | head -n 1 | cut -d'"' -f2)
fi

if [ -z "$LINK" ] && [ -n "$TEXT_BODY" ]; then
    # Look for links in plain text
    LINK=$(echo "$TEXT_BODY" | grep -oE 'https://[^ ]+' | head -n 1)
fi

# Display results
echo "======================================================================="
echo "  Authentication Details for $USER_EMAIL"
echo "======================================================================="

if [ -n "$CODE" ]; then
    echo ""
    echo "📱 Verification Code: $CODE"
fi

if [ -n "$LINK" ]; then
    echo ""
    echo "🔗 Authentication Link:"
    echo "$LINK"
fi

if [ -z "$CODE" ] && [ -z "$LINK" ]; then
    echo ""
    echo "⚠️  No verification code or link found in this email."
    echo ""
    echo "Email subject: $MESSAGE_SUBJECT"
    echo ""
    echo "You can view the full email at:"
    echo "$MAILPIT_UI"
fi

echo ""
echo "======================================================================="

# Show other recent emails for this user
OTHER_MESSAGES=$(echo "$MESSAGE_DATA" | tail -n +2)
if [ -n "$OTHER_MESSAGES" ]; then
    echo ""
    echo "Other recent emails for $USER_EMAIL:"
    echo "$OTHER_MESSAGES" | jq -r '"  • \(.subject) (\(.date))"'
fi

echo ""