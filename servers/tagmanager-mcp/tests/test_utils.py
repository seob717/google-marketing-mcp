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

from tagmanager_mcp.tools import utils


def test_path_builders_accept_ints_and_strings():
    assert utils.account_path(6) == "accounts/6"
    assert utils.container_path(6, 42) == "accounts/6/containers/42"
    assert (
        utils.workspace_path("6", "42", "3")
        == "accounts/6/containers/42/workspaces/3"
    )
    assert (
        utils.version_path(6, 42, 9)
        == "accounts/6/containers/42/versions/9"
    )
    assert (
        utils.entity_path(6, 42, 3, "tags", 11)
        == "accounts/6/containers/42/workspaces/3/tags/11"
    )


def test_norm_extracts_trailing_id_from_full_path():
    assert utils.container_path(6, "accounts/6/containers/42") == (
        "accounts/6/containers/42"
    )


def test_norm_rejects_non_numeric():
    with pytest.raises(ValueError):
        utils.account_path("not-a-number")


def test_destructive_gate_disabled_by_default(monkeypatch):
    monkeypatch.delenv("GTM_MCP_ALLOW_DESTRUCTIVE", raising=False)
    assert utils.destructive_allowed() is False
    with pytest.raises(PermissionError):
        utils.ensure_destructive_allowed("delete_tag")


def test_destructive_gate_enabled_by_env(monkeypatch):
    monkeypatch.setenv("GTM_MCP_ALLOW_DESTRUCTIVE", "1")
    assert utils.destructive_allowed() is True
    # Should not raise.
    utils.ensure_destructive_allowed("publish_version")


def test_delete_workspace_is_gated(monkeypatch):
    import asyncio

    from tagmanager_mcp.tools import write

    monkeypatch.delenv("GTM_MCP_ALLOW_DESTRUCTIVE", raising=False)
    with pytest.raises(PermissionError):
        asyncio.run(write.delete_workspace(6, 42, 3))


def test_resolve_conflict_is_gated(monkeypatch):
    import asyncio

    from tagmanager_mcp.tools import write

    monkeypatch.delenv("GTM_MCP_ALLOW_DESTRUCTIVE", raising=False)
    with pytest.raises(PermissionError):
        asyncio.run(write.resolve_conflict(6, 42, 3, {"variable": {}}))
    with pytest.raises(PermissionError):
        asyncio.run(write.revert_change(6, 42, 3, "variables", 7))
    with pytest.raises(PermissionError):
        asyncio.run(write.disable_built_in_variables(6, 42, 3, ["pageUrl"]))


def test_revert_change_rejects_unknown_entity_type(monkeypatch):
    import asyncio

    from tagmanager_mcp.tools import write

    monkeypatch.setenv("GTM_MCP_ALLOW_DESTRUCTIVE", "1")
    with pytest.raises(ValueError):
        asyncio.run(write.revert_change(6, 42, 3, "folders", 7))


def test_merge_entity_keeps_untouched_parameters():
    from tagmanager_mcp.tools.write import merge_entity

    current = {
        "name": "GA4 credit_topup",
        "fingerprint": "1",
        "parameter": [
            {"key": "eventName", "type": "template", "value": "credit_topup"},
            {"key": "measurementId", "type": "template", "value": "G-X"},
        ],
    }
    patch = {"parameter": [{"key": "eventName", "type": "template", "value": "x"}]}
    merged = merge_entity(current, patch)
    assert merged["name"] == "GA4 credit_topup"
    assert {p["key"]: p["value"] for p in merged["parameter"]} == {
        "eventName": "x",
        "measurementId": "G-X",
    }


def test_diff_versions_matches_by_name_and_trigger_name():
    from tagmanager_mcp.tools.read import diff_versions

    def version(trigger_id, extra_var):
        return {
            "trigger": [{"triggerId": trigger_id, "name": "purchase", "type": "customEvent"}],
            "tag": [{"tagId": trigger_id, "name": "GA4 credit_topup", "firingTriggerId": [trigger_id]}],
            "variable": [{"variableId": "1", "name": "method", "type": "v"}] + extra_var,
            "builtInVariable": [{"type": "pageUrl"}],
        }

    dev = version("10", [{"variableId": "2", "name": "credit_type", "type": "v"}])
    prod = version("99", [])
    d = diff_versions(dev, prod)
    # Different trigger IDs, same trigger name: not a change.
    assert d["tag"] == {"only_in_a": [], "only_in_b": [], "changed": {}}
    assert d["trigger"]["changed"] == {}
    assert d["variable"]["only_in_a"] == ["credit_type"]
    assert d["builtInVariable"] == {"only_in_a": [], "only_in_b": []}


def test_list_all_follows_next_page_token():
    import asyncio

    from tagmanager_mcp.tools.read import _list_all

    pages = {None: {"tag": [1, 2], "nextPageToken": "p2"}, "p2": {"tag": [3]}}

    class Req:
        def __init__(self, token):
            self.token = token

        def execute(self):
            return pages[self.token]

    assert asyncio.run(_list_all(lambda t: Req(t), "tag")) == [1, 2, 3]
