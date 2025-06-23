# Invisible Application Setup

## Overview

This repository contains a setup script designed to provision a bare Ubuntu server to run the complete Invisible application stack. The script installs all necessary dependencies, configures the environment, and prepares the system to be managed by the `invisible-orchestrator`.

## Prerequisites

1.  A server running a fresh installation of **Ubuntu 22.04 LTS**.
2.  You have **sudo privileges** on the server.
3.  You have pointed the necessary **DNS records** to your server's public IP address. At a minimum, you will need:
    *   `chat.your-domain.com`
    *   `hub.your-domain.com`
    *   `api.your-domain.com`

## Usage

1.  SSH into your new Ubuntu server.

2.  Clone this repository:
    ```bash
    git clone https://github.com/your-github-username/invisible-setup.git
    cd invisible-setup
    ```

3.  Make the setup script executable:
    ```bash
    chmod +x setup.sh
    ```

4.  Run the script with `sudo`, providing all the required arguments. Be sure to wrap any values with special characters in quotes.

    **Example:**
    ```bash
    sudo ./setup.sh \
      --docker-username "your-docker-user" \
      --docker-password "your-docker-password" \
      --app-domain "your-domain.com" \
      --postgres-password "your-db-password" \
      --jwt-secret "a-very-long-and-random-secret-string"
    ```

5.  To see all available options, run:
    ```bash
    ./setup.sh --help
    ```

## Post-Setup

After the script completes, it will provide final instructions on how to start, manage, and monitor your application stack using `docker-compose` from the `/opt/invisible` directory.
