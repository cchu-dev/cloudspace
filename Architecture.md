# Cloudspace Architecture

Cloudspace is a Node.js/TypeScript MCP server that exposes selected local
development directories to MCP-capable clients. It is packaged as a CLI
(`cloudspace`) and runs an Express-based Streamable HTTP MCP endpoint protected by
a single-user OAuth flow.

The core design is intentionally small:

- users configure allowed local roots and a public base URL
- clients authenticate through an Owner-password OAuth approval flow
- clients open one allowed project as a workspace
- all file, search, edit, shell, worktree, skill, and review operations are
  routed through explicit MCP tools scoped to that workspace

## Overall Architecture

Runtime layers:

1. CLI layer (`src/cli.ts`) handles `init`, `serve`, `doctor`, `config`,
   version, and help commands.
2. Configuration layer (`src/config.ts`, `src/user-config.ts`) combines
   persisted JSON files and environment variables into one `ServerConfig`.
3. HTTP/MCP layer (`src/server.ts`) builds the Express app, OAuth routes,
   static widget asset routes, and `/mcp` Streamable HTTP transport handling.
4. Authentication layer (`src/oauth-provider.ts`, `src/oauth-store.ts`) handles
   dynamic client registration, authorization, token exchange, refresh, revoke,
   and bearer-token verification.
5. Workspace layer (`src/workspaces.ts`, `src/workspace-store.ts`,
   `src/roots.ts`, `src/git-worktrees.ts`) enforces filesystem allowlists,
   creates/restores workspace sessions, supports managed Git worktrees, and
   discovers instructions and skills.
6. Tool layer (`src/server.ts`, `src/pi-tools.ts`, `src/apply-patch.ts`,
   `src/process-sessions.ts`, `src/review-checkpoints.ts`) registers MCP tools
   and delegates implementation to either Pi SDK primitives or Cloudspace-native
   helpers.
7. State layer (`src/db/*`) stores workspace sessions, OAuth clients, and token
   hashes in SQLite.
8. UI layer (`src/ui/*`, `vite.config.ts`) builds a React widget app used by
   ChatGPT Apps-compatible hosts for file/tool result cards.

## Module Responsibilities

`src/cli.ts`
: Entrypoint for the published `cloudspace` binary. It validates Node support,
  bootstraps config when needed, runs setup prompts, prints diagnostics, starts
  the server, and shuts it down on signals.

`src/config.ts`
: Parses the effective server configuration. It owns defaults and validation
  for host, port, allowed roots, allowed hosts, public base URL, OAuth settings,
  tool mode, tool naming, widgets, state directories, skill paths, and logging.

`src/user-config.ts`
: Reads and writes `~/.cloudspace/config.json` and `~/.cloudspace/auth.json`
  (or `CLOUDSPACE_CONFIG_DIR`). It also generates the Owner password.

`src/server.ts`
: Main composition root. It creates the Express app, registers OAuth metadata
  routes, protects `/mcp` with bearer auth, creates per-session MCP transports,
  registers all MCP resources/tools, serves UI assets, logs requests, and closes
  long-lived resources.

`src/oauth-provider.ts`
: Implements the MCP SDK OAuth provider interface for a single local owner.
  It renders the Owner-password approval form, validates resource and scope
  requests, issues authorization codes, exchanges codes and refresh tokens, and
  verifies bearer access tokens.

`src/oauth-store.ts`
: Persists OAuth clients and token hashes in SQLite. It validates redirect
  hosts during dynamic client registration and deletes expired tokens on store
  startup.

`src/workspaces.ts`
: Owns workspace lifecycle. It opens checkout or worktree workspaces, generates
  `workspaceId` values, persists sessions, restores known sessions, resolves
  paths, loads root instruction files, discovers nested `AGENTS.md`/`CLAUDE.md`
  files, and exposes skill read allowances after a skill is activated.

`src/roots.ts`
: Shared path-containment helpers. It expands `~`, resolves paths, and rejects
  paths outside configured allowlists.

