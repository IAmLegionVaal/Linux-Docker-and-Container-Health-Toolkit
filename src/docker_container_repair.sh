#!/usr/bin/env bash
set -u

RESTART_DOCKER=false
CONTAINER=""
CONTAINER_ACTION=""
PRUNE_STOPPED=false
PRUNE_IMAGES=false
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: docker_container_repair.sh [options]

  --restart-docker                 Restart the Docker service.
  --container NAME --action ACTION Run start, restart, stop or unpause on one container.
  --prune-stopped                  Remove stopped containers after confirmation.
  --prune-dangling-images          Remove dangling images after confirmation.
  --dry-run                        Show actions without changing Docker.
  --yes                            Skip confirmation prompts.
  --output DIR                     Save logs and verification output in DIR.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --restart-docker) RESTART_DOCKER=true; shift ;;
    --container) CONTAINER="${2:-}"; shift 2 ;;
    --action) CONTAINER_ACTION="${2:-}"; shift 2 ;;
    --prune-stopped) PRUNE_STOPPED=true; shift ;;
    --prune-dangling-images) PRUNE_IMAGES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "Docker CLI is required." >&2; exit 3; }
if ! $RESTART_DOCKER && [ -z "$CONTAINER" ] && ! $PRUNE_STOPPED && ! $PRUNE_IMAGES; then echo "Choose at least one repair action." >&2; exit 2; fi
if [ -n "$CONTAINER" ]; then
  case "$CONTAINER_ACTION" in start|restart|stop|unpause) : ;; *) echo "--action must be start, restart, stop or unpause." >&2; exit 2 ;; esac
  docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "Container not found: $CONTAINER" >&2; exit 2; }
fi

STAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${OUTPUT_DIR:-./docker-repair-$STAMP}"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/repair.log"
BEFORE="$OUTPUT_DIR/before.txt"
AFTER="$OUTPUT_DIR/after.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() { $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " answer; case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac; }
run_action() {
  local description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then printf 'DRY-RUN:' >> "$LOG"; printf ' %q' "$@" >> "$LOG"; printf '\n' >> "$LOG"; return 0; fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_root() { local description="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run_action "$description" "$@"; else run_action "$description" sudo "$@"; fi; }
collect_state() {
  local destination="$1"
  {
    echo "Collected: $(date -Is)"
    docker version 2>&1 || true
    echo
    docker info 2>&1 || true
    echo
    docker ps -a --no-trunc 2>&1 || true
    echo
    docker system df 2>&1 || true
    if [ -n "$CONTAINER" ]; then echo; docker inspect "$CONTAINER" 2>&1 || true; fi
  } > "$destination"
}

collect_state "$BEFORE"
confirm "Apply the selected Docker repair actions? Running workloads may be interrupted." || { log "Repair cancelled."; exit 10; }

if $RESTART_DOCKER; then
  if systemctl list-unit-files docker.service >/dev/null 2>&1; then
    run_root "Restarting Docker service" systemctl restart docker || true
  else
    FAILURES=$((FAILURES + 1)); log "WARNING: docker.service was not found."
  fi
fi

if [ -n "$CONTAINER" ]; then
  case "$CONTAINER_ACTION" in
    start) run_root "Starting container $CONTAINER" docker start "$CONTAINER" || true ;;
    restart) run_root "Restarting container $CONTAINER" docker restart "$CONTAINER" || true ;;
    stop) run_root "Stopping container $CONTAINER" docker stop "$CONTAINER" || true ;;
    unpause) run_root "Unpausing container $CONTAINER" docker unpause "$CONTAINER" || true ;;
  esac
fi

if $PRUNE_STOPPED && confirm "Remove all stopped containers? This cannot be undone."; then
  run_root "Removing stopped containers" docker container prune -f || true
fi
if $PRUNE_IMAGES && confirm "Remove all dangling images?"; then
  run_root "Removing dangling images" docker image prune -f || true
fi

$DRY_RUN || sleep 3
collect_state "$AFTER"

if [ -n "$CONTAINER" ] && [ "$CONTAINER_ACTION" != "stop" ]; then
  STATE=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || true)
  case "$STATE" in running) : ;; *) FAILURES=$((FAILURES + 1)); log "WARNING: $CONTAINER state is $STATE after repair." ;; esac
fi
if $RESTART_DOCKER && systemctl list-unit-files docker.service >/dev/null 2>&1; then
  systemctl is-active --quiet docker || { FAILURES=$((FAILURES + 1)); log "WARNING: Docker service is not active after repair."; }
fi

if [ "$FAILURES" -gt 0 ]; then exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0
