#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/cloudspace}"
ENV_DIR="${ENV_DIR:-/etc/cloudspace}"
ENV_FILE="${ENV_FILE:-${ENV_DIR}/cloudspace.env}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/srv/cloudspace/workspace}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/cloudspace}"
SERVICE_FILE="${SERVICE_FILE:-/etc/systemd/system/cloudspace.service}"
CONTAINER_WORKSPACE_UID="${CONTAINER_WORKSPACE_UID:-1000}"
CONTAINER_WORKSPACE_GID="${CONTAINER_WORKSPACE_GID:-1000}"
DEFAULT_WORKSPACE_DIR="/srv/cloudspace/workspace"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

log() {
  printf '[cloudspace deploy] %s\n' "$*"
}

die() {
  printf '[cloudspace deploy] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "run this script with sudo or as root"
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker and Docker Compose are already installed"
    return
  fi

  log "Installing Docker Engine and Docker Compose plugin"
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release rsync
  install -m 0755 -d /etc/apt/keyrings

  if [ ! -s /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  . /etc/os-release
  arch="$(dpkg --print-architecture)"
  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin rsync
  systemctl enable --now docker
}

install_app_checkout() {
  if [ ! -f "${SOURCE_DIR}/docker-compose.yml" ]; then
    die "could not find docker-compose.yml from ${SOURCE_DIR}"
  fi

  if ! command -v rsync >/dev/null 2>&1; then
    log "Installing rsync"
    apt-get update
    apt-get install -y --no-install-recommends rsync
  fi

  install -d -m 0755 "${APP_DIR}"

  if [ "${SOURCE_DIR}" = "${APP_DIR}" ]; then
    log "App checkout already lives at ${APP_DIR}"
    return
  fi

  if [ -n "$(find "${APP_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ] && [ ! -f "${APP_DIR}/docker-compose.yml" ]; then
    die "${APP_DIR} is not empty and does not look like a Cloudspace checkout"
  fi

  log "Syncing current checkout to ${APP_DIR}"
  rsync -a --delete \
    --exclude node_modules \
    --exclude dist \
    --exclude .env \
    "${SOURCE_DIR}/" "${APP_DIR}/"
}

install_environment() {
  install -d -m 0755 "${ENV_DIR}"
  install -d -m 0755 "${WORKSPACE_DIR}"
  install -d -m 0700 "${BACKUP_DIR}"

  if [ "${WORKSPACE_DIR}" = "${DEFAULT_WORKSPACE_DIR}" ]; then
    log "Making ${WORKSPACE_DIR} writable by the Cloudspace container user (${CONTAINER_WORKSPACE_UID}:${CONTAINER_WORKSPACE_GID})"
    chown -R "${CONTAINER_WORKSPACE_UID}:${CONTAINER_WORKSPACE_GID}" "${WORKSPACE_DIR}"
    chmod u+rwx "${WORKSPACE_DIR}"
  else
    log "Leaving custom workspace ownership unchanged: ${WORKSPACE_DIR}"
    log "Ensure it is writable by container UID:GID ${CONTAINER_WORKSPACE_UID}:${CONTAINER_WORKSPACE_GID}"
  fi

  if [ ! -f "${ENV_FILE}" ]; then
    log "Creating ${ENV_FILE} from template"
    install -m 0600 "${APP_DIR}/deploy/oracle-ubuntu/cloudspace.env.example" "${ENV_FILE}"
  else
    log "Keeping existing ${ENV_FILE}"
    chmod 0600 "${ENV_FILE}"
  fi
}

install_systemd_service() {
  log "Installing systemd unit ${SERVICE_FILE}"
  install -m 0644 "${APP_DIR}/deploy/oracle-ubuntu/cloudspace.service" "${SERVICE_FILE}"
  systemctl daemon-reload
  systemctl enable cloudspace.service
}

env_has_placeholders() {
  grep -Eq 'cloudspace\.example\.com|change-me-generate-a-strong-secret' "${ENV_FILE}"
}

start_if_configured() {
  if env_has_placeholders; then
    cat <<EOF

Cloudspace is installed but not started because ${ENV_FILE} still contains
placeholder values.

Next steps:
  1. Edit ${ENV_FILE}
  2. Set CLOUDSPACE_HOSTNAME to your DNS name
  3. Set CLOUDSPACE_OAUTH_OWNER_TOKEN to a strong secret
  4. Optionally set CLOUDSPACE_WORKSPACE_PATH to an existing host directory
  5. Run: sudo systemctl start cloudspace.service

EOF
    return
  fi

  log "Validating Docker Compose configuration"
  docker compose --project-name cloudspace --env-file "${ENV_FILE}" --project-directory "${APP_DIR}" config --quiet
  log "Starting Cloudspace"
  systemctl restart cloudspace.service
  systemctl --no-pager --full status cloudspace.service || true
}

main() {
  require_root
  install_docker
  install_app_checkout
  install_environment
  install_systemd_service
  start_if_configured
}

main "$@"
