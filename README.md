# Google Marketing MCP

One repo, one setup for managing **Google Analytics (GA4)**, **Google Ads**, and
**Google Tag Manager (GTM)** through MCP — in Claude Desktop and/or the Claude
Code CLI. A single `setup.sh` installs the servers, signs you in once (shared
ADC, union of scopes), enables the required APIs, and registers everything into
the clients you choose.

## What you get

| Server | Package | Source | Capability |
|---|---|---|---|
| Google Analytics | `analytics-mcp` | [our GA fork](https://github.com/seob717/google-analytics-mcp) | reporting (Data API) **+ read-only admin** (data streams, change history) |
| Google Ads | `google-ads-mcp` | official PyPI | read-only ads reporting |
| Google Tag Manager | `tagmanager-mcp` | `servers/tagmanager-mcp` (this repo) | **read + write** (tags/triggers/variables, versions, publish) |

The GA server is installed from our fork rather than PyPI because it adds the
read-only Admin tools (data streams, `getGlobalSiteTag`, Change History) that the
official package doesn't ship. GTM's destructive ops (delete/publish) stay gated
behind `GTM_MCP_ALLOW_DESTRUCTIVE=1`.

## Quick start (macOS)

```shell
curl -fsSL https://raw.githubusercontent.com/seob717/google-marketing-mcp/main/setup.sh -o /tmp/gmm-setup.sh && bash /tmp/gmm-setup.sh
```

The script:

1. Asks which **servers** to install — `space` to toggle **Google Analytics** /
   **Google Ads** / **Google Tag Manager** (any subset, e.g. GA only). Skip with
   `GA_MCP_SERVERS=ga,ads,gtm`.
2. Asks which **clients** to set up — `space` to toggle **Claude Desktop** /
   **Claude Code CLI** (or `GA_MCP_TARGETS=desktop,cli`).
3. Installs the servers via `uv`, installs the Google Cloud SDK if missing.
4. Signs you in once (ADC) with the union of scopes for whichever servers you chose.
5. Enables the required APIs and registers the servers into your clients.

Non-interactive example (CLI, all three):

```shell
GA_MCP_TARGETS=cli GA_MCP_WITH_ADS=1 GA_MCP_ADS_DEV_TOKEN=xxx GA_MCP_WITH_GTM=1 bash /tmp/gmm-setup.sh
```

### Scopes note

Most reads work with `analytics.readonly`. GA4 **Change History** additionally
requires the broader `analytics.edit` scope — add it to the ADC login only if you
want that tool.

## Layout

```
google-marketing-mcp/
  setup.sh                     # unified installer
  servers/
    tagmanager-mcp/            # GTM MCP server (read + write)
      pyproject.toml
      tagmanager_mcp/
      tests/
```

GA and Ads are not vendored here — the installer pulls them from their own
sources (GA fork / PyPI). Override any source via `GA_INSTALL_SOURCE`,
`ADS_PACKAGE`, or `GTM_INSTALL_SOURCE`.

## Develop the GTM server

```shell
cd servers/tagmanager-mcp
uv sync --extra dev
uv run pytest
```
