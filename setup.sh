#!/usr/bin/env bash
#
# Copyright 2025 Google LLC All Rights Reserved.
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
#
# One-step setup for the Google Marketing MCP servers on macOS — Google
# Analytics (with admin tools), plus optional Google Ads and Google Tag Manager
# — targeting Claude Desktop and/or the Claude Code CLI.
#
# No Homebrew required. Uses `uv` (which also manages Python) to install and run
# the servers, installs the Google Cloud SDK if missing, signs you in to Google,
# enables the required APIs, and wires the servers into your chosen clients.
#
# Usage:
#   bash setup.sh
#   GA_MCP_PROJECT=my-gcp-project bash setup.sh   # skip the project prompt
#   GA_MCP_SERVERS=ga,ga-admin,ads,gtm bash setup.sh
#     # skip the server picker (values: ga, ga-admin, ads, gtm — any subset)
#   GA_MCP_TARGETS=desktop,cli bash setup.sh
#     # skip the target picker (values: desktop, cli — comma-separated)
#   GA_MCP_WITH_ADS=1 GA_MCP_ADS_DEV_TOKEN=xxx bash setup.sh
#     # also set up Google Ads MCP without prompts
#     # (optional: GA_MCP_ADS_LOGIN_CUSTOMER_ID for access via a manager/MCC account)
#   GA_MCP_WITH_GTM=1 bash setup.sh
#     # also set up the Google Tag Manager MCP server (read + write)
#     # (optional: GTM_MCP_ALLOW_DESTRUCTIVE=1 to allow delete/publish)

set -euo pipefail

# --- pretty logging -----------------------------------------------------------
if [ -t 1 ]; then
  C_BLUE=$'\033[0;34m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[0;33m'
  C_RED=$'\033[0;31m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'; C_DIM=$'\033[2m'
else
  C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BOLD=''; C_OFF=''; C_DIM=''
fi
info() { printf '%s▶%s %s\n' "$C_BLUE" "$C_OFF" "$1"; }
ok()   { printf '%s✓%s %s\n' "$C_GREEN" "$C_OFF" "$1"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_OFF" "$1"; }
err()  { printf '%s✗%s %s\n' "$C_RED" "$C_OFF" "$1" >&2; }
step() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_OFF"; }

# Read user input from the terminal even when the script is piped in.
ask() {
  local __var="$1" __prompt="$2" __reply
  if [ -r /dev/tty ]; then
    read -r -p "$__prompt" __reply </dev/tty
  else
    read -r -p "$__prompt" __reply
  fi
  printf -v "$__var" '%s' "$__reply"
}

# Yes/No prompt → sets VAR to 1/0. Usage: ask_yn VAR "질문?" <y|n default>.
# Plain line read (no TUI), so it works in any terminal / bash 3.2.
ask_yn() {
  local __var="$1" __prompt="$2" __def="${3:-y}" __reply __hint
  if [ "$__def" = "y" ]; then __hint="[Y/n]"; else __hint="[y/N]"; fi
  if [ -r /dev/tty ]; then
    read -r -p "$(printf '%s %s%s%s ' "$__prompt" "$C_DIM" "$__hint" "$C_OFF")" __reply </dev/tty || __reply=''
  else
    __reply=''
  fi
  __reply="${__reply:-$__def}"
  case "$__reply" in
    [yY]*) printf -v "$__var" '%s' 1 ;;
    *)     printf -v "$__var" '%s' 0 ;;
  esac
}

# Checkbox picker (↑↓ / space / Enter), drawn by Python curses so it uses this
# terminal's own terminfo instead of hand-written ANSI — the earlier bash TUI
# broke wherever cursor-up was ignored. Returns 1 when curses can't drive the
# terminal so every caller keeps its plain y/N path.
PICKER_PY="$(mktemp -t gmm-picker)"
trap 'rm -f "$PICKER_PY" "${SERVERS_JSON:-}"' EXIT
cat > "$PICKER_PY" <<'PY'
"""Checkbox picker for setup.sh. Exits 2 when curses can't drive this terminal
(caller falls back to y/N prompts) and 130 when the user cancels."""

import curses
import sys
import unicodedata


def _w(text):
    """Display width, counting East Asian wide characters as two columns."""
    return sum(2 if unicodedata.east_asian_width(c) in "WFA" else 1 for c in text)


def _clip(text, width):
    out, used = "", 0
    for c in text:
        cw = 2 if unicodedata.east_asian_width(c) in "WFA" else 1
        if used + cw > width:
            break
        out += c
        used += cw
    return out


def _pad(text, width):
    return text + " " * max(0, width - _w(text))


