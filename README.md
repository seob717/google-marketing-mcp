# Google Marketing MCP

One repo, one setup for managing **Google Analytics (GA4)**, **Google Ads**, and
**Google Tag Manager (GTM)** through MCP — in Claude Desktop and/or the Claude
Code CLI. A single `setup.sh` installs the servers, signs you in once (shared
ADC, union of scopes), enables the required APIs, and registers everything into
the clients you choose.

## What you get

| Server | Package | Source | Capability |
|---|---|---|---|
| Google Analytics | `analytics-mcp` | official PyPI | reporting (Data API): `run_report`, `run_realtime_report`, `run_funnel_report`, account/property lookups |
| Google Analytics Admin | `ga4-admin-mcp` | `servers/ga4-admin-mcp` (this repo) | read-only admin: `list_data_streams`, `get_global_site_tag`, `search_change_history_events` |
| Google Ads | `google-ads-mcp` | official PyPI | read-only ads reporting (GAQL `search`, accessible customers) |
| Google Tag Manager | `tagmanager-mcp` | `servers/tagmanager-mcp` (this repo) | **read + write**: tags/triggers/variables, versions, publish |

**Design:** the official servers (GA, Ads) install straight from PyPI, so they
track their own upstream automatically. Our own additions — GA Admin and GTM —
live here under `servers/`. No fork to maintain. GA Admin is separate from GA
reporting because its change-history tool needs the broader `analytics.edit`
scope; GTM's destructive ops (delete/publish) stay gated behind
`GTM_MCP_ALLOW_DESTRUCTIVE=1`.

## Requirements

- **macOS** — the installer is macOS-only and exits on other platforms.
- **Claude Desktop** and/or the **Claude Code CLI** (`claude`). The installer
  skips the CLI target automatically when the binary isn't on your `PATH`.
- A **Google account with access to the properties you want to read**, and a
  Google Cloud project (the installer can create one for you).
- No Homebrew, no manual Python — `uv` and the Google Cloud SDK are installed
  for you if missing.

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
3. For **Ads**, asks for a developer token (and an MCC customer ID if you go
   through a manager account). No token → Ads is skipped.
4. For **GTM**, asks whether to allow destructive writes (delete / publish).
   Default is no.
5. Installs the servers via `uv`, installs the Google Cloud SDK if missing.
6. Signs you in once (ADC) with the union of scopes for whichever servers you chose.
7. Enables the required APIs and registers the servers into your clients.

Re-running the script is safe: it upgrades what's installed, backs up your
Claude Desktop config before touching it, and re-registers CLI entries in place.
The only repeated cost is the ADC browser sign-in.

Non-interactive example (CLI only, all four servers):

```shell
GA_MCP_TARGETS=cli \
GA_MCP_SERVERS=ga,ga-admin,ads,gtm \
GA_MCP_PROJECT=my-gcp-project \
GA_MCP_ADS_DEV_TOKEN=xxx \
GTM_MCP_ALLOW_DESTRUCTIVE=1 \
bash /tmp/gmm-setup.sh
```

### Environment variables

