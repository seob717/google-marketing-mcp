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

"""Singleton MCP server that registers the GA4 Admin tools."""

import json
import sys

from mcp import types as mcp_types
from mcp.server.lowlevel import Server

from google.adk.tools.function_tool import FunctionTool
from google.adk.tools.mcp_tool.conversion_utils import adk_to_mcp_tool_type

from ga4_admin_mcp.tools import admin

_FUNCTIONS = [
    admin.list_data_streams,
    admin.get_data_stream,
    admin.get_global_site_tag,
    admin.search_change_history_events,
]

tools = [FunctionTool(fn) for fn in _FUNCTIONS]
tool_map = {t.name: t for t in tools}

app = Server(name="Google Analytics Admin MCP Server")


def _sanitize_additional_properties(node) -> None:
    """Forces additionalProperties to a boolean, which some MCP clients require."""
    if not isinstance(node, dict):
        return
    if "additionalProperties" in node and not isinstance(
        node["additionalProperties"], bool
    ):
        node["additionalProperties"] = True
    for child in node.values():
        if isinstance(child, dict):
            _sanitize_additional_properties(child)
        elif isinstance(child, list):
            for element in child:
                _sanitize_additional_properties(element)


mcp_tools = [adk_to_mcp_tool_type(tool) for tool in tools]

for tool in mcp_tools:
    if tool.inputSchema == {}:
        tool.inputSchema = {"type": "object", "properties": {}}
    for prop in tool.inputSchema.get("properties", {}).values():
        if "anyOf" in prop and prop.get("type") == "null":
            del prop["type"]
    _sanitize_additional_properties(tool.inputSchema)


@app.list_tools()
async def list_tools() -> list[mcp_types.Tool]:
    return mcp_tools


@app.call_tool()
async def call_mcp_tool(name: str, arguments: dict) -> list[mcp_types.Content]:
    if name not in tool_map:
        error = {"error": f"Tool '{name}' not implemented by this server."}
        return [mcp_types.TextContent(type="text", text=json.dumps(error))]

    try:
        response = await tool_map[name].run_async(args=arguments, tool_context=None)
        return [
            mcp_types.TextContent(
                type="text", text=json.dumps(response, indent=2, default=str)
            )
        ]
    except Exception as e:
        print(f"MCP Server: error executing '{name}': {e}", file=sys.stderr)
        error = {"error": f"Failed to execute tool '{name}': {str(e)}"}
        return [mcp_types.TextContent(type="text", text=json.dumps(error))]