def _draw(scr, title, items, state, idx):
    scr.erase()
    height, width = scr.getmaxyx()
    avail = max(1, width - 1)
    label_w = max(_w(i["label"]) for i in items)

    scr.addstr(0, 0, _clip(title, avail), curses.A_BOLD)
    scr.addstr(1, 0, _clip("  ↑↓ 이동 · space 선택 · a 전체 · Enter 확정 · q 취소", avail))

    for n, item in enumerate(items):
        row = 3 + n
        if row >= height:
            break
        mark = "[x]" if state[n] else "[ ]"
        pointer = ">" if n == idx else " "
        line = "%s %s  %s   %s" % (pointer, mark, _pad(item["label"], label_w), item["desc"])
        scr.addstr(row, 0, _clip(line, avail), curses.A_BOLD if n == idx else curses.A_NORMAL)

    row = 4 + len(items)
    if row < height:
        chosen = sum(state)
        note = "  %d개 선택됨" % chosen if chosen else "  하나도 선택하지 않았습니다 — 최소 1개가 필요합니다"
        scr.addstr(row, 0, _clip(note, avail))
    scr.refresh()


def _run(scr, title, items, state):
    curses.curs_set(0)
    scr.keypad(True)
    height, width = scr.getmaxyx()
    if height < len(items) + 6 or width < 40:
        raise RuntimeError("terminal too small for the picker")
    idx = 0
    while True:
        _draw(scr, title, items, state, idx)
        key = scr.getch()
        if key == -1:
            # stdin closed underneath us; bail instead of spinning forever.
            sys.exit(130)
        if key in (curses.KEY_UP, ord("k")):
            idx = (idx - 1) % len(items)
        elif key in (curses.KEY_DOWN, ord("j")):
            idx = (idx + 1) % len(items)
        elif key == ord(" "):
            state[idx] = not state[idx]
        elif key == ord("a"):
            fill = not all(state)
            state[:] = [fill] * len(items)
        elif ord("1") <= key <= ord("9") and key - ord("1") < len(items):
            idx = key - ord("1")
            state[idx] = not state[idx]
        elif key in (curses.KEY_ENTER, 10, 13):
            if any(state):
                return state
        elif key in (ord("q"), 27):
            sys.exit(130)


def main(argv):
    out_path, title, specs = argv[1], argv[2], argv[3:]
    items, state = [], []
    for spec in specs:
        key, label, desc, default = spec.split("\t")
        items.append({"key": key, "label": label, "desc": desc})
        state.append(default == "1")
    if not items:
        return 2
    # curses needs a real terminal on both ends; setup.sh redirects them to /dev/tty.
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        return 2
    try:
        curses.wrapper(_run, title, items, state)
    except SystemExit:
        raise
    except Exception:
        # Unknown TERM, no terminfo entry, window too small — let bash fall back.
        return 2
    with open(out_path, "w") as f:
        f.write(",".join(i["key"] for i, on in zip(items, state) if on))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

# Usage: pick_multi VAR "제목" "key:label:desc:1" ...  → VAR="key1,key2"
pick_multi() {
  local __var="$1" __title="$2" __out __spec __key __rest __label __desc __def __rc=0
  local __args=()
  shift 2
  [ -r /dev/tty ] || return 1
  [ -n "${UV:-}" ] && [ -x "$UV" ] || return 1
  for __spec in "$@"; do
    __key="${__spec%%:*}"; __rest="${__spec#*:}"
    __label="${__rest%%:*}"; __rest="${__rest#*:}"
    __desc="${__rest%%:*}"; __def="${__rest##*:}"
    __args+=("$(printf '%s\t%s\t%s\t%s' "$__key" "$__label" "$__desc" "$__def")")
  done
  __out="$(mktemp -t gmm-pick)"
  "$UV" run --no-project python "$PICKER_PY" "$__out" "$__title" "${__args[@]}" \
    </dev/tty >/dev/tty 2>/dev/null || __rc=$?
  if [ "$__rc" -eq 130 ]; then
    rm -f "$__out"
    err "설치를 취소했습니다."
    exit 130
  fi
  if [ "$__rc" -ne 0 ]; then
    rm -f "$__out"
    return 1
  fi
  printf -v "$__var" '%s' "$(cat "$__out")"
  rm -f "$__out"
  return 0
}

ANALYTICS_READONLY_SCOPE="https://www.googleapis.com/auth/analytics.readonly"
ANALYTICS_EDIT_SCOPE="https://www.googleapis.com/auth/analytics.edit"
ADWORDS_SCOPE="https://www.googleapis.com/auth/adwords"
GTM_SCOPES="https://www.googleapis.com/auth/tagmanager.readonly,https://www.googleapis.com/auth/tagmanager.edit.containers,https://www.googleapis.com/auth/tagmanager.edit.containerversions,https://www.googleapis.com/auth/tagmanager.publish"

