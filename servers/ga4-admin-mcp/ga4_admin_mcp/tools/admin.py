# Copyright 2026 seob717
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Read-only GA4 Admin tools: data streams and change history.

Exposes property configuration the Data API can't see. Data stream reads work
with analytics.readonly; change history requires the broader analytics.edit
scope (per the Admin API). "connected site tags" are intentionally absent — the
Admin API has no method for them (GA4 UI only).
"""

import asyncio
from typing import Any, Dict, List, Optional

from google.analytics import admin_v1alpha

from ga4_admin_mcp.tools.client import create_admin_alpha_client
from ga4_admin_mcp.tools.utils import (
    account_rn,
    construct_property_rn,
    data_stream_rn,
    parse_time,
    proto_to_dict,
)


async def list_data_streams(property_id: int | str) -> List[Dict[str, Any]]:
    """Lists the data streams (web/app) configured for a GA4 property.

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
    """
    request = admin_v1alpha.ListDataStreamsRequest(
        parent=construct_property_rn(property_id)
    )

    def _sync_call():
        pager = create_admin_alpha_client().list_data_streams(request=request)
        return [proto_to_dict(page) for page in pager]

    return await asyncio.to_thread(_sync_call)


async def get_data_stream(
    property_id: int | str, data_stream_id: int | str
) -> Dict[str, Any]:
    """Returns configuration for a single data stream, including its measurement ID.

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
        data_stream_id: The numeric data stream ID.
    """
    request = admin_v1alpha.GetDataStreamRequest(
        name=data_stream_rn(property_id, data_stream_id)
    )

    def _sync_call():
        return proto_to_dict(
            create_admin_alpha_client().get_data_stream(request=request)
        )

    return await asyncio.to_thread(_sync_call)


async def get_global_site_tag(
    property_id: int | str, data_stream_id: int | str
) -> Dict[str, Any]:
    """Returns the gtag (G-XXXX) snippet for a web data stream.

    Note: this is the stream's own tag, NOT 'connected site tags' (which the
    Admin API does not expose).

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
        data_stream_id: The numeric web data stream ID.
    """
    request = admin_v1alpha.GetGlobalSiteTagRequest(
        name=f"{data_stream_rn(property_id, data_stream_id)}/globalSiteTag"
    )

    def _sync_call():
        return proto_to_dict(
            create_admin_alpha_client().get_global_site_tag(request=request)
        )

    return await asyncio.to_thread(_sync_call)


async def search_change_history_events(
    account_id: int | str,
    property_id: Optional[int | str] = None,
    resource_types: Optional[List[str]] = None,
    actions: Optional[List[str]] = None,
    actor_email: Optional[str] = None,
    earliest_change_time: Optional[str] = None,
    latest_change_time: Optional[str] = None,
    page_size: int = 200,
) -> List[Dict[str, Any]]:
    """Searches the GA4 Change History (who changed what configuration, and when).

    Requires the analytics.edit scope. Scoped to an account; filter by property,
    resource type, action, actor, and time window to pinpoint a change.

    Args:
        account_id: The numeric GA4 account ID (parent of the change history).
        property_id: Optional property to scope to (number or 'properties/NUMBER').
        resource_types: Optional list, e.g. ["DATA_STREAM", "GOOGLE_ADS_LINK",
          "PROPERTY", "ATTRIBUTION_SETTINGS", "BIGQUERY_LINK",
          "ENHANCED_MEASUREMENT_SETTINGS"].
        actions: Optional list of "CREATED", "UPDATED", "DELETED".
        actor_email: Optional email of the user who made the change.
        earliest_change_time: Optional ISO 8601 lower bound, e.g. "2026-07-04T00:00:00Z".
        latest_change_time: Optional ISO 8601 upper bound, e.g. "2026-07-06T00:00:00Z".
        page_size: Max events to return (default 200).
    """
    kwargs: Dict[str, Any] = {
        "account": account_rn(account_id),
        "page_size": page_size,
    }
    if property_id is not None:
        kwargs["property"] = construct_property_rn(property_id)
    if resource_types:
        kwargs["resource_type"] = [
            admin_v1alpha.ChangeHistoryResourceType[r.strip().upper()]
            for r in resource_types
        ]
    if actions:
        kwargs["action"] = [
            admin_v1alpha.ActionType[a.strip().upper()] for a in actions
        ]
    if actor_email:
        kwargs["actor_email"] = actor_email
    if earliest_change_time:
        kwargs["earliest_change_time"] = parse_time(earliest_change_time)
    if latest_change_time:
        kwargs["latest_change_time"] = parse_time(latest_change_time)

    request = admin_v1alpha.SearchChangeHistoryEventsRequest(**kwargs)

    def _sync_call():
        pager = create_admin_alpha_client().search_change_history_events(
            request=request
        )
        return [proto_to_dict(page) for page in pager]

    return await asyncio.to_thread(_sync_call)
