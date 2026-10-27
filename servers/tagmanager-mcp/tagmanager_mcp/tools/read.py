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

"""Read-only tools for inspecting Google Tag Manager configuration.

All IDs are the numeric GTM IDs (not the public 'GTM-XXXX' code). Use
`list_accounts` → `list_containers` → `list_workspaces` to discover them.
"""

import asyncio
from typing import Any, Dict, List

from tagmanager_mcp.tools.client import tagmanager
from tagmanager_mcp.tools.utils import (
    account_path,
    container_path,
    entity_path,
    version_path,
    workspace_path,
)


async def _call(fn):
    return await asyncio.to_thread(lambda: fn().execute())


async def _list_all(fn, key):
    """Follows nextPageToken so large containers aren't silently truncated."""
    items, token = [], None
    while True:
        res = await _call(lambda: fn(token))
        items.extend(res.get(key, []))
        token = res.get("nextPageToken")
        if not token:
            return items


async def list_accounts() -> List[Dict[str, Any]]:
    """Lists the GTM accounts the authenticated user can access."""
    return await _list_all(
        lambda t: tagmanager().accounts().list(pageToken=t), "account"
    )


async def list_containers(account_id: int | str) -> List[Dict[str, Any]]:
    """Lists containers in an account.

    Args:
        account_id: The numeric GTM account ID.
    """
    parent = account_path(account_id)
    return await _list_all(
        lambda t: tagmanager().accounts().containers().list(parent=parent, pageToken=t), "container"
    )


async def get_container(
    account_id: int | str, container_id: int | str
) -> Dict[str, Any]:
    """Returns details for a single container.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
    """
    path = container_path(account_id, container_id)
    return await _call(lambda: tagmanager().accounts().containers().get(path=path))


async def list_workspaces(
    account_id: int | str, container_id: int | str
) -> List[Dict[str, Any]]:
    """Lists workspaces in a container.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
    """
    parent = container_path(account_id, container_id)
    return await _list_all(
        lambda t: tagmanager().accounts().containers().workspaces().list(parent=parent, pageToken=t), "workspace"
    )


async def get_workspace(
    account_id: int | str, container_id: int | str, workspace_id: int | str
) -> Dict[str, Any]:
    """Returns details for a single workspace.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
        workspace_id: The numeric GTM workspace ID.
    """
    path = workspace_path(account_id, container_id, workspace_id)
    return await _call(
        lambda: tagmanager().accounts().containers().workspaces().get(path=path)
    )


async def get_workspace_status(
    account_id: int | str, container_id: int | str, workspace_id: int | str
) -> Dict[str, Any]:
    """Returns a workspace's pending changes and merge conflicts.

    Check this before create_version: a workspace whose base version is behind
    the latest version can conflict with it and fail to version/publish.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
        workspace_id: The numeric GTM workspace ID.
    """
    path = workspace_path(account_id, container_id, workspace_id)
    return await _call(lambda: _workspaces(tagmanager()).getStatus(path=path))


async def quick_preview(
    account_id: int | str, container_id: int | str, workspace_id: int | str
) -> Dict[str, Any]:
    """Compiles the workspace without creating a version, to catch compiler
    errors before create_version. Changes nothing.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
        workspace_id: The numeric GTM workspace ID.
    """
    path = workspace_path(account_id, container_id, workspace_id)
    return await _call(lambda: _workspaces(tagmanager()).quick_preview(path=path))


def _workspaces(svc):
    return svc.accounts().containers().workspaces()


async def list_tags(
    account_id: int | str, container_id: int | str, workspace_id: int | str
) -> List[Dict[str, Any]]:
    """Lists tags in a workspace.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
        workspace_id: The numeric GTM workspace ID.
    """
    parent = workspace_path(account_id, container_id, workspace_id)
    return await _list_all(
        lambda t: _workspaces(tagmanager()).tags().list(parent=parent, pageToken=t), "tag"
    )


async def get_tag(
    account_id: int | str,
    container_id: int | str,
    workspace_id: int | str,
    tag_id: int | str,
) -> Dict[str, Any]:
    """Returns details for a single tag.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
        workspace_id: The numeric GTM workspace ID.
        tag_id: The numeric tag ID.
    """
    path = entity_path(account_id, container_id, workspace_id, "tags", tag_id)
    return await _call(lambda: _workspaces(tagmanager()).tags().get(path=path))


async def list_triggers(
    account_id: int | str, container_id: int | str, workspace_id: int | str
) -> List[Dict[str, Any]]:
    """Lists triggers in a workspace.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
        workspace_id: The numeric GTM workspace ID.
    """
    parent = workspace_path(account_id, container_id, workspace_id)
    return await _list_all(
        lambda t: _workspaces(tagmanager()).triggers().list(parent=parent, pageToken=t), "trigger"
    )


async def get_trigger(
    account_id: int | str,
    container_id: int | str,
    workspace_id: int | str,
    trigger_id: int | str,
) -> Dict[str, Any]:
    """Returns details for a single trigger.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
        workspace_id: The numeric GTM workspace ID.
        trigger_id: The numeric trigger ID.
    """
    path = entity_path(account_id, container_id, workspace_id, "triggers", trigger_id)
    return await _call(lambda: _workspaces(tagmanager()).triggers().get(path=path))