| Variable | Effect |
|---|---|
| `GA_MCP_TARGETS` | Comma list of `desktop`, `cli`. Skips the client prompt. |
| `GA_MCP_SERVERS` | Comma list of `ga`, `ga-admin`, `ads`, `gtm`. Skips the server prompt. |
| `GA_MCP_PROJECT` | Google Cloud project ID. Skips the project prompt. |
| `GA_MCP_ADS_DEV_TOKEN` | Google Ads developer token ([API Center](https://ads.google.com/aw/apicenter)). |
| `GA_MCP_ADS_LOGIN_CUSTOMER_ID` | MCC (manager) customer ID; dashes are stripped. |
| `GTM_MCP_ALLOW_DESTRUCTIVE` | `1` enables GTM `delete_*` and `publish_version`. |
| `GA4_ADMIN_MCP_TRANSPORT` | `rest` makes `ga4-admin-mcp` call Google over HTTPS instead of gRPC (see [Troubleshooting](#troubleshooting)). Default: gRPC. |
| `GA_PACKAGE` / `ADS_PACKAGE` | Override the PyPI package installed for GA / Ads. |
| `GA_ADMIN_INSTALL_SOURCE` / `GTM_INSTALL_SOURCE` | Override the install source for the two servers in this repo (e.g. a local path while developing). |

`GA_MCP_WITH_ADS=1` / `GA_MCP_WITH_GTM=1` are a fallback for fully
non-interactive runs (no TTY) where `GA_MCP_SERVERS` isn't set — there GA is on
by default and these two opt the extras in. Prefer `GA_MCP_SERVERS`.

### Scopes note

Most reads work with `analytics.readonly`. Selecting **Google Analytics Admin**
adds the broader `analytics.edit` scope (its change-history tool requires it).
Selecting **Google Ads** adds the `adwords` scope, and **GTM** adds the
`tagmanager.*` scopes. The installer requests the union in a single ADC login.

⚠️ ADC is a **single credentials file**. Any later `gcloud auth
application-default login` — including another installer that requests fewer
scopes — overwrites it and can break the servers you already set up. If that
happens, just re-run `setup.sh`.

## After installing

**Verify**

- Claude Desktop: quit it completely (⌘Q) and reopen, then ask
  `내 Google Analytics 속성 목록을 보여줘`.
- Claude Code CLI: `claude mcp list`.

**Update**

Re-running `setup.sh` is the reliable path — it upgrades the PyPI servers and
reinstalls the git-sourced ones. Manually:

```shell
uv tool upgrade analytics-mcp google-ads-mcp
uv tool install --force "git+https://github.com/seob717/google-marketing-mcp.git@main#subdirectory=servers/ga4-admin-mcp"
uv tool install --force "git+https://github.com/seob717/google-marketing-mcp.git@main#subdirectory=servers/tagmanager-mcp"
```

**Uninstall**

```shell
uv tool uninstall analytics-mcp ga4-admin-mcp google-ads-mcp tagmanager-mcp
claude mcp remove -s user analytics-mcp   # repeat per server, CLI only
```

For Claude Desktop, delete the entries under `mcpServers` in
`~/Library/Application Support/Claude/claude_desktop_config.json`, or restore
one of the `claude_desktop_config.json.bak.*` backups the installer left.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Servers don't show up in Claude Desktop | Quit with ⌘Q (closing the window isn't enough) and reopen. |
| A server binary is missing after install | Read `/tmp/ga-mcp-install.log` — the installer writes every `uv tool install` there. |
| `API 활성화 권한이 없습니다` warning | You're not owner/editor on the project. Ask an admin to enable the listed APIs once; the step passes automatically afterwards. |
| `search_change_history_events` returns a permission error | Its `analytics.edit` scope is missing from ADC. Re-run `setup.sh` with GA Admin selected. |
| GA servers fail with `Could not contact DNS servers` while GTM works on the same host | gRPC DNS issue, not the network — see [GA servers can't resolve DNS](#ga-servers-cant-resolve-dns-grpc) below. |
| `403 ... quota project` / `API has not been used in project` | See [403 after DNS is fixed](#403-after-dns-is-fixed) below. |
| gcloud fails to start | The installer pins a `uv`-managed Python 3.12 via `CLOUDSDK_PYTHON` when the system `python3` is too old; re-run it if you hit this outside the script. |
| Ads was silently skipped | No developer token was given. Get one at the [API Center](https://ads.google.com/aw/apicenter) and re-run. |
| GTM delete/publish refuses to run | Expected — add `GTM_MCP_ALLOW_DESTRUCTIVE=1` to the `tagmanager-mcp` env, or re-run and answer `y`. |

**Note:** the Ads developer token is stored in plain text in the client config.

### GA servers can't resolve DNS (gRPC)

Symptom: `analytics-mcp` / `ga4-admin-mcp` fail with
`Could not contact DNS servers`, but `tagmanager-mcp` (and `curl`) reach
Google fine from the same machine.

Cause: `tagmanager-mcp` uses `google-api-python-client` (REST over HTTPS), so
it goes through the OS resolver and any HTTPS proxy. The two GA servers use
`google-analytics-data` / `google-analytics-admin`, whose default transport is
**gRPC**. gRPC doesn't use the OS resolver — it ships its own (c-ares) that
sends raw UDP queries to port 53. Sandboxed / proxied hosts typically allow
outbound 443 only and block raw UDP/53, so c-ares fails; that message is its
error string.

Fix — set one env var on the MCP server process:

```
GRPC_DNS_RESOLVER=native
```

This makes gRPC use the OS `getaddrinfo` like everything else. `setup.sh`
already puts it (plus `GOOGLE_CLOUD_QUOTA_PROJECT`) in both GA server blocks;
if you wired the servers by hand, add it yourself:

```json
"analytics-mcp": {
  "command": "...",
  "args": [],
  "env": {
    "GRPC_DNS_RESOLVER": "native",
    "GOOGLE_CLOUD_QUOTA_PROJECT": "your-project-id"
  }
}
```

Do the same for `ga4-admin-mcp`. Docker → `-e`, systemd → `Environment=`,
hosted → that service's env settings. Restart the MCP servers afterwards
(Claude Desktop: ⌘Q and reopen).

If that's still not enough, `ga4-admin-mcp` can skip gRPC entirely: set
`GA4_ADMIN_MCP_TRANSPORT=rest` in its env (or run
`GA4_ADMIN_MCP_TRANSPORT=rest bash setup.sh`). It then talks REST/HTTPS, the
same path the GTM server already proves works. (`analytics-mcp` is the
official upstream package, so only the env-var fix applies to it.)

### 403 after DNS is fixed

With user-account ADC (`gcloud auth application-default login`) and no quota
project, Google returns 403 for Analytics (and GTM) calls. `setup.sh` handles
this, but if you signed in manually:

```shell
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

and make sure **Google Analytics Data API** and **Google Analytics Admin API**
are enabled on that project. Then restart the servers and retry
`get_account_summaries`.

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
