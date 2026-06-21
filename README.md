# Linux Docker and Container Health Toolkit

A Linux support toolkit for diagnosing Docker engine and container problems and applying selected maintenance actions.

## Diagnostic script

```bash
chmod +x src/docker_container_health.sh
sudo ./src/docker_container_health.sh
```

## Repair script

Preview a Docker service restart:

```bash
chmod +x src/docker_container_repair.sh
sudo ./src/docker_container_repair.sh --restart-docker --dry-run
```

Restart the Docker service:

```bash
sudo ./src/docker_container_repair.sh --restart-docker
```

Run an action on one container:

```bash
sudo ./src/docker_container_repair.sh --container web01 --action restart
sudo ./src/docker_container_repair.sh --container web01 --action start
sudo ./src/docker_container_repair.sh --container web01 --action unpause
```

Optional cleanup actions:

```bash
sudo ./src/docker_container_repair.sh --prune-stopped
sudo ./src/docker_container_repair.sh --prune-dangling-images
```

## Repair behaviour

- Restarts the Docker system service.
- Performs one explicit action on one selected container.
- Supports optional cleanup of stopped containers or dangling images after confirmation.
- Captures Docker and container state before and after repair.
- Verifies the service and selected container after applicable actions.
- Supports dry-run, prompts, logs and clear exit codes.

Restarting Docker can interrupt workloads. Cleanup actions are explicit. The tool does not remove running containers, volumes or networks, alter daemon configuration or redeploy applications.

## Requirements

- Bash 4+
- Docker CLI
- Permission to access the Docker socket
- systemd for Docker service restart

## Author

Dewald Pretorius — L2 IT Support Engineer