async def list_variables(
    account_id: int | str, container_id: int | str, workspace_id: int | str
) -> List[Dict[str, Any]]:
    """Lists user-defined variables in a workspace.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
        workspace_id: The numeric GTM workspace ID.
    """
    parent = workspace_path(account_id, container_id, workspace_id)
    return await _list_all(
        lambda t: _workspaces(tagmanager()).variables().list(parent=parent, pageToken=t), "variable"
    )


async def get_variable(
    account_id: int | str,
    container_id: int | str,
    workspace_id: int | str,
    variable_id: int | str,
) -> Dict[str, Any]:
    """Returns details for a single variable.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
        workspace_id: The numeric GTM workspace ID.
        variable_id: The numeric variable ID.
    """
    path = entity_path(account_id, container_id, workspace_id, "variables", variable_id)
    return await _call(lambda: _workspaces(tagmanager()).variables().get(path=path))


async def list_built_in_variables(
    account_id: int | str, container_id: int | str, workspace_id: int | str
) -> List[Dict[str, Any]]:
    """Lists the enabled built-in variables in a workspace.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
        workspace_id: The numeric GTM workspace ID.
    """
    parent = workspace_path(account_id, container_id, workspace_id)
    return await _list_all(
        lambda t: _workspaces(tagmanager()).built_in_variables().list(parent=parent, pageToken=t), "builtInVariable"
    )


async def list_versions(
    account_id: int | str, container_id: int | str
) -> List[Dict[str, Any]]:
    """Lists container version headers (id, name, and metadata) for a container.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
    """
    parent = container_path(account_id, container_id)
    return await _list_all(
        lambda t: tagmanager().accounts().containers().version_headers().list(parent=parent, pageToken=t), "containerVersionHeader"
    )


async def get_version(
    account_id: int | str, container_id: int | str, version_id: int | str
) -> Dict[str, Any]:
    """Returns a full container version, including all tags/triggers/variables.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
        version_id: The numeric container version ID.
    """
    path = version_path(account_id, container_id, version_id)
    return await _call(lambda: tagmanager().accounts().containers().versions().get(path=path))


async def get_live_version(
    account_id: int | str, container_id: int | str
) -> Dict[str, Any]:
    """Returns the currently published (live) container version.

    Args:
        account_id: The numeric GTM account ID.
        container_id: The numeric GTM container ID.
    """
    parent = container_path(account_id, container_id)
    return await _call(
        lambda: tagmanager().accounts().containers().versions().live(parent=parent)
    )


# Fields that differ between containers/versions even when the config matches.
_VOLATILE = {
    "accountId", "containerId", "containerVersionId", "workspaceId", "path",
    "fingerprint", "tagManagerUrl", "tagId", "triggerId", "variableId",
    "parentFolderId",
}
_TRIGGER_REFS = ("firingTriggerId", "blockingTriggerId")


def _normalize(entity: Dict[str, Any], trigger_names: Dict[str, str]) -> Dict[str, Any]:
    out = {k: v for k, v in entity.items() if k not in _VOLATILE}
    # Trigger IDs are per-container; compare by trigger name instead.
    for ref in _TRIGGER_REFS:
        if ref in out:
            out[ref] = sorted(trigger_names.get(i, i) for i in out[ref])
    if "parameter" in out:
        out["parameter"] = sorted(out["parameter"], key=lambda p: p.get("key", ""))
    return out


def diff_versions(a: Dict[str, Any], b: Dict[str, Any]) -> Dict[str, Any]:
    """Diffs two container versions by entity name."""
    result: Dict[str, Any] = {}
    names = [
        {t["triggerId"]: t["name"] for t in v.get("trigger", [])} for v in (a, b)
    ]
    for kind in ("tag", "trigger", "variable"):
        ea, eb = (
            {e["name"]: _normalize(e, n) for e in v.get(kind, [])}
            for v, n in zip((a, b), names)
        )
        changed = {}
        for name in ea.keys() & eb.keys():
            fields = {
                f: {"a": ea[name].get(f), "b": eb[name].get(f)}
                for f in ea[name].keys() | eb[name].keys()
                if ea[name].get(f) != eb[name].get(f)
            }
            if fields:
                changed[name] = fields
        result[kind] = {
            "only_in_a": sorted(ea.keys() - eb.keys()),
            "only_in_b": sorted(eb.keys() - ea.keys()),
            "changed": changed,
        }
    bia, bib = ({x["type"] for x in v.get("builtInVariable", [])} for v in (a, b))
    result["builtInVariable"] = {
        "only_in_a": sorted(bia - bib),
        "only_in_b": sorted(bib - bia),
    }
    return result


async def compare_live_versions(
    account_id_a: int | str,
    container_id_a: int | str,
    account_id_b: int | str,
    container_id_b: int | str,
) -> Dict[str, Any]:
    """Compares the live versions of two containers (e.g. dev vs prod) and
    returns only the differences: tags/triggers/variables present on one side
    only, and per-field changes for same-named ones. Trigger references are
    compared by trigger name, since IDs differ between containers.

    Args:
        account_id_a: The numeric GTM account ID of container A.
        container_id_a: The numeric GTM container ID of container A.
        account_id_b: The numeric GTM account ID of container B.
        container_id_b: The numeric GTM container ID of container B.
    """
    a, b = await asyncio.gather(
        get_live_version(account_id_a, container_id_a),
        get_live_version(account_id_b, container_id_b),
    )
    return {
        "a": {"container": a.get("container", {}).get("name"), "version": a.get("containerVersionId")},
        "b": {"container": b.get("container", {}).get("name"), "version": b.get("containerVersionId")},
        "diff": diff_versions(a, b),
    }
