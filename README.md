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

Connect to your server via SSH and run the single command below. This is all you need to do.

The script will automatically:
- Install Docker and all other dependencies.
- Prompt you for your Docker Hub credentials and domain name.
- Fetch all configuration and application images from Docker Hub.
- Generate all necessary secrets.
- Launch the entire application stack.

```bash
curl -sSL https://raw.githubusercontent.com/invisible-life/invisible-setup/main/setup.sh | sudo bash
```

You can also provide the details as command-line arguments to skip the interactive prompts:
```bash
sudo bash -s -- --docker-username "..." --docker-password "..." --app-domain "..."
```

## 4. Your Services

Once the script completes, your platform will be running. The key public services will be available at these domains:

-   **API Gateway**: `https://api.your-domain.com`
-   **Chat UI**: `https://chat.your-domain.com`
-   **UI Hub**: `https://hub.your-domain.com`

All services are managed via Docker Compose in the `/opt/invisible` directory on your server.

## 5. Secure Database Access

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
