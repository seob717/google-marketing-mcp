# GA4 Admin MCP Server (read-only)

A local [MCP](https://modelcontextprotocol.io) server exposing the parts of the
[Google Analytics Admin API](https://developers.google.com/analytics/devguides/config/admin/v1)
that the official `analytics-mcp` (Data API / reporting) can't see:

- `list_data_streams` / `get_data_stream` — data stream setup + measurement IDs
- `get_global_site_tag` — the stream's gtag (`G-XXXX`) snippet
- `search_change_history_events` — who changed what config, and when

> Part of [google-marketing-mcp](../../README.md). Runs alongside the official
> `analytics-mcp` (installed from PyPI) rather than forking it — so reporting
> tracks upstream automatically and these admin tools stay your own.

## Scopes

- Data stream reads work with `analytics.readonly`.
- **Change history requires the broader `analytics.edit` scope** (Admin API
  requirement — even though this server only reads).

## Transport

The client uses gRPC by default. On hosts where gRPC's built-in DNS resolver
can't reach port 53 (`Could not contact DNS servers`), set
`GRPC_DNS_RESOLVER=native` in the server env first; if that isn't enough,
`GA4_ADMIN_MCP_TRANSPORT=rest` switches the Admin API client to REST/HTTPS.
See the [root troubleshooting guide](../../README.md#ga-servers-cant-resolve-dns-grpc).

## Not included

**Connected site tags** — the GA4 Admin API exposes no method for them, so they
can only be inspected in the GA4 Admin UI.

## Develop

```shell
cd servers/ga4-admin-mcp
uv sync --extra dev
uv run pytest
```
