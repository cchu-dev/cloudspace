#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/cloudspace}"
ENV_FILE="${ENV_FILE:-/etc/cloudspace/cloudspace.env}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/cloudspace}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-cloudspace}"
HELPER_IMAGE="${CLOUDSPACE_BACKUP_HELPER_IMAGE:-cloudspace:local}"
RETENTION_DAYS="${CLOUDSPACE_BACKUP_RETENTION_DAYS:-30}"
DEFAULT_WORKSPACE_DIR="/srv/cloudspace/workspace"
INCLUDE_WORKSPACE=0

usage() {
  cat <<'EOF'
Usage: sudo deploy/oracle-ubuntu/backup.sh [--include-workspace]

Backs up Docker named volumes and /etc/cloudspace/cloudspace.env.
The /srv/cloudspace/workspace tree is included only with --include-workspace.
Custom workspace paths are not archived by this script; back them up with the
storage policy appropriate for that directory.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --include-workspace)
      INCLUDE_WORKSPACE=1
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
  printf '[cloudspace backup] %s\n' "$*"
}

die() {
  printf '[cloudspace backup] ERROR: %s\n' "$*" >&2
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
    HELPER_IMAGE="${CLOUDSPACE_BACKUP_HELPER_IMAGE:-${HELPER_IMAGE}}"
    RETENTION_DAYS="${CLOUDSPACE_BACKUP_RETENTION_DAYS:-${RETENTION_DAYS}}"
  fi
}

ensure_helper_image() {
  if docker image inspect "${HELPER_IMAGE}" >/dev/null 2>&1; then
    return
  fi

  log "Backup helper image ${HELPER_IMAGE} is missing; building Cloudspace image"
  docker compose --project-name "${PROJECT_NAME}" --env-file "${ENV_FILE}" --project-directory "${APP_DIR}" build cloudspace
}

backup_volume() {
  logical_name="$1"
  output_dir="$2"
  volume_name="${PROJECT_NAME}_${logical_name}"

  if ! docker volume inspect "${volume_name}" >/dev/null 2>&1; then
    log "Skipping missing Docker volume ${volume_name}"
    return
  fi

  log "Backing up Docker volume ${volume_name}"
  docker run --rm --user 0 \
    -v "${volume_name}:/volume:ro" \
    -v "${output_dir}:/backup" \
    "${HELPER_IMAGE}" \
    tar -C /volume -czf "/backup/${logical_name}.tar.gz" .
}

main() {
  require_root
  load_env

  [ -d "${APP_DIR}" ] || die "missing app directory ${APP_DIR}"
  [ -f "${ENV_FILE}" ] || die "missing environment file ${ENV_FILE}"

  umask 077
  install -d -m 0700 "${BACKUP_DIR}"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  stage_dir="$(mktemp -d "${BACKUP_DIR}/.tmp.${timestamp}.XXXXXX")"
  trap 'rm -rf "${stage_dir}"' EXIT

  install -d -m 0700 "${stage_dir}/volumes" "${stage_dir}/etc"

  ensure_helper_image
  backup_volume "cloudspace-data" "${stage_dir}/volumes"
  backup_volume "caddy-data" "${stage_dir}/volumes"
  backup_volume "caddy-config" "${stage_dir}/volumes"

  log "Backing up ${ENV_FILE}"
  install -m 0600 "${ENV_FILE}" "${stage_dir}/etc/cloudspace.env"

  workspace_path="${CLOUDSPACE_WORKSPACE_PATH:-${DEFAULT_WORKSPACE_DIR}}"
  if [ "${INCLUDE_WORKSPACE}" -eq 1 ]; then
    if [ "${workspace_path}" = "${DEFAULT_WORKSPACE_DIR}" ] && [ -d "${DEFAULT_WORKSPACE_DIR}" ]; then
      log "Backing up ${DEFAULT_WORKSPACE_DIR}"
      install -d -m 0700 "${stage_dir}/workspace"
      tar -C "${DEFAULT_WORKSPACE_DIR}" -czf "${stage_dir}/workspace/srv-cloudspace-workspace.tar.gz" .
    else
      log "Skipping workspace archive because CLOUDSPACE_WORKSPACE_PATH is ${workspace_path}, not ${DEFAULT_WORKSPACE_DIR}"
    fi
  fi

  cat > "${stage_dir}/manifest.txt" <<EOF
created_utc=${timestamp}
app_dir=${APP_DIR}
env_file=${ENV_FILE}
project_name=${PROJECT_NAME}
workspace_path=${workspace_path}
include_workspace=${INCLUDE_WORKSPACE}
EOF

  archive="${BACKUP_DIR}/cloudspace-backup-${timestamp}.tar.gz"
  tar -C "${stage_dir}" -czf "${archive}" .
  chmod 0600 "${archive}"
  log "Created ${archive}"

  if [ "${RETENTION_DAYS}" -gt 0 ] 2>/dev/null; then
    find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'cloudspace-backup-*.tar.gz' -mtime "+${RETENTION_DAYS}" -delete
  fi
}

main "$@"