`src/git-worktrees.ts`
: Creates managed detached Git worktrees under `CLOUDSPACE_WORKTREE_ROOT`. It
  validates the source path, Git root, base ref, and generated worktree path.

`src/pi-tools.ts`
: Thin adapter around `@earendil-works/pi-coding-agent` tools for read, write,
  edit, grep, find, ls, and shell. File and directory operations are path-checked
  before invoking Pi primitives.

`src/apply-patch.ts`
: Cloudspace-native Codex-style patch parser and applier used in `codex` tool
  mode. It confines paths to the workspace, rejects binary/non-UTF-8 files, and
  emits unified patch metadata for UI cards.

`src/process-sessions.ts` and `src/process-platform.ts`
: Cloudspace-native command/session implementation for `codex` mode. It supports
  non-PTY and optional PTY execution, polling, stdin writes, output truncation,
  process-tree termination, and process ownership by `workspaceId`.

`src/review-checkpoints.ts` and `src/git.ts`
: Implements `show_changes` when widget mode is `changes`. It snapshots a Git
  working tree into temporary commits under `refs/cloudspace/review/*`, diffs
  against the last checkpoint, and optionally advances the checkpoint.

`src/skills.ts`
: Discovers Agent Skills from user, project, compatibility, and configured
  skill paths. It controls which skill files are readable by the model.

`src/db/client.ts`, `src/db/migrations.ts`, `src/db/schema.ts`
: SQLite setup, migrations, and Drizzle schema. The database file is
  `cloudspace.sqlite` under `stateDir`.

`src/logger.ts`
: Structured request/tool logging with JSON or pretty output. Shell command
  previews are opt-in.

`src/ui/*`
: React widget application and styles for tool cards/diff display. Built by
  Vite into `dist/ui`.

`scripts/dev-server.mjs`
: Local development runner that watches `src` and restarts `tsx src/cli.ts
  serve`.

`scripts/fix-node-pty-permissions.mjs`
: macOS postinstall helper that fixes executable permissions on optional
  `node-pty` spawn helpers.

## Request Flow

Initial client connection:

1. User runs `cloudspace serve`.
2. CLI loads `ServerConfig`, creates the Express/MCP server, and listens on
   `host:port`.
3. MCP client discovers OAuth metadata under:
   - `/.well-known/oauth-protected-resource/mcp`
   - `/.well-known/oauth-authorization-server`
4. Client dynamically registers through the MCP SDK auth router. Redirect URIs
   must use allowed redirect hosts.
5. Client opens the authorization URL. Cloudspace renders an Owner-password form.
6. User enters the Owner password from `auth.json` or
   `CLOUDSPACE_OAUTH_OWNER_TOKEN`.
7. Cloudspace issues a short-lived authorization code, then access and refresh
   tokens. Only token hashes are stored.

MCP session flow:

1. Client sends an initialize request to `/mcp` with a bearer token.
2. `requireBearerAuth` verifies the token and required scope.
3. Cloudspace verifies the token resource matches the configured MCP resource.
4. For initialize requests without an existing MCP session ID, Cloudspace creates
   a `StreamableHTTPServerTransport`, connects a new `McpServer`, and stores the
   transport by generated session ID.
5. Later requests must include `mcp-session-id`; unknown session IDs get JSON-RPC
   errors.
6. Tool calls execute against a `workspaceId`, not just a raw path.

Workspace/tool flow:

1. Client calls `open_workspace` with a path under `allowedRoots`.
2. Cloudspace opens the actual checkout or creates a managed Git worktree.
3. Cloudspace returns a `workspaceId`, loaded root instructions, nested instruction
   file paths, visible skills, diagnostics, and model instructions.
4. Subsequent tools resolve the `workspaceId`, validate paths against the
   workspace root, call the tool implementation, log the call, and return MCP
   content plus structured content and optional widget metadata.

## Configuration

Persistent user files:

- `~/.cloudspace/config.json`
- `~/.cloudspace/auth.json`

`CLOUDSPACE_CONFIG_DIR` changes the directory that contains those files.

Important environment variables:

- `HOST`, `PORT`
- `CLOUDSPACE_ALLOWED_ROOTS`
- `CLOUDSPACE_PUBLIC_BASE_URL`
- `CLOUDSPACE_ALLOWED_HOSTS`
- `CLOUDSPACE_OAUTH_OWNER_TOKEN`
- `CLOUDSPACE_OAUTH_ACCESS_TOKEN_TTL_SECONDS`
- `CLOUDSPACE_OAUTH_REFRESH_TOKEN_TTL_SECONDS`
- `CLOUDSPACE_OAUTH_SCOPES`
- `CLOUDSPACE_OAUTH_ALLOWED_REDIRECT_HOSTS`
- `CLOUDSPACE_STATE_DIR`
- `CLOUDSPACE_WORKTREE_ROOT`
- `CLOUDSPACE_TOOL_MODE`
- `CLOUDSPACE_TOOL_NAMING`
- `CLOUDSPACE_WIDGETS`
- `CLOUDSPACE_SKILLS`
- `CLOUDSPACE_AGENT_DIR`
- `CLOUDSPACE_SKILL_PATHS`
- `CLOUDSPACE_LOG_*`
- `CLOUDSPACE_TRUST_PROXY`

Default behavior:

- host: `127.0.0.1`
- port: `7676`
- public base URL: local URL unless configured
- tool mode: `minimal`
- tool naming: `short`
- widgets: `full`
- state dir: `~/.local/share/cloudspace`
- worktree root: `~/.cloudspace/worktrees`
- agent dir: `~/.codex`
- skills: enabled
- logging: JSON request and tool-call logs enabled, shell command previews
  disabled

Config precedence is environment first, then persisted files, then defaults.

## Authentication

Cloudspace uses a single-user OAuth model:

- The Owner password is generated by `cloudspace init` and stored in
  `auth.json`.
- `CLOUDSPACE_OAUTH_OWNER_TOKEN` can replace the persisted password for
  environment-driven deployments.
- The OAuth approval form is shown for authorization requests.
- Owner password comparison uses `timingSafeEqual`.
- Authorization codes are in memory and expire after five minutes.
- Access and refresh tokens are random values; only SHA-256 hashes are stored.
- Access token TTL defaults to one hour.
- Refresh token TTL defaults to 30 days.
- Refresh token exchange rotates the refresh token by deleting the consumed
  token in the same SQLite transaction that saves the replacement pair.
- Bearer tokens must include the required scope and requested OAuth resource
  must match the configured MCP resource.
- Dynamic client registration is stored in SQLite and redirect hosts are
  allowlisted.

Host-header protection is provided by `createMcpExpressApp` using derived or
configured allowed hosts unless `CLOUDSPACE_ALLOWED_HOSTS=*` is set.

Important boundary: shell tools run as the local OS user. Path checks protect
Cloudspace file tools, but shell commands have the same authority as the process
user. This is why OAuth, tunnels, and narrow allowlists matter.

## MCP Implementation

Cloudspace uses:

- `@modelcontextprotocol/sdk/server/mcp.js` for `McpServer`
- `@modelcontextprotocol/sdk/server/express.js` for the Express MCP app
- `@modelcontextprotocol/sdk/server/streamableHttp.js` for Streamable HTTP
- MCP SDK auth helpers for OAuth metadata, protected resources, and bearer auth
- `@modelcontextprotocol/ext-apps/server` for ChatGPT Apps resources/tools

The app exposes:

- OAuth metadata and authorization/token routes via `mcpAuthRouter`
- `/mcp` for authenticated MCP Streamable HTTP
- `/mcp-app-assets/*` for built widget assets
- `/healthz` for a simple health check

Tool/resource registration happens per new MCP transport session. The registered
tool names depend on `CLOUDSPACE_TOOL_MODE` and `CLOUDSPACE_TOOL_NAMING`.

Widget support:

- `CLOUDSPACE_WIDGETS=full` attaches the React widget resource to normal tools.
- `CLOUDSPACE_WIDGETS=changes` attaches widgets to `open_workspace` and
  `show_changes`.