# --- install sources ----------------------------------------------------------
# Official servers come from PyPI (they track their own upstream); our own
# servers come from this repo. Each is overridable by env.
#   - GA reporting: official PyPI `analytics-mcp`.
#   - GA admin:     this repo (ga4-admin-mcp under servers/ga4-admin-mcp).
#   - Ads:          official PyPI `google-ads-mcp`.
#   - GTM:          this repo (tagmanager-mcp under servers/tagmanager-mcp).
GA_PACKAGE="${GA_PACKAGE:-analytics-mcp}"
GA_ADMIN_INSTALL_SOURCE="${GA_ADMIN_INSTALL_SOURCE:-git+https://github.com/seob717/google-marketing-mcp.git@main#subdirectory=servers/ga4-admin-mcp}"
ADS_PACKAGE="${ADS_PACKAGE:-google-ads-mcp}"
GTM_INSTALL_SOURCE="${GTM_INSTALL_SOURCE:-git+https://github.com/seob717/google-marketing-mcp.git@main#subdirectory=servers/tagmanager-mcp}"
CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
ADC_PATH="$HOME/.config/gcloud/application_default_credentials.json"

printf '%s%s%s\n' "$C_BOLD" "Google Marketing MCP · 설치 (GA · GA Admin · Ads · GTM)" "$C_OFF"
echo "필요한 도구 설치 → Google 로그인 → Claude Desktop/CLI 연결까지 자동으로 진행합니다."
echo "(Homebrew 없이 동작합니다)"

# --- 0. platform check --------------------------------------------------------
if [ "$(uname)" != "Darwin" ]; then
  err "이 스크립트는 macOS 전용입니다. (현재: $(uname))"
  exit 1
fi

# --- 1. uv (also provides Python) --------------------------------------------
step "1/6 · 실행 도구 준비 (uv)"
if ! command -v uv >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/uv" ]; then
  info "uv 설치 중... (관리자 암호 불필요)"
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || true
fi
UV="$(command -v uv 2>/dev/null || true)"
[ -n "$UV" ] || UV="$HOME/.local/bin/uv"
if [ ! -x "$UV" ]; then
  err "uv 설치에 실패했습니다. 인터넷 연결을 확인하고 다시 실행하세요."
  exit 1
fi
ok "uv 준비 완료 ($UV)"

# --- target selection ---------------------------------------------------------
# Where to install the MCP server(s): Claude Desktop, the Claude Code CLI, or both.
# Asked one line at a time (y/N); GA_MCP_TARGETS pins it non-interactively.
TARGET_DESKTOP=0
TARGET_CLI=0
CLAUDE_BIN="$(command -v claude || true)"
if [ -n "${GA_MCP_TARGETS:-}" ]; then
  case ",$GA_MCP_TARGETS," in *,desktop,*) TARGET_DESKTOP=1 ;; esac
  case ",$GA_MCP_TARGETS," in *,cli,*) TARGET_CLI=1 ;; esac
elif [ -r /dev/tty ]; then
  TARGET_SPECS=("desktop:Claude Desktop:데스크톱 앱:1")
  if [ -n "$CLAUDE_BIN" ]; then
    TARGET_SPECS+=("cli:Claude Code CLI:터미널의 claude 명령:1")
  else
    warn "'claude' CLI가 없어 Claude Code CLI는 건너뜁니다 (https://claude.ai/download)."
  fi
  if pick_multi PICKED_TARGETS "설치할 대상" "${TARGET_SPECS[@]}"; then
    case ",$PICKED_TARGETS," in *,desktop,*) TARGET_DESKTOP=1 ;; esac
    case ",$PICKED_TARGETS," in *,cli,*) TARGET_CLI=1 ;; esac
  else
    step "설치할 대상"
    ask_yn TARGET_DESKTOP "Claude Desktop에 설치할까요?" y
    if [ -n "$CLAUDE_BIN" ]; then
      ask_yn TARGET_CLI "Claude Code CLI에 설치할까요?" y
    fi
  fi
else
  TARGET_DESKTOP=1
fi

# Claude Code CLI needs the `claude` binary. Skip that target if it's missing.
if [ "$TARGET_CLI" = "1" ] && [ -z "$CLAUDE_BIN" ]; then
  warn "'claude' CLI를 찾을 수 없어 Claude Code CLI 설정을 건너뜁니다."
  warn "설치: https://claude.ai/download  또는  npm i -g @anthropic-ai/claude-code"
  TARGET_CLI=0
fi
if [ "$TARGET_DESKTOP" = "0" ] && [ "$TARGET_CLI" = "0" ]; then
  err "설정할 대상이 없습니다."
  exit 1
fi

# --- server selection ---------------------------------------------------------
# Which MCP servers to install. GA (reporting) and GA Admin (data streams /
# change history) are separate: admin needs the broader analytics.edit scope.
WITH_GA=0
WITH_GA_ADMIN=0
WITH_ADS=0
WITH_GTM=0
if [ -n "${GA_MCP_SERVERS:-}" ]; then
  case ",$GA_MCP_SERVERS," in *,ga,*) WITH_GA=1 ;; esac
  case ",$GA_MCP_SERVERS," in *,ga-admin,*) WITH_GA_ADMIN=1 ;; esac
  case ",$GA_MCP_SERVERS," in *,ads,*) WITH_ADS=1 ;; esac
  case ",$GA_MCP_SERVERS," in *,gtm,*) WITH_GTM=1 ;; esac
