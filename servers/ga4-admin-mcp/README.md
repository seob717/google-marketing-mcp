# GA4 Admin MCP Server (read + write)

A local [MCP](https://modelcontextprotocol.io) server exposing the parts of the
[Google Analytics Admin API](https://developers.google.com/analytics/devguides/config/admin/v1)
that the official `analytics-mcp` (Data API / reporting) can't see:

**Read**

- `list_data_streams` / `get_data_stream` — data stream setup + measurement IDs
- `get_global_site_tag` — the stream's gtag (`G-XXXX`) snippet
- `search_change_history_events` — who changed what config, and when
- `list_custom_dimensions` / `list_custom_metrics` / `list_key_events` —
  definitions **with their IDs**. The Data API's metadata reports only
  `api_name`/`ui_name`; the numeric ID these return is what the update and
  archive tools take.

**Write**

- `create_custom_dimension` / `update_custom_dimension` — register an event
  parameter so it becomes reportable
- `create_custom_metric` / `update_custom_metric` — same, for numeric parameters
- `create_key_event` / `update_key_event` — mark an event as a conversion
- `archive_custom_dimension` / `archive_custom_metric` / `delete_key_event` —
  destructive, gated (see below)

> GA4 does **not** backfill. A parameter your app already sends stays invisible
> in reports until it is registered, and only data collected after registration
> becomes reportable — so registering early matters.

> Part of [google-marketing-mcp](../../README.md). Runs alongside the official
> `analytics-mcp` (installed from PyPI) rather than forking it — so reporting
> tracks upstream automatically and these admin tools stay your own.

## Scopes

- Data stream reads work with `analytics.readonly`.
- **Change history and every write tool require the broader `analytics.edit`
  scope.**

## Destructive operations

`archive_*` and `delete_key_event` refuse to run unless the server environment
sets:

```shell
GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE=1
```

Create and update are not gated. Archiving frees a custom
dimension/metric slot and removes the definition from reports; historical data
is not deleted. `delete_key_event` only unmarks the conversion — the event keeps
being collected.

## Transport

The client uses gRPC by default. On hosts where gRPC's built-in DNS resolver
can't reach port 53 (`Could not contact DNS servers`), set
`GRPC_DNS_RESOLVER=native` in the server env first; if that isn't enough,
`GA4_ADMIN_MCP_TRANSPORT=rest` switches the Admin API client to REST/HTTPS.
See the [root troubleshooting guide](../../README.md#gaads-servers-cant-resolve-dns-grpc).

## Not included

**Connected site tags** — the GA4 Admin API exposes no method for them, so they
can only be inspected in the GA4 Admin UI.

**Explorations** (`/analysis/...` reports) — Google publishes no API for them at
all, so they cannot be listed, created, or edited from here. GA4 UI only.

## Develop

```shell
cd servers/ga4-admin-mcp
uv sync --extra dev
uv run pytest
```
