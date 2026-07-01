#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/cloudspace}"
ENV_FILE="${ENV_FILE:-/etc/cloudspace/cloudspace.env}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-cloudspace}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ARGS=("$@")

log() {
  printf '[cloudspace update] %s\n' "$*"
}

die() {
  printf '[cloudspace update] ERROR: %s\n' "$*" >&2
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

main() {
  require_root
  load_env

  [ -d "${APP_DIR}/.git" ] || die "${APP_DIR} is not a Git checkout"
  [ -f "${ENV_FILE}" ] || die "missing environment file ${ENV_FILE}"

  log "Running backup before update"
  APP_DIR="${APP_DIR}" ENV_FILE="${ENV_FILE}" COMPOSE_PROJECT_NAME="${PROJECT_NAME}" \
    "${SCRIPT_DIR}/backup.sh" "${BACKUP_ARGS[@]}"

  log "Pulling latest code"
  git -C "${APP_DIR}" fetch --all --prune
  git -C "${APP_DIR}" pull --ff-only

  log "Validating Docker Compose configuration"
  docker compose --project-name "${PROJECT_NAME}" --env-file "${ENV_FILE}" --project-directory "${APP_DIR}" config --quiet

  log "Rebuilding Cloudspace and Caddy services"
  docker compose --project-name "${PROJECT_NAME}" --env-file "${ENV_FILE}" --project-directory "${APP_DIR}" build

  log "Restarting cloudspace.service"
  systemctl restart cloudspace.service

  log "systemd status"
  systemctl --no-pager --full status cloudspace.service || true

  log "Docker Compose status"
  docker compose --project-name "${PROJECT_NAME}" --env-file "${ENV_FILE}" --project-directory "${APP_DIR}" ps
}

main "$@"
