# Google Marketing MCP

One repo, one setup for managing **Google Analytics (GA4)**, **Google Ads**, and
**Google Tag Manager (GTM)** through MCP — in Claude Desktop and/or the Claude
Code CLI. A single `setup.sh` installs the servers, signs you in once (shared
ADC, union of scopes), enables the required APIs, and registers everything into
the clients you choose.

## What you get

| Server | Package | Source | Capability |
|---|---|---|---|
| Google Analytics | `analytics-mcp` | official PyPI | reporting (Data API) |
| Google Analytics Admin | `ga4-admin-mcp` | `servers/ga4-admin-mcp` (this repo) | read-only admin: data streams, `getGlobalSiteTag`, change history |
| Google Ads | `google-ads-mcp` | official PyPI | read-only ads reporting |
| Google Tag Manager | `tagmanager-mcp` | `servers/tagmanager-mcp` (this repo) | **read + write** (tags/triggers/variables, versions, publish) |

**Design:** the official servers (GA, Ads) install straight from PyPI, so they
track their own upstream automatically. Our own additions — GA Admin and GTM —
live here under `servers/`. No fork to maintain. GA Admin is separate from GA
reporting because its change-history tool needs the broader `analytics.edit`
scope; GTM's destructive ops (delete/publish) stay gated behind
`GTM_MCP_ALLOW_DESTRUCTIVE=1`.

## Quick start (macOS)

```shell
curl -fsSL https://raw.githubusercontent.com/seob717/google-marketing-mcp/main/setup.sh -o /tmp/gmm-setup.sh && bash /tmp/gmm-setup.sh
```

The script:

1. Asks which **clients** to set up — one `y/N` line each for **Claude Desktop**
   and **Claude Code CLI** (or pin with `GA_MCP_TARGETS=desktop,cli`).
2. Asks which **servers** to install — one `y/N` line each for **Google
   Analytics** / **Google Analytics Admin** / **Google Ads** / **Google Tag
   Manager** (all default to yes; answer `n` to skip any). Pin the whole set
   with `GA_MCP_SERVERS=ga,ga-admin,ads,gtm`.
3. Installs the servers via `uv`, installs the Google Cloud SDK if missing.
4. Signs you in once (ADC) with the union of scopes for whichever servers you chose.
5. Enables the required APIs and registers the servers into your clients.

Non-interactive example (CLI, all three):

```shell
GA_MCP_TARGETS=cli GA_MCP_WITH_ADS=1 GA_MCP_ADS_DEV_TOKEN=xxx GA_MCP_WITH_GTM=1 bash /tmp/gmm-setup.sh
```

### Scopes note

Most reads work with `analytics.readonly`. Selecting **Google Analytics Admin**
adds the broader `analytics.edit` scope (its change-history tool requires it).
Selecting **Google Ads** adds the `adwords` scope. The installer requests the
union in a single ADC login.

## Layout

```
google-marketing-mcp/
  setup.sh                     # unified installer
  servers/
    ga4-admin-mcp/            # GA4 Admin MCP server (read-only)
    tagmanager-mcp/          # GTM MCP server (read + write)
```

GA reporting and Ads aren't vendored here — the installer pulls them from PyPI.
Override any source via `GA_PACKAGE`, `ADS_PACKAGE`, `GA_ADMIN_INSTALL_SOURCE`,
or `GTM_INSTALL_SOURCE`.

## Develop the servers

```shell
cd servers/ga4-admin-mcp   # or servers/tagmanager-mcp
uv sync --extra dev
uv run pytest
```
