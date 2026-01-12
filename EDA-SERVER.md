# EDA Server UI (Optional)

This project now includes an optional EDA Server with web UI for visualizing and managing your Vault event-driven automation.

## What's Included

The EDA Server provides:
- **Web UI** for managing rulebook activations
- **Event visualization** - see Vault events in real-time
- **Activation management** - start/stop/configure rulebook activations
- **API access** - programmatic access to EDA functionality
- **Job history** - track all automation runs and their results

## Prerequisites

- **Docker Desktop** (or Docker Engine + Docker Compose)
  - macOS: [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop)
  - Windows: [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop)
  - Linux: [Docker Engine](https://docs.docker.com/engine/install/)

## Quick Start

### 1. Start Vault (if not already running)

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=myroot
make start-vault
```

### 2. Start EDA Server

```bash
make start-eda-server
```

This will:
- Download the required Docker images (first time only, ~2-3 minutes)
- Start PostgreSQL database
- Start EDA API server
- Start EDA UI
- Start worker processes
- Create default admin user

### 3. Access the UI

Open your browser to: **https://localhost:8443**

**Default credentials:**
- Username: `admin`
- Password: `testpass`

*Note: You may see a security warning about self-signed certificates - this is normal for local development. Click "Advanced" and "Proceed" to continue.*

**First-time setup:** The `make start-eda-server` command automatically creates the admin user with the above credentials. If you need to reset the password later, you can run the password reset command documented in the Troubleshooting section.

## Using EDA Server with Your Rulebooks

### Option 1: Create Activation via CLI (Recommended)

The fastest way to get your Vault rulebook running in EDA Server:

```bash
make create-eda-activation
```

This command:
- Creates an organization, project, and decision environment (if needed)
- Sets up an activation for the Vault EDA rulebook
- Passes through your VAULT_ADDR and VAULT_TOKEN automatically
- Is idempotent - safe to run multiple times
- Shows the activation in the UI immediately

View the activation at: https://localhost:8443/rulebook-activations/1

### Option 2: Create Activation via UI

1. Log in to the UI at https://localhost:8443
2. Navigate to **Projects** → **Create Project**
3. Add your Git repository: https://github.com/gitrgoliveira/vault-eda-delivery.git
4. Navigate to **Rulebook Activations** → **Create Activation**
5. Select `vault-eda-rulebook.yaml`
6. Add extra variables: `VAULT_ADDR` and `VAULT_TOKEN`
7. Click **Enable** to start processing events

### Option 3: Continue Using CLI

You can continue using the CLI-based approach alongside EDA Server:

```bash
# Your existing workflow still works
make run-rulebook-bg
make test-events
```

**Note:** The CLI and EDA Server are independent. Stop the CLI version (`make stop-rulebook`) before using EDA Server to avoid duplicate event processing.

## Managing EDA Server

### Check Status

```bash
make status-eda-server
```

### View Logs

```bash
make logs-eda-server
```

To view logs for a specific service:
```bash
docker compose logs -f eda-api
docker compose logs -f eda-ui
```

### Stop EDA Server

```bash
make stop-eda-server
```

### Clean Up (Remove All Data)

```bash
make clean-eda-server
```

*Warning: This removes all data including users, activations, and history.*

## Architecture

The EDA Server consists of:

```
┌─────────────────┐
│   Browser       │  → https://localhost:8443
└────────┬────────┘
         │
┌────────▼────────┐
│   EDA UI        │  (React frontend)
└────────┬────────┘
         │
┌────────▼────────┐
│   EDA API       │  → http://localhost:8000
└────────┬────────┘
         │
┌────────▼────────┐
│  PostgreSQL     │  (Database)
└─────────────────┘
         │
┌────────▼────────┐
│  Workers        │  (Execute rulebooks)
└─────────────────┘
```

## Configuration

### Environment Variables

You can customize the deployment by setting environment variables:

```bash
# Vault connection (automatically passed to containers)
export VAULT_ADDR=http://host.docker.internal:8200
export VAULT_TOKEN=myroot

# AWX/Controller integration (optional)
export EDA_CONTROLLER_URL=https://your-awx-instance.com
export EDA_CONTROLLER_TOKEN=your-awx-token

# Start with custom config
make start-eda-server
```

### Connecting to External Vault

The containers are configured to access Vault on your host machine via `host.docker.internal`. If Vault is running elsewhere:

```bash
# For Vault on a different host
export VAULT_ADDR=https://your-vault-server.com:8200
export VAULT_TOKEN=your-token

make start-eda-server
```

## Ports Used

- **8443**: EDA UI (HTTPS)
- **8000**: EDA API (HTTP)
- **8001**: EDA WebSocket
- **5432**: PostgreSQL
- **8888**: Podman service (for running activations)

If you have conflicts, you can modify the ports in `docker-compose.yml`.

## Troubleshooting

### Services Won't Start

Check Docker is running:
```bash
docker ps
```

Check logs:
```bash
make logs-eda-server
```

### Can't Access Vault from Containers

The configuration uses `host.docker.internal` to access services on your Mac. If you're on Linux, you may need to:

1. Use your actual IP address:
   ```bash
   export VAULT_ADDR=http://192.168.1.100:8200
   ```

2. Or add to docker-compose.yml under each service:
   ```yaml
   extra_hosts:
     - "host.docker.internal:192.168.1.100"
   ```

### UI Shows "Unable to Connect"

Wait 1-2 minutes after starting for all services to initialize. Check status:
```bash
make status-eda-server
```

All services should show as "Up" and "healthy".

### Database Issues

Reset the database:
```bash
make clean-eda-server
make start-eda-server
```

### Login Not Working

If you can't log in with admin/testpass, reset the password:
```bash
docker compose exec -T eda-api bash -c "echo \"from django.contrib.auth import get_user_model; User = get_user_model(); u = User.objects.get(username='admin'); u.set_password('testpass'); u.save()\" | aap-eda-manage shell"
```

Then refresh your browser (Cmd+Shift+R) and try again.

## Differences from CLI Approach

| Feature | CLI (`make run-rulebook-bg`) | EDA Server UI |
|---------|------------------------------|---------------|
| Setup | Lightweight, Python venv | Requires Docker |
| UI | None (logs only) | Full web interface |
| Management | Command line | Web-based |
| Multiple Rulebooks | Manual process switching | Manage multiple simultaneously |
| History | Log files | Full database history |
| Team Use | Single developer | Multi-user with RBAC |

## Next Steps

- Explore the **Documentation** section in the UI
- Check out the **API docs** at http://localhost:8000/api/eda/v1/docs
- Connect to AWX/Controller for triggering automation jobs
- Set up credentials for accessing external systems

## More Information

- [EDA Server GitHub](https://github.com/ansible/eda-server)
- [EDA Server Documentation](https://github.com/ansible/eda-server/tree/main/docs)
- [Ansible EDA Documentation](https://ansible.readthedocs.io/projects/rulebook/)
