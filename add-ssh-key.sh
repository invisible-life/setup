#!/bin/bash

# =====================================================================================
#
#  Invisible - Add SSH Key Script
#
#  This script securely adds a new user's public SSH key to the server, granting
#  them SSH access. It must be run with sudo.
#
#  --- How to find your Public SSH Key ---
#
#  1. Open a terminal on your LOCAL computer (not the server).
#  2. Your public key is usually located at ~/.ssh/id_rsa.pub.
#  3. Display your key by running this command:
#
#     cat ~/.ssh/id_rsa.pub
#
#  4. If the file doesn't exist, you'll need to generate a new key pair. Run:
#
#     ssh-keygen -t rsa -b 4096
#
#     Then run the `cat` command again.
#  5. Copy the ENTIRE output of the `cat` command. It should start with 'ssh-rsa'.
#
#  --- How to use this script ---
#
#  1. SSH into the server as a user with sudo privileges.
#  2. Run this script with sudo, passing the public key you copied as an argument.
#     The key MUST be wrapped in double quotes.
#
# =====================================================================================

set -e

# --- Helper Functions ---
usage() {
  echo "Usage: sudo $0 \"<public-ssh-key>\""
  echo "This script securely adds a public SSH key to the current user's authorized_keys file."
  echo ""
  echo "Example:"
  echo "  sudo $0 \"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD... user@example.com\""
}

# --- Main Script ---

# 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run with sudo."
  usage
  exit 1
fi

# 2. Check for SUDO_USER
if [ -z "$SUDO_USER" ]; then
    echo "Error: SUDO_USER environment variable is not set. Please run with sudo."
    exit 1
fi

# 3. Check for arguments
if [ "$#" -ne 1 ]; then
    echo "Error: You must provide exactly one argument: the public SSH key string."
    usage
    exit 1
fi

PUBLIC_KEY="$1"
TARGET_USER="$SUDO_USER"
AUTH_KEYS_FILE="/home/$TARGET_USER/.ssh/authorized_keys"
SSH_DIR=$(dirname "$AUTH_KEYS_FILE")

echo "--> Adding public key for user: $TARGET_USER"

# 4. Create .ssh directory if it doesn't exist
if [ ! -d "$SSH_DIR" ]; then
    echo "--> Creating .ssh directory at $SSH_DIR"
    mkdir -p "$SSH_DIR"
fi

# 5. Append the key to the authorized_keys file
echo "$PUBLIC_KEY" >> "$AUTH_KEYS_FILE"
echo "--> Public key successfully added to $AUTH_KEYS_FILE"

# 6. Set correct permissions and ownership
echo "--> Setting secure permissions and ownership..."
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS_FILE"
chown -R "$TARGET_USER:$TARGET_USER" "$SSH_DIR"

echo ""
echo "Setup complete. User '$TARGET_USER' can now access the server with the provided key."
