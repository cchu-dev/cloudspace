#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/cloudspace}"
ENV_DIR="${ENV_DIR:-/etc/cloudspace}"
ENV_FILE="${ENV_FILE:-${ENV_DIR}/cloudspace.env}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/cloudspace}"
SERVICE_FILE="${SERVICE_FILE:-/etc/systemd/system/cloudspace.service}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-cloudspace}"
DEFAULT_WORKSPACE_DIR="/srv/cloudspace/workspace"
PURGE_DATA=0
PURGE_WORKSPACE=0
REMOVE_BACKUPS=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: sudo deploy/oracle-ubuntu/uninstall.sh [options]

Stops Cloudspace, disables and removes the systemd unit, runs Docker Compose
down, and removes the app checkout from /opt/cloudspace.

By default this preserves /etc/cloudspace, Docker volumes, backups, and
workspace files.

Options:
  --purge-data        Remove /etc/cloudspace and Cloudspace/Caddy Docker volumes.
  --purge-workspace   Remove CLOUDSPACE_WORKSPACE_PATH, or /srv/cloudspace/workspace.
  --remove-backups    Remove /var/backups/cloudspace.
  -y, --yes           Do not prompt for confirmation.
  -h, --help          Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --purge-data)
      PURGE_DATA=1
      shift
      ;;
    --purge-workspace)
      PURGE_WORKSPACE=1
      shift
      ;;
    --remove-backups)
      REMOVE_BACKUPS=1
      shift
      ;;
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

log() {
  printf '[cloudspace uninstall] %s\n' "$*"
}

die() {
  printf '[cloudspace uninstall] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "run this script with sudo or as root"
  fi
}

load_env() {
  if [ -f "${ENV_FILE}" ]; then
    # shellcheck disable=SC1090
    set -a
    . "${ENV_FILE}"
    set +a
    PROJECT_NAME="${COMPOSE_PROJECT_NAME:-${PROJECT_NAME}}"
  fi
}

confirm() {
  if [ "${ASSUME_YES}" -eq 1 ]; then
    return
  fi

  cat <<EOF
This will uninstall Cloudspace from this host.

Will remove:
  - systemd unit: ${SERVICE_FILE}
  - app checkout: ${APP_DIR}
  - running Compose containers for project: ${PROJECT_NAME}

Will preserve unless explicitly requested:
  - environment/secrets: ${ENV_DIR}
  - Docker volumes: ${PROJECT_NAME}_cloudspace-data, ${PROJECT_NAME}_caddy-data, ${PROJECT_NAME}_caddy-config
  - workspace: ${CLOUDSPACE_WORKSPACE_PATH:-${DEFAULT_WORKSPACE_DIR}}
  - backups: ${BACKUP_DIR}

EOF

  read -r -p "Continue? [y/N] " answer
  case "${answer}" in
    y|Y|yes|YES)
      ;;
    *)
      die "aborted"
      ;;
  esac
}

safe_rm_rf() {
  path="$1"
  label="$2"

  case "${path}" in
    ""|"/"|"/etc"|"/opt"|"/srv"|"/var"|"/var/backups"|"/home"|"/workspace")
      die "refusing to remove unsafe ${label} path: ${path}"
      ;;
  esac

  if [ -e "${path}" ]; then
    log "Removing ${label}: ${path}"
    rm -rf -- "${path}"
  else
    log "Skipping missing ${label}: ${path}"
  fi
}

stop_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    log "systemctl is not available; skipping systemd stop/disable"
    return
  fi

  if systemctl list-unit-files cloudspace.service >/dev/null 2>&1; then
    log "Stopping cloudspace.service"
    systemctl stop cloudspace.service || true
    log "Disabling cloudspace.service"
    systemctl disable cloudspace.service || true
  fi
}

compose_down() {
  if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    log "Docker Compose is not available; skipping Compose shutdown"
    return
  fi

  if [ ! -f "${APP_DIR}/docker-compose.yml" ]; then
    log "Skipping Compose shutdown because ${APP_DIR}/docker-compose.yml is missing"
    return
  fi

  log "Stopping Docker Compose project ${PROJECT_NAME}"
  if [ -f "${ENV_FILE}" ]; then
    docker compose --project-name "${PROJECT_NAME}" --env-file "${ENV_FILE}" --project-directory "${APP_DIR}" down --remove-orphans || true
  else
    docker compose --project-name "${PROJECT_NAME}" --project-directory "${APP_DIR}" down --remove-orphans || true
  fi
}

remove_systemd_unit() {
  if [ -f "${SERVICE_FILE}" ]; then
    log "Removing systemd unit ${SERVICE_FILE}"
    rm -f -- "${SERVICE_FILE}"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl reset-failed cloudspace.service || true
  fi
}

purge_volumes() {
  if [ "${PURGE_DATA}" -ne 1 ]; then
    return
  fi

  if ! command -v docker >/dev/null 2>&1; then
    log "Docker is not available; skipping Docker volume purge"
    return
  fi

  for logical_name in cloudspace-data caddy-data caddy-config; do
    volume_name="${PROJECT_NAME}_${logical_name}"
    if docker volume inspect "${volume_name}" >/dev/null 2>&1; then
      log "Removing Docker volume ${volume_name}"
      docker volume rm "${volume_name}" >/dev/null
    else
      log "Skipping missing Docker volume ${volume_name}"
    fi
  done
}

main() {
  require_root
  load_env
  confirm

  stop_service
  compose_down
  remove_systemd_unit
  purge_volumes

  safe_rm_rf "${APP_DIR}" "app checkout"

  if [ "${PURGE_DATA}" -eq 1 ]; then
    safe_rm_rf "${ENV_DIR}" "environment directory"
  fi

  if [ "${PURGE_WORKSPACE}" -eq 1 ]; then
    safe_rm_rf "${CLOUDSPACE_WORKSPACE_PATH:-${DEFAULT_WORKSPACE_DIR}}" "workspace"
  fi

  if [ "${REMOVE_BACKUPS}" -eq 1 ]; then
    safe_rm_rf "${BACKUP_DIR}" "backup directory"
  fi

  log "Uninstall complete"
}

main "$@"
