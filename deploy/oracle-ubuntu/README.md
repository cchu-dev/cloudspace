# Oracle Cloud Ubuntu Deployment

This bundle runs Cloudspace on an Oracle Cloud Ubuntu VM with Docker Compose,
Caddy, and systemd. It does not use Kubernetes.

## Paths

- App checkout: `/opt/cloudspace`
- Production environment and secrets: `/etc/cloudspace/cloudspace.env`
- Documented production workspace default: `/srv/cloudspace/workspace`
- Backups: `/var/backups/cloudspace`

`CLOUDSPACE_WORKSPACE_PATH` may point at another existing host directory, such
as `/home/ubuntu/workspaces`. Docker still mounts that host path to `/workspace`
inside the Cloudspace container, and `CLOUDSPACE_ALLOWED_ROOTS` should remain
`/workspace`.

## Oracle Cloud Prerequisites

1. Create an Ubuntu VM.
2. Point a DNS `A` record, such as `cloudspace.example.com`, at the VM public IP.
3. In the OCI security list or network security group, allow inbound TCP `80`
   and `443`. Keep SSH limited to trusted source IPs.
4. If Ubuntu firewall is enabled, allow only SSH, HTTP, and HTTPS:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## Initial Install

From a Cloudspace checkout:

```bash
sudo ./deploy/oracle-ubuntu/deploy.sh
```

The script installs Docker if needed, syncs the checkout to `/opt/cloudspace`,
creates `/etc/cloudspace/cloudspace.env` from the template when missing, installs
`cloudspace.service`, and enables the service. It will not start Cloudspace while
the environment file still contains placeholder values.

Edit the environment file:

```bash
sudo editor /etc/cloudspace/cloudspace.env
```

Set at least:

- `CLOUDSPACE_HOSTNAME`
- `CLOUDSPACE_OAUTH_OWNER_TOKEN`
- `CLOUDSPACE_WORKSPACE_PATH`

Generate the owner token with:

```bash
openssl rand -base64 32
```

Start Cloudspace:

```bash
sudo systemctl start cloudspace.service
sudo systemctl status cloudspace.service
```

Use this MCP endpoint:

```text
https://cloudspace.example.com/mcp
```

## systemd Model

`cloudspace.service` runs Docker Compose in attached mode:

```text
docker compose --project-name cloudspace --env-file /etc/cloudspace/cloudspace.env up --build --remove-orphans
```

This lets systemd supervise the foreground Compose process. Caddy is the only
container publishing ports `80` and `443`; Cloudspace is reachable only on the
private Docker network and is reverse proxied by Caddy.

## Backups

Default backup:

```bash
sudo /opt/cloudspace/deploy/oracle-ubuntu/backup.sh
```

This archives:

- Docker named volumes `cloudspace_cloudspace-data`,
  `cloudspace_caddy-data`, and `cloudspace_caddy-config`
- `/etc/cloudspace/cloudspace.env`

The default backup does not archive workspace files. To include
`/srv/cloudspace/workspace`, run:

```bash
sudo /opt/cloudspace/deploy/oracle-ubuntu/backup.sh --include-workspace
```

If `CLOUDSPACE_WORKSPACE_PATH` points somewhere else, back up that directory
with your normal filesystem or block-volume backup process.

Backups are written to `/var/backups/cloudspace` with mode `0600`. Set
`CLOUDSPACE_BACKUP_RETENTION_DAYS` to change the default 30-day retention.

## Updates

Run:

```bash
sudo /opt/cloudspace/deploy/oracle-ubuntu/update.sh
```

The update script runs a backup first, pulls the Git checkout, validates the
Compose config, rebuilds the Docker images, restarts `cloudspace.service`, and
prints systemd and Compose status. Pass `--include-workspace` to include the
default `/srv/cloudspace/workspace` tree in the pre-update backup.

## Uninstall

Run:

```bash
sudo /opt/cloudspace/deploy/oracle-ubuntu/uninstall.sh
```

The uninstall script stops and disables `cloudspace.service`, runs Docker
Compose down for the `cloudspace` project, removes the systemd unit, and removes
the app checkout at `/opt/cloudspace`.

By default it preserves:

- `/etc/cloudspace` environment and secrets
- Docker named volumes for Cloudspace state and Caddy certificates
- workspace files
- `/var/backups/cloudspace`

Use explicit flags for destructive cleanup:

```bash
sudo /opt/cloudspace/deploy/oracle-ubuntu/uninstall.sh --purge-data
sudo /opt/cloudspace/deploy/oracle-ubuntu/uninstall.sh --purge-workspace
sudo /opt/cloudspace/deploy/oracle-ubuntu/uninstall.sh --remove-backups
```

Add `--yes` to skip the confirmation prompt.

## Restore

Stop Cloudspace:

```bash
sudo systemctl stop cloudspace.service
```

Extract the backup:

```bash
sudo mkdir -p /tmp/cloudspace-restore
sudo tar -C /tmp/cloudspace-restore -xzf /var/backups/cloudspace/cloudspace-backup-YYYYMMDDTHHMMSSZ.tar.gz
```

Restore the environment file:

```bash
sudo install -m 0600 /tmp/cloudspace-restore/etc/cloudspace.env /etc/cloudspace/cloudspace.env
```

Restore Docker volumes:

```bash
for volume in cloudspace-data caddy-data caddy-config; do
  sudo docker volume create "cloudspace_${volume}"
  sudo docker run --rm --user 0 \
    -v "cloudspace_${volume}:/volume" \
    -v "/tmp/cloudspace-restore/volumes:/backup:ro" \
    cloudspace:local \
    sh -c "find /volume -mindepth 1 -maxdepth 1 -exec rm -rf {} +; tar -C /volume -xzf /backup/${volume}.tar.gz"
done
```

If the backup includes `workspace/srv-cloudspace-workspace.tar.gz` and you want
to restore the documented default workspace path:

```bash
sudo mkdir -p /srv/cloudspace/workspace
sudo tar -C /srv/cloudspace/workspace -xzf /tmp/cloudspace-restore/workspace/srv-cloudspace-workspace.tar.gz
```

Start Cloudspace again:

```bash
sudo systemctl start cloudspace.service
sudo systemctl status cloudspace.service
```