elif [ -r /dev/tty ]; then
  # Checkbox picker, everything on by default; falls back to one y/N line each
  # when curses is unavailable. Ads asks for a developer token below and skips
  # itself if none is given.
  if pick_multi PICKED_SERVERS "설치할 MCP 서버" \
    "ga:Google Analytics:리포팅·실시간 리포트:1" \
    "ga-admin:Google Analytics Admin:데이터 스트림·변경기록:1" \
    "ads:Google Ads:광고 리포팅 (개발자 토큰 필요):1" \
    "gtm:Google Tag Manager:태그·트리거·버전 게시:1"; then
    case ",$PICKED_SERVERS," in *,ga,*) WITH_GA=1 ;; esac
    case ",$PICKED_SERVERS," in *,ga-admin,*) WITH_GA_ADMIN=1 ;; esac
    case ",$PICKED_SERVERS," in *,ads,*) WITH_ADS=1 ;; esac
    case ",$PICKED_SERVERS," in *,gtm,*) WITH_GTM=1 ;; esac
  else
    step "설치할 MCP 서버 (필요 없는 건 n)"
    ask_yn WITH_GA       "Google Analytics (리포팅)?" y
    ask_yn WITH_GA_ADMIN "Google Analytics Admin (데이터 스트림·변경기록)?" y
    ask_yn WITH_ADS      "Google Ads (개발자 토큰 필요)?" y
    ask_yn WITH_GTM      "Google Tag Manager?" y
  fi
else
  # Non-interactive without GA_MCP_SERVERS: GA on, others by their env flag.
  WITH_GA=1
  [ "${GA_MCP_WITH_ADS:-}" = "1" ] && WITH_ADS=1
  [ "${GA_MCP_WITH_GTM:-}" = "1" ] && WITH_GTM=1
fi
if [ "$WITH_GA" = "0" ] && [ "$WITH_GA_ADMIN" = "0" ] && [ "$WITH_ADS" = "0" ] && [ "$WITH_GTM" = "0" ]; then
  err "설치할 서버가 선택되지 않았습니다."
  exit 1
fi

# --- Google Ads: developer token ----------------------------------------------
# The official google-ads-mcp server is read-only, but needs a developer token
# that can only be issued manually in the Google Ads API Center — so we ask.
ADS_DEV_TOKEN="${GA_MCP_ADS_DEV_TOKEN:-}"
ADS_LOGIN_CUSTOMER_ID="${GA_MCP_ADS_LOGIN_CUSTOMER_ID:-}"
if [ "$WITH_ADS" = "1" ] && [ -z "$ADS_DEV_TOKEN" ]; then
  echo ""
  info "Google Ads developer token이 필요합니다."
  echo "  발급 위치: Google Ads 관리자 계정(MCC) → API 센터"
  echo "  https://ads.google.com/aw/apicenter"
  echo "  (Explorer access 수준이면 대부분 즉시 자동 승인됩니다)"
  ask ADS_DEV_TOKEN "developer token을 붙여넣으세요 (건너뛰려면 Enter): "
  if [ -z "$ADS_DEV_TOKEN" ]; then
    warn "developer token이 없어 Google Ads 설정을 건너뜁니다. 발급 후 스크립트를 다시 실행하세요."
    WITH_ADS=0
  fi
fi
if [ "$WITH_ADS" = "1" ] && [ -z "$ADS_LOGIN_CUSTOMER_ID" ]; then
  ask ADS_LOGIN_CUSTOMER_ID "MCC(관리자 계정)를 통해 접근한다면 관리자 고객 ID를 입력하세요 (직접 접근이면 Enter): "
fi
ADS_LOGIN_CUSTOMER_ID="${ADS_LOGIN_CUSTOMER_ID//-/}"

# --- Google Tag Manager: destructive gate -------------------------------------
# GTM supports read + write. Delete/publish stay disabled unless opted in.
GTM_ALLOW_DESTRUCTIVE="${GTM_MCP_ALLOW_DESTRUCTIVE:-}"
if [ "$WITH_GTM" = "1" ] && [ -z "$GTM_ALLOW_DESTRUCTIVE" ]; then
  ask GTM_DESTRUCTIVE_REPLY "삭제·publish 같은 위험한 쓰기도 허용할까요? (기본: 비허용) [y/N]: "
  case "$GTM_DESTRUCTIVE_REPLY" in
    [yY]*) GTM_ALLOW_DESTRUCTIVE=1 ;;
  esac
fi

