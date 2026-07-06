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

"""Client initialization for the Google Analytics Admin API (alpha)."""

import contextlib
import subprocess
import threading
from importlib import metadata
from unittest.mock import patch

import google.auth
from google.analytics import admin_v1alpha
from google.api_core.gapic_v1.client_info import ClientInfo

# Data stream reads work with analytics.readonly; change history requires the
# broader analytics.edit scope. The scope that actually applies comes from the
# ADC login — request both here so either tool works when the login includes them.
SCOPES = [
    "https://www.googleapis.com/auth/analytics.readonly",
    "https://www.googleapis.com/auth/analytics.edit",
]


def _version() -> str:
    try:
        return metadata.version("ga4-admin-mcp")
    except Exception:
        return "unknown"


_CLIENT_INFO = ClientInfo(user_agent=f"ga4-admin-mcp/{_version()}")
_lock = threading.Lock()
_CREDENTIALS = None


@contextlib.contextmanager
def _prevent_stdio_inheritance():
    """Stops child processes (e.g. gcloud) from inheriting stdio handles."""
    original_popen = subprocess.Popen

    def safe_popen(*args, **kwargs):
        if kwargs.get("stdin") is None:
            kwargs["stdin"] = subprocess.DEVNULL
        return original_popen(*args, **kwargs)

    with patch("subprocess.Popen", new=safe_popen):
        yield


def _get_credentials():
    global _CREDENTIALS
    if _CREDENTIALS is None:
        with _prevent_stdio_inheritance():
            _CREDENTIALS, _ = google.auth.default(scopes=SCOPES)
    return _CREDENTIALS


def create_admin_alpha_client() -> admin_v1alpha.AnalyticsAdminServiceClient:
    """Returns the Google Analytics Admin API (alpha) client."""
    with _lock:
        return admin_v1alpha.AnalyticsAdminServiceClient(
            client_info=_CLIENT_INFO, credentials=_get_credentials()
        )