- `CLOUDSPACE_WIDGETS=off` omits widget metadata.

The widget resource URI is `ui://cloudspace/workspace-app.html`; runtime HTML is
generated from the Vite manifest in `dist/ui/.vite/manifest.json`.

## Tool Implementation

Always exposed:

- `open_workspace`
- `read` or `read_file`

Non-`codex` modes:

- `write` or `write_file`
- `edit` or `edit_file`
- `bash` or `run_shell`

`full` mode only:

- `grep` or `grep_files`
- `glob` or `find_files`
- `ls` or `list_directory`

`codex` mode:

- `apply_patch`
- `exec_command`
- `write_stdin`

`changes` widget mode:

- `show_changes`

Tool behavior:

- Workspace paths are resolved through `WorkspaceRegistry` and `roots.ts`.
- Skill paths can be read only when advertised by `open_workspace`; files inside
  a skill directory become readable only after the skill's `SKILL.md` is read.
- Pi-backed tools adapt Pi SDK results into MCP content.
- `apply_patch` uses a Cloudspace parser and applies text patches with temporary
  files.
- `exec_command` starts a process in a workspace-owned session and returns a
  `sessionId` when the command is still running after the yield window.
- `write_stdin` writes to or polls a session and verifies the session belongs to
  the given workspace.
- `show_changes` uses Git snapshots; it requires a Git repository with `HEAD`.

## Build System

The project is TypeScript ESM:

- package type: `module`
- main entry: `dist/server.js`
- binary: `dist/cli.js`
- runtime engine in `package.json`: Node `>=22.19 <27`
- CLI runtime check currently accepts Node `>=20.12 <27`

NPM scripts:

- `npm run clean`: removes `dist`
- `npm run build`: cleans, builds UI with Vite, then compiles server TS
- `npm run build:app`: Vite build for `src/ui`
- `npm run dev`: watches source and restarts `tsx src/cli.ts serve`
- `npm run typecheck`: `tsc -p tsconfig.json --noEmit`
- `npm test`: runs each `*.test.ts` with `tsx`
- `npm run start`: runs `node dist/cli.js serve`

TypeScript:

- `tsconfig.json` targets ES2022, `NodeNext` modules/resolution, strict mode,
  React JSX, root `src`, output `dist`
- `tsconfig.build.json` excludes tests and `src/ui`

Vite:

- root: `src/ui`
- entry: `src/ui/workspace-app.html`
- output: `dist/ui`
- manifest enabled
- hashed JS/CSS/assets under `dist/ui/assets`

Publishing:

- package includes `dist`, `docs`, `scripts`, and `README.md`
- `postinstall` runs the macOS `node-pty` permission helper
- `better-sqlite3` is required at runtime
- `node-pty` is optional and only needed for PTY support

## Docker Implications

There are no Dockerfiles or Compose files in the repository today.

Running Cloudspace in Docker would change its security and usability model:

- The configured `allowedRoots` must be bind-mounted into the container at paths
  that match the configured roots.
- `~/.cloudspace`, `stateDir`, and `worktreeRoot` should be persisted with volumes
  if OAuth clients, token hashes, workspace sessions, and managed worktrees must
  survive container restarts.
- Git, Bash, Node, npm, and any project-specific build/test tools must exist
  inside the image.
- Shell tool execution happens inside the container, not the host, unless host
  files/tools/sockets are mounted in.
- File ownership can become a problem because edits are written by the container
  user.
- Native dependencies matter. `better-sqlite3` and optional `node-pty` must be
  built or installed for the container's Node ABI, OS, libc, and architecture.
- Public URL and Host-header configuration must match the external reverse proxy
  or tunnel endpoint, not just the internal container port.
- Binding `HOST=0.0.0.0` is usually necessary inside Docker, while external
  access should still be protected by OAuth and a trusted tunnel/proxy.
- Docker isolation can reduce host exposure if roots are mounted read/write
  narrowly, but mounting broad host paths or the Docker socket would restore
  broad host-level risk.
