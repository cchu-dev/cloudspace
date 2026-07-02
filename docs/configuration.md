# Configuration Reference

Cloudspace can be configured through `cloudspace init`, persisted config files, or
environment variables.

The default files are:

```text
~/.cloudspace/config.json
~/.cloudspace/auth.json
```

Use another config directory with:

```bash
CLOUDSPACE_CONFIG_DIR=/path/to/config npx cloudspace serve
```

## Commands

```bash
npx cloudspace init
npx cloudspace serve
npx cloudspace doctor
npx cloudspace config get
npx cloudspace config set publicBaseUrl https://cloudspace.example.com
```

## Core Environment Variables

| Variable | Purpose |
| --- | --- |
| `HOST` | Local bind host. Defaults to `127.0.0.1`. |
| `PORT` | Local port. Defaults to `7676`. |
| `CLOUDSPACE_ALLOWED_ROOTS` | Comma-separated local roots that workspaces may open. |
| `CLOUDSPACE_PUBLIC_BASE_URL` | Public origin for the server, without `/mcp`. |
| `CLOUDSPACE_ALLOWED_HOSTS` | Optional Host header allowlist override. |
| `CLOUDSPACE_OAUTH_OWNER_TOKEN` | Owner password for OAuth approval. Must be at least 16 characters. |
| `CLOUDSPACE_WORKTREE_ROOT` | Directory for managed Git worktrees. Defaults to `~/.cloudspace/worktrees`. |
| `CLOUDSPACE_STATE_DIR` | Directory for SQLite state. Defaults to `~/.local/share/cloudspace`. |

## OAuth

Cloudspace uses a single-user OAuth approval flow.

| Variable | Default |
| --- | --- |
| `CLOUDSPACE_OAUTH_ACCESS_TOKEN_TTL_SECONDS` | `3600` |
| `CLOUDSPACE_OAUTH_REFRESH_TOKEN_TTL_SECONDS` | `2592000` |
| `CLOUDSPACE_OAUTH_SCOPES` | `cloudspace` |
| `CLOUDSPACE_OAUTH_ALLOWED_REDIRECT_HOSTS` | `chatgpt.com,localhost,127.0.0.1` |

MCP clients discover metadata from:

```text
/.well-known/oauth-protected-resource/mcp
/.well-known/oauth-authorization-server
```

## Tool Modes

`CLOUDSPACE_TOOL_NAMING` controls tool names.

| Value | Behavior |
| --- | --- |
| `short` | Default. Uses `read`, `edit`, `bash`, and related names. |
| `legacy` | Uses `read_file`, `edit_file`, `run_shell`, and related names. |

`CLOUDSPACE_TOOL_MODE` controls the tool surface.

| Value | Behavior |
| --- | --- |
| `minimal` | Default. Exposes `open_workspace`, `read`, `write`, `edit`, and `bash`. Clients use `bash` with tools such as `rg`, `find`, and `ls` for inspection. |
| `full` | Exposes the minimal tools plus dedicated `grep`, `glob`, and `ls` tools. |
| `codex` | Experimental. Exposes `open_workspace`, `read`, `apply_patch`, `exec_command`, and `write_stdin`. Existing mutation and shell tools are hidden. |

`CLOUDSPACE_MINIMAL_TOOLS` remains a backward-compatible alias when
`CLOUDSPACE_TOOL_MODE` is unset: `1` selects `minimal` and `0` selects `full`.
The `codex` mode must be selected through `CLOUDSPACE_TOOL_MODE` and always uses
its fixed short tool names regardless of `CLOUDSPACE_TOOL_NAMING`.

Codex-mode commands run without a PTY by default. Set `tty: true` on
`exec_command` for interactive terminal programs. PTY support uses the optional
`node-pty` dependency; `write_stdin` can send input, poll output, and resize PTY
sessions.

## Widgets

`CLOUDSPACE_WIDGETS` controls ChatGPT Apps iframe usage.

| Value | Behavior |
| --- | --- |
| `full` | Default. Widget UI is attached to exposed workspace, file, edit, and shell tools. |
| `changes` | Enables the aggregate `show_changes` tool and attaches widget UI to `open_workspace` and `show_changes`. |
| `off` | Disables widget UI. |

## Skills

| Variable | Purpose |
| --- | --- |
| `CLOUDSPACE_SKILLS` | Set to `0` to hide skills. Enabled by default. |
| `CLOUDSPACE_AGENT_DIR` | Defaults to `~/.codex`; its `skills` child is loaded for compatibility. |
| `CLOUDSPACE_SKILL_PATHS` | Optional comma-separated additional skill directories. |

Cloudspace discovers standard Agent Skills from:

- `~/.agents/skills`
- project `.agents/skills`

It also keeps compatibility with:

- `CLOUDSPACE_AGENT_DIR/skills`, defaulting to `~/.codex/skills`
- additional paths from `CLOUDSPACE_SKILL_PATHS`

Legacy project paths such as `.pi/skills` can be added through `CLOUDSPACE_SKILL_PATHS` when needed.

Example:

```bash
CLOUDSPACE_SKILL_PATHS="$HOME/.claude/skills,$HOME/company/skills" \
npx cloudspace serve
```

## Logging

| Variable | Default |
| --- | --- |
| `CLOUDSPACE_LOG_LEVEL` | `info` |
| `CLOUDSPACE_LOG_FORMAT` | `json` |
| `CLOUDSPACE_LOG_REQUESTS` | `1` |
| `CLOUDSPACE_LOG_ASSETS` | `0` |
| `CLOUDSPACE_LOG_TOOL_CALLS` | `1` |
| `CLOUDSPACE_LOG_SHELL_COMMANDS` | `0` |
| `CLOUDSPACE_TRUST_PROXY` | `0` |

Set `CLOUDSPACE_LOG_FORMAT=pretty` for local debugging.

Set `CLOUDSPACE_LOG_SHELL_COMMANDS=1` only when you intentionally want command
previews in logs.

## Env-Only Example

```bash
CLOUDSPACE_OAUTH_OWNER_TOKEN="$(openssl rand -base64 32)" \
CLOUDSPACE_ALLOWED_ROOTS="$HOME/personal,$HOME/work" \
CLOUDSPACE_PUBLIC_BASE_URL="https://cloudspace.example.com" \
CLOUDSPACE_WORKTREE_ROOT="$HOME/.cloudspace/worktrees" \
CLOUDSPACE_TOOL_MODE="minimal" \
CLOUDSPACE_TOOL_NAMING="short" \
CLOUDSPACE_WIDGETS="full" \
npx cloudspace serve
```

The environment assignments must be part of the same command invocation, or
exported first.
