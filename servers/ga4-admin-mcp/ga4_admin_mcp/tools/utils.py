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

"""Resource-name and conversion helpers for the GA4 Admin tools."""

import os
from datetime import datetime, timezone
from typing import Any, Dict

import proto


def construct_property_rn(property_value: int | str) -> str:
    """Returns a property resource name ('properties/NUMBER')."""
    property_num = None
    if isinstance(property_value, int):
        property_num = property_value
    elif isinstance(property_value, str):
        property_value = property_value.strip()
        if property_value.isdigit():
            property_num = int(property_value)
        elif property_value.startswith("properties/"):
            tail = property_value.split("/")[-1]
            if tail.isdigit():
                property_num = int(tail)
    if property_num is None:
        raise ValueError(
            f"Invalid property ID: {property_value!r}. Expected a number or "
            "'properties/NUMBER'."
        )
    return f"properties/{property_num}"


def account_rn(account_id: int | str) -> str:
    """Returns 'accounts/NUMBER'."""
    return f"accounts/{str(account_id).strip().split('/')[-1]}"


def data_stream_rn(property_id: int | str, data_stream_id: int | str) -> str:
    """Returns the data stream resource name."""
    ds = str(data_stream_id).strip().split("/")[-1]
    return f"{construct_property_rn(property_id)}/dataStreams/{ds}"


def _child_rn(property_id: int | str, collection: str, child_id: int | str) -> str:
    """Returns a property-scoped child resource name."""
    child = str(child_id).strip().split("/")[-1]
    return f"{construct_property_rn(property_id)}/{collection}/{child}"


def custom_dimension_rn(property_id: int | str, custom_dimension_id: int | str) -> str:
    """Returns the custom dimension resource name."""
    return _child_rn(property_id, "customDimensions", custom_dimension_id)


def custom_metric_rn(property_id: int | str, custom_metric_id: int | str) -> str:
    """Returns the custom metric resource name."""
    return _child_rn(property_id, "customMetrics", custom_metric_id)


def key_event_rn(property_id: int | str, key_event_id: int | str) -> str:
    """Returns the key event (conversion) resource name."""
    return _child_rn(property_id, "keyEvents", key_event_id)


def build_update_mask(fields: Dict[str, Any]) -> list[str]:
    """Returns the names of the fields that were actually supplied.

    GA4 update calls replace only the paths named in the update mask, so a
    caller that supplies nothing would silently issue a no-op write.
    """
    mask = [name for name, value in fields.items() if value is not None]
    if not mask:
        raise ValueError("No fields to update. Supply at least one field to change.")
    return mask


def to_field_mask(paths: list[str]) -> str:
    """Renders field names as a protobuf FieldMask string.

    FieldMask parses its JSON form, which requires camelCase — passing the
    snake_case proto field names raises "must not contain _s".
    """
    camel = []
    for path in paths:
        head, *rest = path.split("_")
        camel.append(head + "".join(part.title() for part in rest))
    return ",".join(camel)


def parse_time(value: str) -> datetime:
    """Parses an ISO 8601 string to a timezone-aware datetime (assumes UTC)."""
    dt = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def proto_to_dict(obj: proto.Message) -> Dict[str, Any]:
    """Converts a proto-plus message to a dictionary."""
    return type(obj).to_dict(
        obj, use_integers_for_enums=False, preserving_proto_field_name=True
    )


def destructive_allowed() -> bool:
    """Whether destructive operations (archive/delete) are enabled."""
    return os.environ.get("GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE") == "1"


def ensure_destructive_allowed(action: str) -> None:
    """Raises PermissionError unless destructive operations are enabled.

    Guards archive/delete so they can't run unless the operator opts in with
    GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE=1.
    """
    if not destructive_allowed():
        raise PermissionError(
            f"'{action}' is a destructive operation and is disabled. "
            "Set GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE=1 in the server environment "
            "to enable it."
        )
