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

"""Write tools for GA4 property configuration.

Custom dimensions and metrics register event parameters so they become
reportable — GA4 does not backfill, so a parameter is invisible in reports
until it is registered. Key events mark an event as a conversion.

Create and update apply immediately. Archive and delete are destructive and
require GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE=1 in the server environment.
"""

import asyncio
from typing import Any, Dict, Optional

from google.analytics import admin_v1alpha

from ga4_admin_mcp.tools.client import create_admin_alpha_client
from ga4_admin_mcp.tools.utils import (
    build_update_mask,
    construct_property_rn,
    custom_dimension_rn,
    custom_metric_rn,
    ensure_destructive_allowed,
    key_event_rn,
    proto_to_dict,
    to_field_mask,
)


async def _run(build_request):
    """Executes a client call off the event loop and returns a plain dict."""

    def _sync_call():
        return proto_to_dict(build_request(create_admin_alpha_client()))

    return await asyncio.to_thread(_sync_call)


# --- custom dimensions --------------------------------------------------------


async def create_custom_dimension(
    property_id: int | str,
    parameter_name: str,
    display_name: str,
    scope: str = "EVENT",
    description: Optional[str] = None,
    disallow_ads_personalization: Optional[bool] = None,
) -> Dict[str, Any]:
    """Registers an event parameter as a custom dimension so it can be reported on.

    GA4 does not backfill: data collected before registration stays unreportable.

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
        parameter_name: The event parameter name as sent, e.g. "plan_subscription".
          For USER scope this is the user property name.
        display_name: The name shown in the GA4 UI, e.g. "Subscription plan".
        scope: "EVENT" (default), "USER", or "ITEM".
        description: Optional description shown in the UI.
        disallow_ads_personalization: Optional; True marks the dimension as NPA
          (no ads personalization). Only valid for USER-scoped dimensions.
    """
    dimension = admin_v1alpha.CustomDimension(
        parameter_name=parameter_name,
        display_name=display_name,
        scope=admin_v1alpha.CustomDimension.DimensionScope[scope.strip().upper()],
    )
    if description is not None:
        dimension.description = description
    if disallow_ads_personalization is not None:
        dimension.disallow_ads_personalization = disallow_ads_personalization

    request = admin_v1alpha.CreateCustomDimensionRequest(
        parent=construct_property_rn(property_id), custom_dimension=dimension
    )
    return await _run(lambda client: client.create_custom_dimension(request=request))


async def update_custom_dimension(
    property_id: int | str,
    custom_dimension_id: int | str,
    display_name: Optional[str] = None,
    description: Optional[str] = None,
    disallow_ads_personalization: Optional[bool] = None,
) -> Dict[str, Any]:
    """Updates a custom dimension's display name, description, or NPA flag.

    parameter_name and scope are immutable in GA4 — changing either means
    archiving the dimension and creating a new one.

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
        custom_dimension_id: The numeric custom dimension ID (from
          list_custom_dimensions).
        display_name: Optional new UI name.
        description: Optional new description.
        disallow_ads_personalization: Optional new NPA flag.
    """
    fields = {
        "display_name": display_name,
        "description": description,
        "disallow_ads_personalization": disallow_ads_personalization,
    }
    update_mask = build_update_mask(fields)

    dimension = admin_v1alpha.CustomDimension(
        name=custom_dimension_rn(property_id, custom_dimension_id),
        **{name: fields[name] for name in update_mask},
    )
    request = admin_v1alpha.UpdateCustomDimensionRequest(
        custom_dimension=dimension, update_mask=to_field_mask(update_mask)
    )
    return await _run(lambda client: client.update_custom_dimension(request=request))


async def archive_custom_dimension(
    property_id: int | str, custom_dimension_id: int | str
) -> Dict[str, str]:
    """Archives a custom dimension. Destructive: requires GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE=1.

    Archiving frees one of the property's custom dimension slots and stops the
    dimension appearing in reports. Historical data is not deleted.

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
        custom_dimension_id: The numeric custom dimension ID.
    """
    ensure_destructive_allowed("archive_custom_dimension")
    name = custom_dimension_rn(property_id, custom_dimension_id)
    request = admin_v1alpha.ArchiveCustomDimensionRequest(name=name)

    def _sync_call():
        create_admin_alpha_client().archive_custom_dimension(request=request)
        return {"archived": name}

    return await asyncio.to_thread(_sync_call)


# --- custom metrics -----------------------------------------------------------


async def create_custom_metric(
    property_id: int | str,
    parameter_name: str,
    display_name: str,
    measurement_unit: str = "STANDARD",
    scope: str = "EVENT",
    description: Optional[str] = None,
) -> Dict[str, Any]:
    """Registers a numeric event parameter as a custom metric.

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
        parameter_name: The event parameter name as sent, e.g. "renewal_count".
        display_name: The name shown in the GA4 UI, e.g. "Renewal count".
        measurement_unit: "STANDARD" (default), "CURRENCY", "FEET", "METERS",
          "KILOMETERS", "MILES", "MILLISECONDS", "SECONDS", "MINUTES", or "HOURS".
          CURRENCY metrics require the value in the property's currency.
        scope: "EVENT" (default) is the only scope GA4 supports for custom metrics.
        description: Optional description shown in the UI.
    """
    metric = admin_v1alpha.CustomMetric(
        parameter_name=parameter_name,
        display_name=display_name,
        measurement_unit=admin_v1alpha.CustomMetric.MeasurementUnit[
            measurement_unit.strip().upper()
        ],
        scope=admin_v1alpha.CustomMetric.MetricScope[scope.strip().upper()],
    )
    if description is not None:
        metric.description = description

    request = admin_v1alpha.CreateCustomMetricRequest(
        parent=construct_property_rn(property_id), custom_metric=metric
    )
    return await _run(lambda client: client.create_custom_metric(request=request))