# All servers may have been skipped (e.g. Ads-only with no token).
if [ "$WITH_GA" = "0" ] && [ "$WITH_GA_ADMIN" = "0" ] && [ "$WITH_ADS" = "0" ] && [ "$WITH_GTM" = "0" ]; then
  err "설치할 서버가 없습니다."
  exit 1
fi

# --- 2. Google Cloud SDK ------------------------------------------------------
step "2/6 · Google Cloud SDK 준비"
if command -v gcloud >/dev/null 2>&1; then
  GCLOUD="$(command -v gcloud)"
elif [ -x "$HOME/google-cloud-sdk/bin/gcloud" ]; then
  GCLOUD="$HOME/google-cloud-sdk/bin/gcloud"
else
  info "Google Cloud SDK 설치 중... (수 분 걸릴 수 있어요, 관리자 암호 불필요)"
  curl -fsSL https://sdk.cloud.google.com -o /tmp/ga-mcp-gcloud-install.sh
  bash /tmp/ga-mcp-gcloud-install.sh --disable-prompts --install-dir="$HOME" >/dev/null 2>&1 || true
  GCLOUD="$HOME/google-cloud-sdk/bin/gcloud"
fi
if [ ! -x "$GCLOUD" ] && ! command -v gcloud >/dev/null 2>&1; then
  err "Google Cloud SDK 설치에 실패했습니다."
  err "https://cloud.google.com/sdk/docs/install 의 안내로 설치 후 다시 실행하세요."
  exit 1
fi
ok "Google Cloud SDK 준비 완료 ($GCLOUD)"

# gcloud는 Python 3.10–3.14가 필요한데 시스템 python3가 더 낮으면 실패한다.
# 현재 gcloud가 못 도는 경우에만 uv로 호환 Python을 확보해 지정한다.
if ! CLOUDSDK_CORE_DISABLE_PROMPTS=1 "$GCLOUD" version >/dev/null 2>&1; then
  info "gcloud 실행용 Python 준비 중... (uv가 자동 설치)"
  "$UV" python install 3.12 >/dev/null 2>&1 || true
  CLOUDSDK_PYTHON="$("$UV" python find 3.12 2>/dev/null || true)"
  export CLOUDSDK_PYTHON
  [ -n "$CLOUDSDK_PYTHON" ] && ok "gcloud Python: $CLOUDSDK_PYTHON"
fi

# --- 3. MCP servers (via uv) ---------------------------------------------------
# uv의 출력은 로그에 모아두고, 설치가 실제로 실패했을 때만 보여준다.
# (조용히 삼키면 왜 실패했는지 알 수 없다.)
INSTALL_LOG="/tmp/ga-mcp-install.log"
: >"$INSTALL_LOG"

uv_install() {
  printf '\n$ %s\n' "$*" >>"$INSTALL_LOG"
  "$@" >>"$INSTALL_LOG" 2>&1
}

install_failed() {
  err "$1 실행 파일을 찾을 수 없습니다."
  err "설치 로그 마지막 20줄 (전체: $INSTALL_LOG):"
  tail -20 "$INSTALL_LOG" | sed 's/^/    /' >&2
  exit 1
}

step "3/6 · MCP 서버 설치"
MCP_BIN=""
if [ "$WITH_GA" = "1" ]; then
  info "analytics-mcp 설치/업데이트 중... (공식 PyPI)"
  uv_install "$UV" tool install "$GA_PACKAGE" --quiet \
    || uv_install "$UV" tool upgrade "$GA_PACKAGE" --quiet || true
  MCP_BIN="$HOME/.local/bin/analytics-mcp"
  if [ ! -x "$MCP_BIN" ]; then
    MCP_BIN="$(command -v analytics-mcp 2>/dev/null || true)"
  fi
  if [ -z "$MCP_BIN" ] || [ ! -x "$MCP_BIN" ]; then
    install_failed "analytics-mcp"
  fi
  ok "Analytics 서버 설치 완료 ($MCP_BIN)"
fi

GA_ADMIN_MCP_BIN=""
if [ "$WITH_GA_ADMIN" = "1" ]; then
  info "ga4-admin-mcp 설치/업데이트 중... (이 레포에서)"
  uv_install "$UV" tool install --force "$GA_ADMIN_INSTALL_SOURCE" --quiet || true
  GA_ADMIN_MCP_BIN="$HOME/.local/bin/ga4-admin-mcp"
  if [ ! -x "$GA_ADMIN_MCP_BIN" ]; then
    GA_ADMIN_MCP_BIN="$(command -v ga4-admin-mcp 2>/dev/null || true)"
  fi
  if [ -z "$GA_ADMIN_MCP_BIN" ] || [ ! -x "$GA_ADMIN_MCP_BIN" ]; then
    install_failed "ga4-admin-mcp"
  fi
  ok "GA Admin 서버 설치 완료 ($GA_ADMIN_MCP_BIN)"
fi

