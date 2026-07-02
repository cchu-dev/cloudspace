#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/cloudspace}"
ENV_FILE="${ENV_FILE:-/etc/cloudspace/cloudspace.env}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-cloudspace}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
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

ensure_rsync() {
  if command -v rsync >/dev/null 2>&1; then
    return
  fi

  log "Installing rsync"
  apt-get update
  apt-get install -y --no-install-recommends rsync
}

update_app_checkout() {
  if [ "${SOURCE_DIR}" = "${APP_DIR}" ]; then
    [ -d "${APP_DIR}/.git" ] || die "${APP_DIR} is not a Git checkout"
    log "Pulling latest code"
    git -C "${APP_DIR}" fetch --all --prune
    git -C "${APP_DIR}" pull --ff-only
    return
  fi

  [ -f "${SOURCE_DIR}/docker-compose.yml" ] || die "could not find docker-compose.yml from ${SOURCE_DIR}"
  ensure_rsync
  install -d -m 0755 "${APP_DIR}"

  if [ -n "$(find "${APP_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ] && [ ! -f "${APP_DIR}/docker-compose.yml" ]; then
    die "${APP_DIR} is not empty and does not look like a Cloudspace checkout"
  fi

  log "Syncing current checkout from ${SOURCE_DIR} to ${APP_DIR}"
  rsync -a --delete \
    --exclude node_modules \
    --exclude dist \
    --exclude .env \
    "${SOURCE_DIR}/" "${APP_DIR}/"
}

main() {
  require_root
  load_env

  [ -f "${ENV_FILE}" ] || die "missing environment file ${ENV_FILE}"

  log "Running backup before update"
  APP_DIR="${APP_DIR}" ENV_FILE="${ENV_FILE}" COMPOSE_PROJECT_NAME="${PROJECT_NAME}" \
    "${SCRIPT_DIR}/backup.sh" "${BACKUP_ARGS[@]}"

  update_app_checkout

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