async def update_custom_metric(
    property_id: int | str,
    custom_metric_id: int | str,
    display_name: Optional[str] = None,
    description: Optional[str] = None,
    measurement_unit: Optional[str] = None,
) -> Dict[str, Any]:
    """Updates a custom metric's display name, description, or measurement unit.

    parameter_name and scope are immutable in GA4.

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
        custom_metric_id: The numeric custom metric ID (from list_custom_metrics).
        display_name: Optional new UI name.
        description: Optional new description.
        measurement_unit: Optional new unit, e.g. "MILLISECONDS". GA4 rejects
          "CURRENCY" here — it can only be set when the metric is created, so
          switching a metric to CURRENCY means archiving and recreating it.
    """
    unit = (
        admin_v1alpha.CustomMetric.MeasurementUnit[measurement_unit.strip().upper()]
        if measurement_unit is not None
        else None
    )
    fields = {
        "display_name": display_name,
        "description": description,
        "measurement_unit": unit,
    }
    update_mask = build_update_mask(fields)

    metric = admin_v1alpha.CustomMetric(
        name=custom_metric_rn(property_id, custom_metric_id),
        **{name: fields[name] for name in update_mask},
    )
    request = admin_v1alpha.UpdateCustomMetricRequest(
        custom_metric=metric, update_mask=to_field_mask(update_mask)
    )
    return await _run(lambda client: client.update_custom_metric(request=request))


async def archive_custom_metric(
    property_id: int | str, custom_metric_id: int | str
) -> Dict[str, str]:
    """Archives a custom metric. Destructive: requires GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE=1.

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
        custom_metric_id: The numeric custom metric ID.
    """
    ensure_destructive_allowed("archive_custom_metric")
    name = custom_metric_rn(property_id, custom_metric_id)
    request = admin_v1alpha.ArchiveCustomMetricRequest(name=name)

    def _sync_call():
        create_admin_alpha_client().archive_custom_metric(request=request)
        return {"archived": name}

    return await asyncio.to_thread(_sync_call)


# --- key events (conversions) -------------------------------------------------


async def create_key_event(
    property_id: int | str,
    event_name: str,
    counting_method: str = "ONCE_PER_EVENT",
) -> Dict[str, Any]:
    """Marks an event as a key event (conversion).

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
        event_name: The event to mark, e.g. "subscribe".
        counting_method: "ONCE_PER_EVENT" (default) counts every occurrence;
          "ONCE_PER_SESSION" counts at most one per session.
    """
    key_event = admin_v1alpha.KeyEvent(
        event_name=event_name,
        counting_method=admin_v1alpha.KeyEvent.CountingMethod[
            counting_method.strip().upper()
        ],
    )
    request = admin_v1alpha.CreateKeyEventRequest(
        parent=construct_property_rn(property_id), key_event=key_event
    )
    return await _run(lambda client: client.create_key_event(request=request))


async def update_key_event(
    property_id: int | str,
    key_event_id: int | str,
    counting_method: Optional[str] = None,
) -> Dict[str, Any]:
    """Updates a key event's counting method.

    event_name is immutable — mark a different event by creating a new key event.

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
        key_event_id: The numeric key event ID (from list_key_events).
        counting_method: "ONCE_PER_EVENT" or "ONCE_PER_SESSION".
    """
    method = (
        admin_v1alpha.KeyEvent.CountingMethod[counting_method.strip().upper()]
        if counting_method is not None
        else None
    )
    fields = {"counting_method": method}
    update_mask = build_update_mask(fields)

    key_event = admin_v1alpha.KeyEvent(
        name=key_event_rn(property_id, key_event_id),
        **{name: fields[name] for name in update_mask},
    )
    request = admin_v1alpha.UpdateKeyEventRequest(
        key_event=key_event, update_mask=to_field_mask(update_mask)
    )
    return await _run(lambda client: client.update_key_event(request=request))


async def delete_key_event(
    property_id: int | str, key_event_id: int | str
) -> Dict[str, str]:
    """Unmarks an event as a key event. Destructive: requires GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE=1.

    The event keeps being collected; it just stops counting as a conversion.

    Args:
        property_id: The Google Analytics property ID (number or 'properties/NUMBER').
        key_event_id: The numeric key event ID.
    """
    ensure_destructive_allowed("delete_key_event")
    name = key_event_rn(property_id, key_event_id)
    request = admin_v1alpha.DeleteKeyEventRequest(name=name)

    def _sync_call():
        create_admin_alpha_client().delete_key_event(request=request)
        return {"deleted": name}

    return await asyncio.to_thread(_sync_call)