ADS_MCP_BIN=""
if [ "$WITH_ADS" = "1" ]; then
  info "google-ads-mcp 설치/업데이트 중..."
  uv_install "$UV" tool install "$ADS_PACKAGE" --quiet \
    || uv_install "$UV" tool upgrade "$ADS_PACKAGE" --quiet || true
  ADS_MCP_BIN="$HOME/.local/bin/google-ads-mcp"
  if [ ! -x "$ADS_MCP_BIN" ]; then
    ADS_MCP_BIN="$(command -v google-ads-mcp 2>/dev/null || true)"
  fi
  if [ -z "$ADS_MCP_BIN" ] || [ ! -x "$ADS_MCP_BIN" ]; then
    install_failed "google-ads-mcp"
  fi
  ok "Ads 서버 설치 완료 ($ADS_MCP_BIN)"
fi

GTM_MCP_BIN=""
if [ "$WITH_GTM" = "1" ]; then
  info "tagmanager-mcp 설치/업데이트 중... (이 포크의 git 소스에서)"
  uv_install "$UV" tool install --force "$GTM_INSTALL_SOURCE" --quiet || true
  GTM_MCP_BIN="$HOME/.local/bin/tagmanager-mcp"
  if [ ! -x "$GTM_MCP_BIN" ]; then
    GTM_MCP_BIN="$(command -v tagmanager-mcp 2>/dev/null || true)"
  fi
  if [ -z "$GTM_MCP_BIN" ] || [ ! -x "$GTM_MCP_BIN" ]; then
    install_failed "tagmanager-mcp"
  fi
  ok "Tag Manager 서버 설치 완료 ($GTM_MCP_BIN)"
fi

# --- 4. Google sign-in & project ---------------------------------------------
step "4/6 · Google 로그인 & 프로젝트"
if ! "$GCLOUD" auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
  info "브라우저에서 Google 계정으로 로그인하세요 (GA 속성에 접근 권한이 있는 계정)."
  "$GCLOUD" auth login
fi
ACTIVE_ACCOUNT="$("$GCLOUD" auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)"
ok "로그인됨: ${ACTIVE_ACCOUNT:-알 수 없음}"

PROJECT="${GA_MCP_PROJECT:-}"
if [ -z "$PROJECT" ]; then
  PROJECT="$("$GCLOUD" config get-value project 2>/dev/null || true)"
  [ "$PROJECT" = "(unset)" ] && PROJECT=""
fi
if [ -z "$PROJECT" ]; then
  echo "사용 가능한 프로젝트:"
  "$GCLOUD" projects list --format="table(projectId, name)" 2>/dev/null || true
  echo ""
  ask PROJECT "사용할 프로젝트 ID를 입력하세요 (없으면 비워두고 Enter → 새로 생성): "
fi
if [ -z "$PROJECT" ]; then
  PROJECT="ga-mcp-$(date +%s)"
  info "새 프로젝트를 생성합니다: $PROJECT"
  "$GCLOUD" projects create "$PROJECT" --name="GA MCP" 1>/dev/null
  warn "새 프로젝트에는 결제 계정 연결이 필요할 수 있습니다 (Data API 무료 할당량 범위 내라면 불필요)."
fi
"$GCLOUD" config set project "$PROJECT" 1>/dev/null 2>&1 || true
ok "프로젝트: $PROJECT"

# --- 5. enable APIs (skip when already active) -------------------------------
# Only the project owner/editor can enable APIs. For a shared project, an admin
# enables them once; everyone else just needs them already on. So we check
# first and skip the enable call when they're active — letting users without
# the enable permission pass this step.
step "5/6 · 필요한 API 확인"
REQUIRED_APIS=""
{ [ "$WITH_GA" = "1" ] || [ "$WITH_GA_ADMIN" = "1" ]; } && REQUIRED_APIS="analyticsadmin.googleapis.com"
[ "$WITH_GA" = "1" ] && REQUIRED_APIS="$REQUIRED_APIS analyticsdata.googleapis.com"
[ "$WITH_ADS" = "1" ] && REQUIRED_APIS="$REQUIRED_APIS googleads.googleapis.com"
[ "$WITH_GTM" = "1" ] && REQUIRED_APIS="$REQUIRED_APIS tagmanager.googleapis.com"
ENABLED_APIS="$("$GCLOUD" services list --enabled --project "$PROJECT" \
  --format="value(config.name)" 2>/dev/null || true)"
MISSING_APIS=""
for api in $REQUIRED_APIS; do
  if printf '%s\n' "$ENABLED_APIS" | grep -qx "$api"; then
    ok "$api (활성화됨)"
  else
    MISSING_APIS="$MISSING_APIS $api"
  fi
