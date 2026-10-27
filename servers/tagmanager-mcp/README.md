# Google Tag Manager MCP Server (read + write)

A local [MCP](https://modelcontextprotocol.io) server that exposes the
[Google Tag Manager API v2](https://developers.google.com/tag-platform/tag-manager/api/v2)
to LLM clients (Claude Desktop, Claude Code CLI, …). It runs as a stdio
subprocess — no hosting, no ports — and authenticates with your local
[Application Default Credentials (ADC)](https://cloud.google.com/docs/authentication/provide-credentials-adc).

> Part of [google-marketing-mcp](../../README.md). This package is
> self-contained — it has no imports from other servers and ships its own
> `pyproject.toml`, so it can be installed on its own.

## Tools 🛠️

All IDs are the **numeric** GTM IDs (not the public `GTM-XXXX` code). Discover
them with `list_accounts` → `list_containers` → `list_workspaces`.

| Group | Tools | Notes |
|---|---|---|
| Discover | `list_accounts`, `list_containers`, `get_container`, `list_workspaces`, `get_workspace` | |
| Tags / triggers / variables | `list_tags`, `get_tag`, `create_tag`, `update_tag`, `delete_tag` 🔒 (same set for `*_trigger`, `*_variable`) | Lists follow every page. |
| Built-in variables | `list_built_in_variables`, `enable_built_in_variables`, `disable_built_in_variables` 🔒 | |
| Workspace changes | `get_workspace_status`, `revert_change` 🔒, `sync_workspace`, `resolve_conflict` 🔒, `create_workspace`, `delete_workspace` 🔒 | `revert_change` undoes one tag/trigger/variable change. |
| Versions | `quick_preview`, `create_version`, `publish_version` 🔒, `list_versions`, `get_version`, `get_live_version`, `compare_live_versions` | `compare_live_versions` diffs two containers (e.g. dev vs prod) by name. |

Create/update/sync only touch a workspace; nothing goes live until you create
and publish a version. A typical change:

1. Edit with `create_*` / `update_*` in a workspace.
2. `get_workspace_status` — check pending changes and merge conflicts. On a
   conflict, `sync_workspace`, then `resolve_conflict` or `revert_change`.
3. `quick_preview` — catch compiler errors.
4. `create_version` → `publish_version`.
5. `compare_live_versions` — confirm dev and prod match.

### Updates merge by default

`update_tag` / `update_trigger` / `update_variable` read the current entity,
change only the fields you pass, and merge `parameter` entries by `key`, so
untouched parameters survive. The write carries the entity's fingerprint and
fails if someone changed it after the read. A list-type parameter such as a
GA4 tag's `eventSettingsTable` is one parameter, so pass its full value to add
a row. Pass `replace=true` to write the full resource (e.g. to remove a
parameter).

### Destructive-operation guard 🔒

Tools marked 🔒 refuse to run unless the server environment sets
`GTM_MCP_ALLOW_DESTRUCTIVE=1`: `delete_*`, `delete_workspace`, `revert_change`,
`resolve_conflict`, `disable_built_in_variables` and `publish_version`. Each
can drop work or change the live container.

## Setup

1. Enable the **Tag Manager API** in your Google Cloud project.
2. Configure ADC with the Tag Manager scopes:

   ```shell
   gcloud auth application-default login \
     --scopes \
     https://www.googleapis.com/auth/tagmanager.readonly,\
   https://www.googleapis.com/auth/tagmanager.edit.containers,\
   https://www.googleapis.com/auth/tagmanager.edit.containerversions,\
   https://www.googleapis.com/auth/tagmanager.publish,\
   https://www.googleapis.com/auth/cloud-platform
   ```

3. Install the server (from this fork, until it has its own repo):

   ```shell
   uv tool install "git+https://github.com/seob717/google-marketing-mcp.git@main#subdirectory=servers/tagmanager-mcp"
   ```

4. Register it with the Claude Code CLI (user scope):

   ```shell
   claude mcp add-json -s user tagmanager-mcp '{
     "command": "'"$HOME"'/.local/bin/tagmanager-mcp",
     "args": [],
     "env": {
       "GOOGLE_APPLICATION_CREDENTIALS": "'"$HOME"'/.config/gcloud/application_default_credentials.json",
       "GOOGLE_CLOUD_PROJECT": "YOUR_PROJECT_ID"
     }
   }'
   ```

   To enable the 🔒 tools, add `"GTM_MCP_ALLOW_DESTRUCTIVE": "1"` to `env`.

   For Claude Desktop, add the same block under `mcpServers` in
   `claude_desktop_config.json`.

## Development

```shell
uv sync --extra dev
uv run pytest
```
