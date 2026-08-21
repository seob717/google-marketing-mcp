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

"""The destructive write tools must refuse to run before touching the API."""

import pytest

from ga4_admin_mcp.tools import write

ENV_FLAG = "GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE"


@pytest.mark.parametrize(
    "call",
    [
        lambda: write.archive_custom_dimension(471889641, 12),
        lambda: write.archive_custom_metric(471889641, 34),
        lambda: write.delete_key_event(471889641, 56),
    ],
    ids=["archive_custom_dimension", "archive_custom_metric", "delete_key_event"],
)
async def test_destructive_tools_refuse_without_the_flag(monkeypatch, call):
    monkeypatch.delenv(ENV_FLAG, raising=False)
    with pytest.raises(PermissionError):
        await call()


async def test_update_without_any_field_is_rejected(monkeypatch):
    monkeypatch.delenv(ENV_FLAG, raising=False)
    with pytest.raises(ValueError):
        await write.update_custom_dimension(471889641, 12)