done
if [ -n "${MISSING_APIS# }" ]; then
  info "활성화 시도:${MISSING_APIS}"
  # shellcheck disable=SC2086
  if "$GCLOUD" services enable $MISSING_APIS --project "$PROJECT" 2>/dev/null; then
    ok "API 활성화 완료"
  else
    warn "이 계정에는 '$PROJECT' 프로젝트의 API를 활성화할 권한이 없습니다."
    warn "관리자에게 아래 API 활성화를 한 번만 요청하세요:${MISSING_APIS}"
    warn "관리자가 켜두면 이 단계는 자동으로 통과합니다. 일단 계속 진행합니다."
  fi
fi

# --- 6. application default credentials + wire into the selected clients ------
step "6/6 · 인증 & MCP 연결"
info "앱용 인증(ADC) 설정 — 브라우저에서 한 번 더 로그인하세요."
# ADC login overwrites the credentials file, so both servers share one ADC —
# request the union of scopes in a single login.
ADC_SCOPES="https://www.googleapis.com/auth/cloud-platform"
{ [ "$WITH_GA" = "1" ] || [ "$WITH_GA_ADMIN" = "1" ]; } && ADC_SCOPES="$ANALYTICS_READONLY_SCOPE,$ADC_SCOPES"
[ "$WITH_GA_ADMIN" = "1" ] && ADC_SCOPES="$ANALYTICS_EDIT_SCOPE,$ADC_SCOPES"
[ "$WITH_ADS" = "1" ] && ADC_SCOPES="$ADC_SCOPES,$ADWORDS_SCOPE"
[ "$WITH_GTM" = "1" ] && ADC_SCOPES="$ADC_SCOPES,$GTM_SCOPES"
"$GCLOUD" auth application-default login --scopes="$ADC_SCOPES"
"$GCLOUD" auth application-default set-quota-project "$PROJECT" >/dev/null 2>&1 || \
  warn "quota project 설정을 건너뜁니다 ($PROJECT). 권한을 확인하세요."
if [ ! -f "$ADC_PATH" ]; then
  err "인증 정보 파일을 찾을 수 없습니다: $ADC_PATH"
  exit 1
fi
ok "인증 설정 완료"

# Build the server definitions once; every selected client reuses them.
SERVERS_JSON="$(mktemp)"
WITH_GA="$WITH_GA" MCP_BIN="$MCP_BIN" ADC_PATH="$ADC_PATH" PROJECT="$PROJECT" \
WITH_GA_ADMIN="$WITH_GA_ADMIN" GA_ADMIN_MCP_BIN="$GA_ADMIN_MCP_BIN" \
WITH_ADS="$WITH_ADS" ADS_MCP_BIN="$ADS_MCP_BIN" ADS_DEV_TOKEN="$ADS_DEV_TOKEN" \
ADS_LOGIN_CUSTOMER_ID="$ADS_LOGIN_CUSTOMER_ID" \
WITH_GTM="$WITH_GTM" GTM_MCP_BIN="$GTM_MCP_BIN" GTM_ALLOW_DESTRUCTIVE="$GTM_ALLOW_DESTRUCTIVE" \
SERVERS_JSON="$SERVERS_JSON" \
"$UV" run --no-project python - <<'PY'
import json, os

servers = {}
if os.environ.get("WITH_GA") == "1":
    servers["analytics-mcp"] = {
        "command": os.environ["MCP_BIN"],
        "args": [],
        "env": {
            "GOOGLE_APPLICATION_CREDENTIALS": os.environ["ADC_PATH"],
            "GOOGLE_CLOUD_PROJECT": os.environ["PROJECT"],
        },
    }

if os.environ.get("WITH_GA_ADMIN") == "1":
    servers["ga4-admin-mcp"] = {
        "command": os.environ["GA_ADMIN_MCP_BIN"],
        "args": [],
        "env": {
            "GOOGLE_APPLICATION_CREDENTIALS": os.environ["ADC_PATH"],
            "GOOGLE_CLOUD_PROJECT": os.environ["PROJECT"],
        },
    }

if os.environ.get("WITH_ADS") == "1":
    ads_env = {
        "GOOGLE_APPLICATION_CREDENTIALS": os.environ["ADC_PATH"],
        "GOOGLE_PROJECT_ID": os.environ["PROJECT"],
        "GOOGLE_ADS_DEVELOPER_TOKEN": os.environ["ADS_DEV_TOKEN"],
    }
    if os.environ.get("ADS_LOGIN_CUSTOMER_ID"):
        ads_env["GOOGLE_ADS_LOGIN_CUSTOMER_ID"] = os.environ["ADS_LOGIN_CUSTOMER_ID"]
    servers["google-ads-mcp"] = {
        "command": os.environ["ADS_MCP_BIN"],
        "args": [],
        "env": ads_env,
    }

if os.environ.get("WITH_GTM") == "1":
    gtm_env = {
        "GOOGLE_APPLICATION_CREDENTIALS": os.environ["ADC_PATH"],
        "GOOGLE_CLOUD_PROJECT": os.environ["PROJECT"],
    }
    if os.environ.get("GTM_ALLOW_DESTRUCTIVE") == "1":
        gtm_env["GTM_MCP_ALLOW_DESTRUCTIVE"] = "1"
    servers["tagmanager-mcp"] = {
        "command": os.environ["GTM_MCP_BIN"],
        "args": [],
        "env": gtm_env,
    }

