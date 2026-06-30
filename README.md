<p align="center">
  <picture>
    <img src="https://raw.githubusercontent.com/Waishnav/cloudspace/main/docs/assets/cloudspace-logo-light.png" alt="Cloudspace logo" width="140">
  </picture>
</p>

<h1 align="center">Cloudspace</h1>

<p align="center">Bring a Codex-style coding workflow to ChatGPT.</p>

<p align="center">
  <a href="https://www.npmjs.com/package/@waishnav/cloudspace"><img alt="npm" src="https://img.shields.io/npm/v/%40waishnav%2Fcloudspace?style=flat-square" /></a>
  <a href="https://github.com/Waishnav/cloudspace/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/Waishnav/cloudspace/ci.yml?style=flat-square&branch=main" /></a>
  <a href="https://github.com/Waishnav/cloudspace/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/npm/l/%40waishnav%2Fcloudspace?style=flat-square" /></a>
</p>

[![Cloudspace connected to ChatGPT](https://raw.githubusercontent.com/Waishnav/cloudspace/main/docs/assets/cloudspace-screenshot.png)](https://raw.githubusercontent.com/Waishnav/cloudspace/main/docs/assets/cloudspace-screenshot.png)

**Give ChatGPT a secure connection to your own machine and Turn ChatGPT into Codex**

Cloudspace is a self-hosted MCP server that lets ChatGPT read, edit, search, and run code in your real local projects — your files, your tools, your terminal — without uploading anything to a third party. You run it on your machine, expose it through a tunnel you control, and approve the connection with a password only you have.

## Sponsors and Special Thanks

<table>
  <thead>
    <tr>
      <th>Sponsor</th>
      <th>About</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center" width="220">
        <a href="https://rebates.ai/">
          <img
            src="https://app.rebates.ai/brand/rebates-lockup.svg"
            alt="Rebates"
            width="170"
          >
        </a>
      </td>
      <td>
        <strong>The ads in your terminal pay you.</strong><br><br>
        <a href="https://rebates.ai/">Rebates</a> adds one optional
        sponsored footer to your coding agent and pays you cash back for every
        session in which it is shown. Turn it off at any time.
      </td>
    </tr>
  </tbody>
</table>

<p>
  Cloudspace is open to new sponsors.
  <a href="https://x.com/wshxnv">Get in touch to become one.</a>
</p>

## Installation

Cloudspace requires Node `>=22.19 <27`.

Install the Cloudspace CLI:

```bash
npm install -g @waishnav/cloudspace
```

Then initialize and start the server:

```bash
cloudspace init
cloudspace serve
```

Or run it without a global install:

```bash
npx @waishnav/cloudspace init
npx @waishnav/cloudspace serve
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

Build and run Cloudspace locally with Docker Compose:

```bash
export CLOUDSPACE_OAUTH_OWNER_TOKEN="$(openssl rand -base64 32)"
docker compose up --build
```

The container listens on port `3000` and Compose publishes it at:

```text
http://localhost:3000/mcp
```

By default, Compose mounts the current repository at `/workspace` and allows
Cloudspace to open that path. To expose a different local folder, set:

```bash
export CLOUDSPACE_WORKSPACE_PATH="$HOME/projects"
export CLOUDSPACE_ALLOWED_ROOTS="/workspace"
docker compose up --build
```

For tunnel or public deployments, set the public origin without `/mcp`:

```bash
export CLOUDSPACE_PUBLIC_BASE_URL="https://your-tunnel-host.example.com"
docker compose up --build
```

Persistent container data is stored in the named `cloudspace-data` volume:

- `/data/config` for Cloudspace config and auth files
- `/data/state` for SQLite state
- `/data/worktrees` for managed Git worktrees

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

- [Setup Guide](https://github.com/Waishnav/cloudspace/blob/main/docs/setup.md)
- [ChatGPT Coding Workflow](https://github.com/Waishnav/cloudspace/blob/main/docs/chatgpt-coding-workflow.md)
- [Configuration Reference](https://github.com/Waishnav/cloudspace/blob/main/docs/configuration.md)
- [Security Model](https://github.com/Waishnav/cloudspace/blob/main/docs/security.md)
- [Troubleshooting Gotchas](https://github.com/Waishnav/cloudspace/blob/main/docs/gotchas.md)

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

## Built by Waishnav

I'm Waishnav, I like building opinionated products and tools, and Cloudspace is one example of that.
This year, I started my journey to build a single-person and multiple-agents company doing multiple millions in
revenue. If you want to watch the failures, wins, lessons, and everything in
between, come hang out with me on [X](https://x.com/wshxnv).

## More from me

<table>
  <thead>
    <tr>
      <th>Project</th>
      <th>About</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center" width="220">
        <a href="https://gitcms.dev/">
          <img
            src="https://gitcms.dev/brand/gitcms-logo.svg"
            alt="GitCMS"
            width="48"
          /><br />
          <strong>GitCMS</strong>
        </a>
      </td>
      <td>
        <strong>Modern CMS and tooling for markdown based content sites — built for agents and humans.</strong><br><br>
        Visual editing, editorial workflow, and ChatGPT/Claude content agents, with
        every post and page stored as files in your repo.
        <a href="https://gitcms.dev/">Learn more</a>.
      </td>
    </tr>
  </tbody>
</table>

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
