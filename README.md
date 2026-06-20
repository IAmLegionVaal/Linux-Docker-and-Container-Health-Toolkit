# Linux Docker and Container Health Toolkit

A read-only Bash toolkit for collecting Docker engine, container, image, volume, network, event, health-check, and resource evidence into timestamped reports.

## Purpose

This project helps Linux support engineers diagnose container incidents without changing running workloads. It is designed for ticket evidence, escalation notes, lab validation, and repeatable operational checks.

## Checks performed

- Docker CLI and daemon availability
- Docker service state and recent service events
- Engine version, storage driver, cgroup mode, and runtime information
- Running, stopped, restarting, dead, and unhealthy containers
- Restart counts, exit codes, health status, image, ports, and creation time
- One-shot CPU, memory, network, block I/O, and process statistics
- Image inventory, dangling images, volumes, and networks
- Recent Docker events
- Tail logs for failed or unhealthy containers
- Disk use reported by Docker

## Usage

```bash
chmod +x src/docker_container_health.sh
sudo ./src/docker_container_health.sh
```

Optional parameters:

```bash
sudo ./src/docker_container_health.sh --hours 24 --log-lines 200 --output /tmp/docker-health
```

## Output

The toolkit creates a timestamped directory containing:

- `docker-health.txt`
- `containers.csv`
- `summary.json`
- `command-errors.log`
- Per-container log excerpts when investigation is needed

## Safety

The script never starts, stops, restarts, removes, prunes, pauses, kills, or updates containers. It does not alter images, networks, volumes, or daemon configuration.

## Requirements

- Bash 4+
- Docker CLI
- Permission to query the Docker socket
- `systemctl` and `journalctl` for full service evidence

## Validation ideas

- Healthy running container
- Container with a failing health check
- Restart-looping container
- Exited container with a non-zero exit code
- Docker daemon stopped
- Host with no containers

## Author

Dewald Pretorius — L2 IT Support Engineer