with open(os.environ["SERVERS_JSON"], "w") as f:
    json.dump(servers, f)
PY

SERVER_NAMES=""
[ "$WITH_GA" = "1" ] && SERVER_NAMES="analytics-mcp"
[ "$WITH_GA_ADMIN" = "1" ] && SERVER_NAMES="${SERVER_NAMES:+$SERVER_NAMES, }ga4-admin-mcp"
[ "$WITH_ADS" = "1" ] && SERVER_NAMES="${SERVER_NAMES:+$SERVER_NAMES, }google-ads-mcp"
[ "$WITH_GTM" = "1" ] && SERVER_NAMES="${SERVER_NAMES:+$SERVER_NAMES, }tagmanager-mcp"

# Claude Desktop: merge the servers into its config JSON.
if [ "$TARGET_DESKTOP" = "1" ]; then
  if [ -f "$CONFIG" ]; then
    cp "$CONFIG" "${CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    ok "기존 Claude Desktop 설정 백업 완료"
  fi
  CONFIG="$CONFIG" SERVERS_JSON="$SERVERS_JSON" \
  "$UV" run --no-project python - <<'PY'
import json, os

cfg = os.environ["CONFIG"]
os.makedirs(os.path.dirname(cfg), exist_ok=True)

data = {}
if os.path.exists(cfg):
    try:
        with open(cfg, "r") as f:
            data = json.load(f)
    except Exception:
        data = {}

with open(os.environ["SERVERS_JSON"], "r") as f:
    servers = json.load(f)

data.setdefault("mcpServers", {}).update(servers)

with open(cfg, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  ok "Claude Desktop 설정에 $SERVER_NAMES 추가 완료"
fi

# Claude Code CLI: register each server at user scope (remove-then-add to overwrite).
if [ "$TARGET_CLI" = "1" ]; then
  while IFS=$'\t' read -r name cfgjson; do
    [ -z "$name" ] && continue
    "$CLAUDE_BIN" mcp remove -s user "$name" >/dev/null 2>&1 || true
    if "$CLAUDE_BIN" mcp add-json -s user "$name" "$cfgjson" >/dev/null 2>&1; then
      ok "Claude Code CLI에 $name 추가 완료 (user 스코프)"
    else
      err "Claude Code CLI에 $name 추가 실패 — 'claude mcp add-json -s user $name ...'를 직접 실행해 확인하세요."
    fi
  done < <(SERVERS_JSON="$SERVERS_JSON" "$UV" run --no-project python - <<'PY'
import json, os
with open(os.environ["SERVERS_JSON"], "r") as f:
    servers = json.load(f)
for name, cfg in servers.items():
    print(name + "\t" + json.dumps(cfg))
PY
)
fi

# --- done ---------------------------------------------------------------------
printf '\n%s설치가 끝났습니다 🎉%s\n' "$C_GREEN$C_BOLD" "$C_OFF"
echo "다음 단계:"
[ "$TARGET_DESKTOP" = "1" ] && echo "  • Claude Desktop을 완전히 종료했다가 다시 실행하세요."
[ "$TARGET_CLI" = "1" ] && echo "  • Claude Code CLI:  claude mcp list 로 등록을 확인하세요."
echo ""
echo "이렇게 물어보세요:"
[ "$WITH_GA" = "1" ] && echo "  • 내 Google Analytics 속성 목록을 보여줘"
[ "$WITH_GA_ADMIN" = "1" ] && echo "  • 이 속성의 데이터 스트림과 최근 변경 기록을 보여줘"
[ "$WITH_ADS" = "1" ] && echo "  • 내가 접근할 수 있는 Google Ads 계정 보여줘"
[ "$WITH_GTM" = "1" ] && echo "  • 내 GTM 계정과 컨테이너 목록 보여줘"
if [ "$WITH_ADS" = "1" ]; then
  echo ""
  echo "참고: developer token은 설정 파일에 평문으로 저장됩니다."
fi
if [ "$WITH_GTM" = "1" ]; then
  if [ "$GTM_ALLOW_DESTRUCTIVE" = "1" ]; then
    echo "참고: GTM 삭제·publish 허용됨 (GTM_MCP_ALLOW_DESTRUCTIVE=1)"
  else
    echo "참고: GTM 삭제·publish 비활성 (켜려면 tagmanager-mcp env에 GTM_MCP_ALLOW_DESTRUCTIVE=1 추가)"
  fi
fi
if [ "$TARGET_DESKTOP" = "1" ]; then
  echo ""
  echo "문제가 있으면 Claude Desktop 설정 파일을 확인하세요:"
  echo "  $CONFIG"
fi
