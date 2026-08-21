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

import pytest

from ga4_admin_mcp.tools import utils

ENV_FLAG = "GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE"


def test_destructive_gate_disabled_by_default(monkeypatch):
    monkeypatch.delenv(ENV_FLAG, raising=False)
    assert utils.destructive_allowed() is False


def test_destructive_gate_enabled_by_env(monkeypatch):
    monkeypatch.setenv(ENV_FLAG, "1")
    assert utils.destructive_allowed() is True


def test_destructive_gate_ignores_other_truthy_values(monkeypatch):
    monkeypatch.setenv(ENV_FLAG, "true")
    assert utils.destructive_allowed() is False


def test_ensure_destructive_allowed_raises_when_disabled(monkeypatch):
    monkeypatch.delenv(ENV_FLAG, raising=False)
    with pytest.raises(PermissionError) as excinfo:
        utils.ensure_destructive_allowed("archive_custom_dimension")
    message = str(excinfo.value)
    assert "archive_custom_dimension" in message
    assert ENV_FLAG in message


def test_ensure_destructive_allowed_passes_when_enabled(monkeypatch):
    monkeypatch.setenv(ENV_FLAG, "1")
    utils.ensure_destructive_allowed("archive_custom_dimension")


def test_resource_name_builders_accept_ints_and_strings():
    assert (
        utils.custom_dimension_rn(471889641, 12)
        == "properties/471889641/customDimensions/12"
    )
    assert (
        utils.custom_metric_rn("properties/471889641", "34")
        == "properties/471889641/customMetrics/34"
    )
    assert utils.key_event_rn(471889641, 56) == "properties/471889641/keyEvents/56"


def test_resource_name_builders_accept_full_paths():
    assert (
        utils.custom_dimension_rn(471889641, "properties/471889641/customDimensions/12")
        == "properties/471889641/customDimensions/12"
    )


def test_resource_name_builders_reject_invalid_property():
    with pytest.raises(ValueError):
        utils.key_event_rn("not-a-number", 56)


def test_build_update_mask_lists_only_provided_fields():
    mask = utils.build_update_mask(
        {"display_name": "Plan", "description": None, "scope": "EVENT"}
    )
    assert mask == ["display_name", "scope"]


def test_build_update_mask_rejects_empty_update():
    with pytest.raises(ValueError):
        utils.build_update_mask({"display_name": None})


def test_field_mask_uses_camel_case_paths():
    """protobuf FieldMask rejects snake_case paths, so the mask must be camelCase."""
    assert utils.to_field_mask(["display_name", "description"]) == (
        "displayName,description"
    )
    assert utils.to_field_mask(["disallow_ads_personalization"]) == (
        "disallowAdsPersonalization"
    )
