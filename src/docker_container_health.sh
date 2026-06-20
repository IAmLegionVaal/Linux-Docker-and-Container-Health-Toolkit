#!/usr/bin/env bash
set -u

HOURS=24
LOG_LINES=200
OUTPUT_DIR=""

usage() {
  cat <<'EOF'
Usage: docker_container_health.sh [--hours N] [--log-lines N] [--output DIR]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --log-lines) LOG_LINES="${2:-200}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ "$HOURS" =~ ^[0-9]+$ ]] || { echo "--hours must be numeric" >&2; exit 2; }
[[ "$LOG_LINES" =~ ^[0-9]+$ ]] || { echo "--log-lines must be numeric" >&2; exit 2; }
command -v docker >/dev/null 2>&1 || { echo "Docker CLI was not found." >&2; exit 1; }

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./docker-health-$STAMP}"
mkdir -p "$OUTPUT_DIR/container-logs"
REPORT="$OUTPUT_DIR/docker-health.txt"
CSV="$OUTPUT_DIR/containers.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"
: > "$ERRORS"

section() {
  local title="$1"
  shift
  {
    printf '\n===== %s =====\n' "$title"
    "$@"
  } >> "$REPORT" 2>> "$ERRORS" || true
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/[[:cntrl:]]/ /g'
}

section "Collection metadata" bash -c 'date -Is; hostname -f 2>/dev/null || hostname; id'
section "Docker version" docker version
section "Docker engine information" docker info
section "Docker service state" bash -c 'systemctl status docker --no-pager -l 2>/dev/null || true'
section "Recent Docker service events" bash -c "journalctl -u docker --since '$HOURS hours ago' --no-pager -n 500 2>/dev/null || true"
section "Container inventory" docker ps -a --no-trunc
section "Live resource snapshot" docker stats --no-stream --all
section "Image inventory" docker image ls --digests
section "Docker disk usage" docker system df -v
section "Volume inventory" docker volume ls
section "Network inventory" docker network ls
section "Recent Docker events" bash -c "docker events --since '${HOURS}h' --until '0s' 2>/dev/null | tail -n 500 || true"

echo 'id,name,image,state,status,health,restart_count,exit_code,created,ports' > "$CSV"

TOTAL=0
RUNNING=0
UNHEALTHY=0
RESTARTING=0
FAILED=0

while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  TOTAL=$((TOTAL + 1))

  name="$(docker inspect -f '{{.Name}}' "$id" 2>>"$ERRORS" | sed 's#^/##')"
  image="$(docker inspect -f '{{.Config.Image}}' "$id" 2>>"$ERRORS")"
  state="$(docker inspect -f '{{.State.Status}}' "$id" 2>>"$ERRORS")"
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}not-configured{{end}}' "$id" 2>>"$ERRORS")"
  restarts="$(docker inspect -f '{{.RestartCount}}' "$id" 2>>"$ERRORS")"
  exit_code="$(docker inspect -f '{{.State.ExitCode}}' "$id" 2>>"$ERRORS")"
  created="$(docker inspect -f '{{.Created}}' "$id" 2>>"$ERRORS")"
  status="$(docker ps -a --filter "id=$id" --format '{{.Status}}' | head -n1)"
  ports="$(docker ps -a --filter "id=$id" --format '{{.Ports}}' | head -n1)"

  [[ "$state" == "running" ]] && RUNNING=$((RUNNING + 1))
  [[ "$health" == "unhealthy" ]] && UNHEALTHY=$((UNHEALTHY + 1))
  [[ "$state" == "restarting" ]] && RESTARTING=$((RESTARTING + 1))
  if [[ "$state" == "exited" && "${exit_code:-0}" -ne 0 ]]; then
    FAILED=$((FAILED + 1))
  fi

  printf '"%s","%s","%s","%s","%s","%s",%s,%s,"%s","%s"\n' \
    "$(json_escape "$id")" \
    "$(json_escape "$name")" \
    "$(json_escape "$image")" \
    "$(json_escape "$state")" \
    "$(json_escape "$status")" \
    "$(json_escape "$health")" \
    "${restarts:-0}" \
    "${exit_code:-0}" \
    "$(json_escape "$created")" \
    "$(json_escape "$ports")" >> "$CSV"

  if [[ "$health" == "unhealthy" || "$state" == "restarting" || ( "$state" == "exited" && "${exit_code:-0}" -ne 0 ) ]]; then
    safe_name="${name//[^A-Za-z0-9_.-]/_}"
    docker logs --timestamps --tail "$LOG_LINES" "$id" > "$OUTPUT_DIR/container-logs/${safe_name}.log" 2>> "$ERRORS" || true
  fi
done < <(docker ps -aq 2>>"$ERRORS")

DAEMON_REACHABLE=false
docker info >/dev/null 2>&1 && DAEMON_REACHABLE=true
OVERALL="Healthy"
if ! $DAEMON_REACHABLE || [[ "$UNHEALTHY" -gt 0 || "$RESTARTING" -gt 0 || "$FAILED" -gt 0 ]]; then
  OVERALL="Attention required"
fi

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -Is)",
  "hostname": "$(json_escape "$(hostname -f 2>/dev/null || hostname)")",
  "docker_daemon_reachable": $DAEMON_REACHABLE,
  "total_containers": $TOTAL,
  "running_containers": $RUNNING,
  "unhealthy_containers": $UNHEALTHY,
  "restarting_containers": $RESTARTING,
  "failed_containers": $FAILED,
  "overall_status": "$OVERALL"
}
EOF

{
  printf '\n===== Summary =====\n'
  printf 'Total containers: %s\n' "$TOTAL"
  printf 'Running: %s\n' "$RUNNING"
  printf 'Unhealthy: %s\n' "$UNHEALTHY"
  printf 'Restarting: %s\n' "$RESTARTING"
  printf 'Exited with non-zero code: %s\n' "$FAILED"
  printf 'Overall status: %s\n' "$OVERALL"
  printf 'Output directory: %s\n' "$OUTPUT_DIR"
} >> "$REPORT"

printf 'Docker health collection completed: %s\n' "$OUTPUT_DIR"
