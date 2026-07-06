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
