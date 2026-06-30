<h1 align="center">Cloudspace</h1>

<p align="center">Bring a Codex-style coding workflow to ChatGPT.</p>

**Give ChatGPT a secure connection to your own machine and Turn ChatGPT into Codex**

Cloudspace is a self-hosted MCP server that lets ChatGPT read, edit, search, and run code in your real local projects — your files, your tools, your terminal — without uploading anything to a third party. You run it on your machine, expose it through a tunnel you control, and approve the connection with a password only you have.

## Installation

Cloudspace requires Node `>=22.19 <27`.

Install the Cloudspace CLI:

```bash
npm install -g cloudspace
```

Then initialize and start the server:

```bash
cloudspace init
cloudspace serve
```

Or run it without a global install:

```bash
npx cloudspace init
npx cloudspace serve
```

During setup, Cloudspace asks for:

- the local project folders ChatGPT is allowed to open through Cloudspace
- the local port, usually `7676`
- your public HTTPS base URL from Cloudflare Tunnel, ngrok, Pinggy, Tailscale Funnel, or
  another reverse proxy

Use the public origin without `/mcp` during setup:

```text
https://your-tunnel-host.example.com
```

You will configure your MCP client with the public `/mcp` URL after setup.

When the client connects, Cloudspace opens an Owner password approval page. Enter
the Owner password printed by `cloudspace init`. It is also stored in:

```text
~/.cloudspace/auth.json
```

Keep that password private.

## Connect Your MCP Client

The default local endpoint is:

```text
http://127.0.0.1:7676/mcp
```

Most users should connect through a public HTTPS tunnel:

```text
https://your-tunnel-host.example.com/mcp
```

> [!NOTE]
> Using Cloudspace as an MCP connector isn't against OpenAI's Usage Policies — it's
> a standard custom App/connector setup, and writing or running code isn't a
> restricted use case. But your account is governed by your usage, not by
> Cloudspace. Don't point it at anything that would violate your provider's terms.
> Used normally, you're fine. (Based on OpenAI's Usage Policies and Service Terms
> as of June 2026.)

## Docker

Build and run Cloudspace behind Caddy with Docker Compose:

```bash
export CLOUDSPACE_HOSTNAME="cloudspace.example.com"
export CLOUDSPACE_OAUTH_OWNER_TOKEN="$(openssl rand -base64 32)"
docker compose up --build
```

Caddy is the only service published to the host, on ports `80` and `443`.
Cloudspace listens on port `3000` only inside Docker's private service network,
and Caddy reverse proxies to it. Configure your MCP client with:

```text
https://cloudspace.example.com/mcp
```

By default, Compose sets `CLOUDSPACE_PUBLIC_BASE_URL` to
`https://$CLOUDSPACE_HOSTNAME`. If you need to override the public origin, set it
without `/mcp`:

```bash
export CLOUDSPACE_PUBLIC_BASE_URL="https://your-public-host.example.com"
docker compose up --build
```

By default, Compose mounts the current repository at `/workspace` and allows
Cloudspace to open that path. To expose a different local folder, set:

```bash
export CLOUDSPACE_WORKSPACE_PATH="$HOME/projects"
export CLOUDSPACE_ALLOWED_ROOTS="/workspace"
docker compose up --build
```

Persistent Cloudspace data is stored in the named `cloudspace-data` volume:

- `/data/config` for Cloudspace config and auth files
- `/data/state` for SQLite state
- `/data/worktrees` for managed Git worktrees

Caddy stores certificates and runtime state in `caddy-data` and `caddy-config`.

The image also declares `/workspace` as a volume for project files. Health
checks call `http://127.0.0.1:3000/healthz`.

## What ChatGPT Can Do

Once connected, ChatGPT can open one of your approved project folders as a
workspace. From there, it can inspect the repo, make scoped edits, run commands,
and show you what changed.

Cloudspace gives ChatGPT tools to:

- read, write, and edit files inside the opened workspace
- search code and inspect directories
- run shell commands for tests, builds, git, and package scripts
- use isolated Git worktrees for parallel coding sessions
- follow project instructions from `AGENTS.md` and `CLAUDE.md`
- discover local agent skills from your skill folders
- show tool cards and optional change summaries in ChatGPT Apps-compatible hosts

## Mental Model

Cloudspace is remote access to selected local folders.

You decide which roots are allowed. The MCP client still has powerful local
capabilities inside an opened workspace, including shell execution. Treat a
connected client like a trusted coding partner with access to your machine.

For a normal ChatGPT coding session:

1. Start your tunnel.
2. Run `cloudspace serve`.
3. Connect the MCP client to your public `/mcp` URL.
4. Approve the connection with the Owner password.
5. Ask ChatGPT to open a project inside one of your allowed roots.

## Platform Support

Cloudspace supports Linux, macOS, and Windows environments with a Bash-compatible
shell.

| Platform                                          | Status            | Notes                                          |
| ------------------------------------------------- | ----------------- | ---------------------------------------------- |
| Linux                                             | Supported         | Requires Node, npm, Git, and Bash.             |
| macOS                                             | Supported         | Requires Node, npm, Git, and Bash.             |
| Windows with Git Bash, WSL, MSYS2, or Cygwin Bash | Supported         | Git Bash is the simplest native Windows setup. |
| Windows PowerShell or `cmd.exe` only              | Not supported yet | Install Git Bash or use WSL.                   |

Run this to inspect your local setup:

```bash
cloudspace doctor
```

## Documentation

- [Setup Guide](docs/setup.md)
- [ChatGPT Coding Workflow](docs/chatgpt-coding-workflow.md)
- [Configuration Reference](docs/configuration.md)
- [Security Model](docs/security.md)
- [Troubleshooting Gotchas](docs/gotchas.md)

## Philosophy

Every piece of software is becoming conversational. Natural language is
redefining how we interact with tools, workflows, and systems.

My bet is that ChatGPT becomes the operating system for everything. Once we
reach AGI, we will simply talk to ChatGPT, and it will prompt, coordinate, and
orchestrate sub-agents that set up the right loops for us.

We are not there yet.

Cloudspace is one attempt to fast-forward that future: a way for MCP-capable
hosts like ChatGPT and Claude to work directly with local project files through
explicit, inspectable tools.

## Attribution

Cloudspace is forked from Waishnav/devspace and remains available under the MIT license. The original copyright notice is preserved in [LICENSE](LICENSE).

## Local Development

For working on Cloudspace itself:

```bash
npm install --include=dev
npm run dev
npm run typecheck
npm test
npm run build
npm run start
```
