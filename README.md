# Invisible Platform Deployment

This guide provides the instructions to deploy the entire Invisible platform onto a fresh Ubuntu server using a single command. The process uses pre-built Docker Hub images and requires no source code on the target machine.

## 1. Prerequisites

- A fresh Ubuntu 22.04 server.
- A registered domain name.
- Your Docker Hub credentials (username and password/access token).

## 2. DNS Configuration

Before running the setup script, you must configure your domain's DNS records to point to your server's public IP address. This allows the platform's reverse proxy to correctly route traffic to each service.

Create the following two records in your DNS provider's dashboard:

1.  **A Record (for the root domain)**
    -   **Type**: `A`
    -   **Name**: `@` (or your domain, e.g., `example.com`)
    -   **Value**: `YOUR_SERVER_IP_ADDRESS`

2.  **CNAME Record (for all subdomains)**
    -   **Type**: `CNAME`
    -   **Name**: `*`
    -   **Value**: `@` (or your domain, e.g., `example.com`)

This wildcard setup (`*`) is required for the platform's services to function correctly.

> **Note:** DNS changes can take some time to propagate.

## 3. Deployment from a Fresh Ubuntu Machine
```bash
curl -fsSL https://raw.githubusercontent.com/invisible-life/setup/main/setup.sh | sudo bash -s -- -u YOUR_DOCKER_USERNAME -p YOUR_DOCKER_PASSWORD --no-domain
```

### Custom Domain

```bash
curl -fsSL https://raw.githubusercontent.com/invisible-life/setup/main/setup.sh | sudo bash -s -- -u YOUR_DOCKER_USERNAME -p YOUR_DOCKER_PASSWORD -d yourdomain.com
```

## What This Does

The setup script:

1. **Fetches Latest Code**: Downloads the most recent orchestrator configuration
2. **Installs Dependencies**: Docker, Node.js, and required packages
3. **Authenticates**: Logs into Docker Hub for private image access
4. **Generates Secrets**: Creates secure JWT tokens and encryption keys
5. **Builds UI Components**: Compiles React apps with correct environment variables baked in
6. **Starts Services**: Launches the complete platform stack
7. **Configures Security**: Sets up firewall and HTTPS certificates

## Key Features

- **Always Up-to-date**: Pulls latest configuration on each run
- **Build-time Environment Injection**: UI apps get correct Supabase URLs and keys
- **HTTPS by Default**: Self-signed certificates for secure access
- **IP-based Access**: Works without domain configuration
- **One Command**: Complete platform deployment in a single line

## Access Your Platform

After setup completes (typically 5-10 minutes):

- **UI Hub**: `https://YOUR_SERVER_IP`
- **UI Chat**: `https://YOUR_SERVER_IP/chat`
- **Supabase Studio**: `https://YOUR_SERVER_IP/studio`

## Requirements

- Ubuntu 20.04+ server with root access
- Docker Hub account with Invisible image access
- Stable internet connection

## Re-running Setup

To update an existing deployment:

```bash
cd /opt/invisible
sudo ./setup/setup.sh -u YOUR_DOCKER_USERNAME -p YOUR_DOCKER_PASSWORD --no-domain
```

## Individual Utility Scripts

This repository also contains standalone utility scripts:

- `setup-supabase.sh` - Supabase-only deployment
- `add-domain.sh` - Add custom domain after setup
- `add-ssh-key.sh` - Manage SSH key access
- `configure-ip-access.sh` - Configure IP-based HTTPS
- `get-email-code.sh` - Retrieve email verification codes

## Architecture

The setup process now uses a **launcher pattern**:

1. **Public Setup Repo** (this repo): Contains minimal launcher script
2. **Orchestrator Repo**: Contains actual setup logic and latest configurations
3. **UI Repositories**: Cloned and built with environment variables during setup

This ensures every deployment uses the latest code and configurations without requiring users to manually update setup scripts.

## Support

For issues or questions:
- Check the [orchestrator repository](https://github.com/invisible-life/orchestrator)
- Review setup logs in `/opt/invisible`
- Contact support with your server IP and error details

## Secure Database Access

For security, the database and its admin studio are **not** exposed to the public internet. To manage your database, connect from your local machine using a secure SSH tunnel.

**1. Establish the SSH Tunnel**

Open a new terminal window on your local machine and run the following command. This will forward your local port `5432` to the server's database port.

```bash
ssh -N -L 5432:localhost:5432 YOUR_SERVER_USER@YOUR_SERVER_IP_ADDRESS
```

Keep this terminal window open while you are connected to the database.

**2. Connect with a Database Client**

You can now use any local database client (e.g., DBeaver, TablePlus, or the local Supabase Studio app) to connect to your database using these credentials:

-   **Host**: `localhost`
-   **Port**: `5432`
-   **Database**: `postgres`
-   **User**: `postgres`
-   **Password**: The `POSTGRES_PASSWORD` generated during setup. You can find this in the `.env` file located at `/opt/invisible/.env` on your server.
