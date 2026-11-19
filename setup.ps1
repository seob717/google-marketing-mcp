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
# Windows version of setup.sh — same flow, same questions, same env overrides.
# Runs on Windows PowerShell 5.1 (built in) and PowerShell 7. No git, no admin.
#
# Usage (cmd or PowerShell):
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/seob717/google-marketing-mcp/main/setup.ps1 -OutFile $env:TEMP\gmm-setup.ps1; & $env:TEMP\gmm-setup.ps1"
#
# Env overrides: see setup.sh (GA_MCP_TARGETS, GA_MCP_SERVERS, GA_MCP_PROJECT, ...).
#
# NOTE: this file must stay UTF-8 *with BOM* — Windows PowerShell 5.1 reads
# BOM-less scripts as the ANSI code page and garbles the Korean strings.

$ErrorActionPreference = 'Continue'  # native stderr must not abort under PS 5.1
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Info($m) { Write-Host "▶ $m" -ForegroundColor Blue }
function Ok($m)   { Write-Host "✓ $m" -ForegroundColor Green }
function Warn($m) { Write-Host "! $m" -ForegroundColor Yellow }
function Err($m)  { Write-Host "✗ $m" -ForegroundColor Red }
function Step($m) { Write-Host ""; Write-Host $m -ForegroundColor White }
function Fail($m) { Err $m; exit 1 }

# Yes/No prompt → 1/0. Empty answer takes the default.
function AskYN($prompt, $def) {
  $hint = if ($def -eq 'y') { '[Y/n]' } else { '[y/N]' }
  $r = Read-Host "$prompt $hint"
  if (-not $r) { $r = $def }
  if ($r -match '^[yY]') { 1 } else { 0 }
}
function HasItem($list, $item) { ",$list," -like "*,$item,*" }

$ANALYTICS_READONLY_SCOPE = 'https://www.googleapis.com/auth/analytics.readonly'
$ANALYTICS_EDIT_SCOPE = 'https://www.googleapis.com/auth/analytics.edit'
$ADWORDS_SCOPE = 'https://www.googleapis.com/auth/adwords'
$GTM_SCOPES = 'https://www.googleapis.com/auth/tagmanager.readonly,https://www.googleapis.com/auth/tagmanager.edit.containers,https://www.googleapis.com/auth/tagmanager.edit.containerversions,https://www.googleapis.com/auth/tagmanager.publish'

# --- install sources ----------------------------------------------------------
# Same packages as setup.sh. Our own servers install from the GitHub zip archive
# instead of git+https so Windows PCs without git work too.
$REPO_ZIP = 'https://github.com/seob717/google-marketing-mcp/archive/refs/heads/main.zip'
$GA_PACKAGE = if ($env:GA_PACKAGE) { $env:GA_PACKAGE } else { 'analytics-mcp' }
$GA_ADMIN_INSTALL_SOURCE = if ($env:GA_ADMIN_INSTALL_SOURCE) { $env:GA_ADMIN_INSTALL_SOURCE } else { "ga4-admin-mcp @ $REPO_ZIP#subdirectory=servers/ga4-admin-mcp" }
$ADS_PACKAGE = if ($env:ADS_PACKAGE) { $env:ADS_PACKAGE } else { 'google-ads-mcp' }
$GTM_INSTALL_SOURCE = if ($env:GTM_INSTALL_SOURCE) { $env:GTM_INSTALL_SOURCE } else { "tagmanager-mcp @ $REPO_ZIP#subdirectory=servers/tagmanager-mcp" }
$CONFIG = Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
$ADC_PATH = Join-Path $env:APPDATA 'gcloud\application_default_credentials.json'

Write-Host 'Google Marketing MCP · 설치 (GA · GA Admin · Ads · GTM)' -ForegroundColor White
Write-Host '필요한 도구 설치 → Google 로그인 → Claude Desktop/CLI 연결까지 자동으로 진행합니다.'
Write-Host '(관리자 권한 없이 동작합니다)'

# --- target selection ---------------------------------------------------------
$CLAUDE_BIN = (Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$TARGET_DESKTOP = 0; $TARGET_CLI = 0
if ($env:GA_MCP_TARGETS) {
  if (HasItem $env:GA_MCP_TARGETS 'desktop') { $TARGET_DESKTOP = 1 }
  if (HasItem $env:GA_MCP_TARGETS 'cli') { $TARGET_CLI = 1 }
} else {
  Step '설치할 대상'
  $TARGET_DESKTOP = AskYN 'Claude Desktop에 설치할까요?' 'y'
  if ($CLAUDE_BIN) {
    $TARGET_CLI = AskYN 'Claude Code CLI에 설치할까요?' 'y'
  } else {
    Warn "'claude' CLI가 없어 Claude Code CLI는 건너뜁니다 (https://claude.ai/download)."
  }
}
if ($TARGET_CLI -and -not $CLAUDE_BIN) {
  Warn "'claude' CLI를 찾을 수 없어 Claude Code CLI 설정을 건너뜁니다."
  $TARGET_CLI = 0
}
if (-not $TARGET_DESKTOP -and -not $TARGET_CLI) { Fail '설정할 대상이 없습니다.' }

# --- server selection ---------------------------------------------------------
$WITH_GA = 0; $WITH_GA_ADMIN = 0; $WITH_ADS = 0; $WITH_GTM = 0
if ($env:GA_MCP_SERVERS) {
  if (HasItem $env:GA_MCP_SERVERS 'ga') { $WITH_GA = 1 }
  if (HasItem $env:GA_MCP_SERVERS 'ga-admin') { $WITH_GA_ADMIN = 1 }
  if (HasItem $env:GA_MCP_SERVERS 'ads') { $WITH_ADS = 1 }
  if (HasItem $env:GA_MCP_SERVERS 'gtm') { $WITH_GTM = 1 }
} else {
  Step '설치할 MCP 서버 (필요 없는 건 n)'
  $WITH_GA       = AskYN 'Google Analytics (리포팅)?' 'y'
  $WITH_GA_ADMIN = AskYN 'Google Analytics Admin (데이터 스트림·변경기록)?' 'y'
  $WITH_ADS      = AskYN 'Google Ads (개발자 토큰 필요)?' 'y'
  $WITH_GTM      = AskYN 'Google Tag Manager?' 'y'
}
if (-not ($WITH_GA -or $WITH_GA_ADMIN -or $WITH_ADS -or $WITH_GTM)) { Fail '설치할 서버가 선택되지 않았습니다.' }

# --- Google Ads: developer token ----------------------------------------------
$ADS_DEV_TOKEN = $env:GA_MCP_ADS_DEV_TOKEN
$ADS_LOGIN_CUSTOMER_ID = $env:GA_MCP_ADS_LOGIN_CUSTOMER_ID
if ($WITH_ADS -and -not $ADS_DEV_TOKEN) {
  Write-Host ''
  Info 'Google Ads developer token이 필요합니다.'
  Write-Host '  발급 위치: Google Ads 관리자 계정(MCC) → API 센터'
  Write-Host '  https://ads.google.com/aw/apicenter'
  $ADS_DEV_TOKEN = Read-Host 'developer token을 붙여넣으세요 (건너뛰려면 Enter)'
  if (-not $ADS_DEV_TOKEN) {
    Warn 'developer token이 없어 Google Ads 설정을 건너뜁니다. 발급 후 스크립트를 다시 실행하세요.'
    $WITH_ADS = 0
  }
}
if ($WITH_ADS -and -not $ADS_LOGIN_CUSTOMER_ID) {
  $ADS_LOGIN_CUSTOMER_ID = Read-Host 'MCC(관리자 계정)를 통해 접근한다면 관리자 고객 ID를 입력하세요 (직접 접근이면 Enter)'
}
if ($ADS_LOGIN_CUSTOMER_ID) { $ADS_LOGIN_CUSTOMER_ID = $ADS_LOGIN_CUSTOMER_ID -replace '-', '' }

# --- write / destructive gates -------------------------------------------------
$GA_ADMIN_ALLOW_DESTRUCTIVE = $env:GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE
if ($WITH_GA_ADMIN -and -not $GA_ADMIN_ALLOW_DESTRUCTIVE) {
  if (AskYN 'GA4 설정의 보관·삭제 같은 위험한 쓰기도 허용할까요? (기본: 비허용)' 'n') { $GA_ADMIN_ALLOW_DESTRUCTIVE = '1' }
}
$GTM_ALLOW_DESTRUCTIVE = $env:GTM_MCP_ALLOW_DESTRUCTIVE
if ($WITH_GTM -and -not $GTM_ALLOW_DESTRUCTIVE) {
  if (AskYN '삭제·publish 같은 위험한 쓰기도 허용할까요? (기본: 비허용)' 'n') { $GTM_ALLOW_DESTRUCTIVE = '1' }
}
$GA_ALLOW_WRITE = $env:GA_MCP_ALLOW_WRITE
if ($WITH_GA -and -not $GA_ALLOW_WRITE) {
  if (AskYN 'GA 주석 만들기 같은 쓰기 도구도 켤까요? (기본: 끔)' 'n') { $GA_ALLOW_WRITE = '1' }
}
if (-not ($WITH_GA -or $WITH_GA_ADMIN -or $WITH_ADS -or $WITH_GTM)) { Fail '설치할 서버가 없습니다.' }

# --- 1. uv ---------------------------------------------------------------------
Step '1/6 · 실행 도구 준비 (uv)'
$UV = (Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $UV) { $UV = Join-Path $env:USERPROFILE '.local\bin\uv.exe' }
if (-not (Test-Path $UV)) {
  Info 'uv 설치 중... (관리자 권한 불필요)'
  powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex" *> $null
}
if (-not (Test-Path $UV)) { Fail 'uv 설치에 실패했습니다. 인터넷 연결을 확인하고 다시 실행하세요.' }
Ok "uv 준비 완료 ($UV)"

# --- 2. Google Cloud SDK -------------------------------------------------------
Step '2/6 · Google Cloud SDK 준비'
function Find-GCloud {
  $c = (Get-Command gcloud -ErrorAction SilentlyContinue | Select-Object -First 1).Source
  if ($c) { return $c }
  foreach ($root in @($env:LOCALAPPDATA, ${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if (-not $root) { continue }
    $p = Join-Path $root 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'
    if (Test-Path $p) { return $p }
  }
}
$GCLOUD = Find-GCloud
if (-not $GCLOUD) {
  Info 'Google Cloud SDK 설치 중... (수 분 걸릴 수 있어요, 관리자 권한 불필요)'
  $installer = Join-Path $env:TEMP 'GoogleCloudSDKInstaller.exe'
  Invoke-WebRequest 'https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe' -OutFile $installer -UseBasicParsing
  # ponytail: silent single-user install; if it ever needs a GUI, the error below points to the manual installer.
  Start-Process $installer -ArgumentList '/S', '/singleuser', '/noreporting', '/nostartmenu', '/nodesktop' -Wait
  $GCLOUD = Find-GCloud
}
if (-not $GCLOUD) {
  Err 'Google Cloud SDK 설치에 실패했습니다.'
  Fail 'https://cloud.google.com/sdk/docs/install 의 Windows 설치 프로그램으로 설치 후 다시 실행하세요.'
}
Ok "Google Cloud SDK 준비 완료 ($GCLOUD)"

# --- 3. MCP servers (via uv) ---------------------------------------------------
$INSTALL_LOG = Join-Path $env:TEMP 'ga-mcp-install.log'
Set-Content $INSTALL_LOG '' -Encoding UTF8
$BIN_DIR = (& $UV tool dir --bin 2>$null | Select-Object -First 1)
if (-not $BIN_DIR) { $BIN_DIR = Join-Path $env:USERPROFILE '.local\bin' }

# Install (or upgrade) one server; returns its .exe path or stops with the log tail.
function Install-Server($label, $source, $exe) {
  Info "$exe 설치/업데이트 중..."
  Add-Content $INSTALL_LOG "`n$ uv tool install --force $source"
  & $UV tool install --force $source --quiet 2>&1 | Out-File $INSTALL_LOG -Append -Encoding UTF8
  $bin = Join-Path $BIN_DIR "$exe.exe"
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $bin)) {
    Err "$exe 실행 파일을 찾을 수 없습니다."
    Err "설치 로그 마지막 20줄 (전체: $INSTALL_LOG):"
    Get-Content $INSTALL_LOG -Tail 20 | ForEach-Object { Write-Host "    $_" }
    exit 1
  }
  Ok "$label 서버 설치 완료 ($bin)"
  return $bin
}

Step '3/6 · MCP 서버 설치'
if ($WITH_GA)       { $MCP_BIN = Install-Server 'Analytics' $GA_PACKAGE 'analytics-mcp' }
if ($WITH_GA_ADMIN) { $GA_ADMIN_MCP_BIN = Install-Server 'GA Admin' $GA_ADMIN_INSTALL_SOURCE 'ga4-admin-mcp' }
if ($WITH_ADS)      { $ADS_MCP_BIN = Install-Server 'Ads' $ADS_PACKAGE 'google-ads-mcp' }
if ($WITH_GTM)      { $GTM_MCP_BIN = Install-Server 'Tag Manager' $GTM_INSTALL_SOURCE 'tagmanager-mcp' }

# --- 4. Google sign-in & project ---------------------------------------------
Step '4/6 · Google 로그인 & 프로젝트'
# gcloud is a .cmd on Windows: keep --format values with parens inside "..." so cmd.exe leaves them alone.
function Active-Account { & $GCLOUD auth list --filter=status:ACTIVE '--format="value(account)"' 2>$null | Select-Object -First 1 }
if (-not (Active-Account)) {
  Info '브라우저에서 Google 계정으로 로그인하세요 (GA 속성에 접근 권한이 있는 계정).'
  & $GCLOUD auth login
}
$ACTIVE_ACCOUNT = Active-Account
Ok "로그인됨: $(if ($ACTIVE_ACCOUNT) { $ACTIVE_ACCOUNT } else { '알 수 없음' })"

$PROJECT = $env:GA_MCP_PROJECT
if (-not $PROJECT) {
  $PROJECT = & $GCLOUD config get-value project 2>$null | Select-Object -First 1
  if ($PROJECT -eq '(unset)') { $PROJECT = '' }
}
if (-not $PROJECT) {
  Write-Host '사용 가능한 프로젝트:'
  & $GCLOUD projects list '--format="table(projectId, name)"' 2>$null
  Write-Host ''
  $PROJECT = Read-Host '사용할 프로젝트 ID를 입력하세요 (없으면 비워두고 Enter → 새로 생성)'
}
if (-not $PROJECT) {
  $PROJECT = "ga-mcp-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
  Info "새 프로젝트를 생성합니다: $PROJECT"
  & $GCLOUD projects create $PROJECT --name='GA MCP' | Out-Null
  Warn '새 프로젝트에는 결제 계정 연결이 필요할 수 있습니다 (Data API 무료 할당량 범위 내라면 불필요).'
}
& $GCLOUD config set project $PROJECT *> $null
Ok "프로젝트: $PROJECT"

# --- 5. enable APIs (skip when already active) -------------------------------
Step '5/6 · 필요한 API 확인'
$REQUIRED_APIS = @()
if ($WITH_GA -or $WITH_GA_ADMIN) { $REQUIRED_APIS += 'analyticsadmin.googleapis.com' }
if ($WITH_GA)  { $REQUIRED_APIS += 'analyticsdata.googleapis.com' }
if ($WITH_ADS) { $REQUIRED_APIS += 'googleads.googleapis.com' }
if ($WITH_GTM) { $REQUIRED_APIS += 'tagmanager.googleapis.com' }
$ENABLED_APIS = @(& $GCLOUD services list --enabled --project $PROJECT '--format="value(config.name)"' 2>$null)
$MISSING_APIS = @()
foreach ($api in $REQUIRED_APIS) {
  if ($ENABLED_APIS -contains $api) { Ok "$api (활성화됨)" } else { $MISSING_APIS += $api }
}
if ($MISSING_APIS.Count -gt 0) {
  Info "활성화 시도: $($MISSING_APIS -join ' ')"
  & $GCLOUD services enable @MISSING_APIS --project $PROJECT 2>$null
  if ($LASTEXITCODE -eq 0) {
    Ok 'API 활성화 완료'
  } else {
    Warn "이 계정에는 '$PROJECT' 프로젝트의 API를 활성화할 권한이 없습니다."
    Warn "관리자에게 아래 API 활성화를 한 번만 요청하세요: $($MISSING_APIS -join ' ')"
    Warn '관리자가 켜두면 이 단계는 자동으로 통과합니다. 일단 계속 진행합니다.'
  }
}

# --- 6. application default credentials + wire into the selected clients ------
Step '6/6 · 인증 & MCP 연결'
Info '앱용 인증(ADC) 설정 — 브라우저에서 한 번 더 로그인하세요.'
$ADC_SCOPES = 'https://www.googleapis.com/auth/cloud-platform'
if ($WITH_GA -or $WITH_GA_ADMIN) { $ADC_SCOPES = "$ANALYTICS_READONLY_SCOPE,$ADC_SCOPES" }
if ($WITH_GA_ADMIN) { $ADC_SCOPES = "$ANALYTICS_EDIT_SCOPE,$ADC_SCOPES" }
if ($WITH_ADS) { $ADC_SCOPES = "$ADC_SCOPES,$ADWORDS_SCOPE" }
if ($WITH_GTM) { $ADC_SCOPES = "$ADC_SCOPES,$GTM_SCOPES" }
& $GCLOUD auth application-default login "--scopes=$ADC_SCOPES"
& $GCLOUD auth application-default set-quota-project $PROJECT *> $null
if ($LASTEXITCODE -ne 0) { Warn "quota project 설정을 건너뜁니다 ($PROJECT). 권한을 확인하세요." }
if (-not (Test-Path $ADC_PATH)) { Fail "인증 정보 파일을 찾을 수 없습니다: $ADC_PATH" }
Ok '인증 설정 완료'

# Server definitions — same shape as setup.sh (see the comments there for why
# GRPC_DNS_RESOLVER=native and the quota-project env are set).
$grpcEnv = [ordered]@{
  GOOGLE_APPLICATION_CREDENTIALS = $ADC_PATH
  GOOGLE_CLOUD_PROJECT = $PROJECT
  GOOGLE_CLOUD_QUOTA_PROJECT = $PROJECT
  GRPC_DNS_RESOLVER = 'native'
}
if ($env:GA_MCP_GRPC_PROXY) { $grpcEnv.grpc_proxy = $env:GA_MCP_GRPC_PROXY }
function Copy-GrpcEnv { $h = [ordered]@{}; foreach ($k in $grpcEnv.Keys) { $h[$k] = $grpcEnv[$k] }; $h }

$servers = [ordered]@{}
if ($WITH_GA) {
  $args_ = @(); if ($GA_ALLOW_WRITE -eq '1') { $args_ = @('--allow-write') }
  $servers['analytics-mcp'] = [ordered]@{ command = $MCP_BIN; args = $args_; env = (Copy-GrpcEnv) }
}
if ($WITH_GA_ADMIN) {
  $e = Copy-GrpcEnv
  if ($env:GA4_ADMIN_MCP_TRANSPORT) { $e.GA4_ADMIN_MCP_TRANSPORT = $env:GA4_ADMIN_MCP_TRANSPORT }
  if ($GA_ADMIN_ALLOW_DESTRUCTIVE -eq '1') { $e.GA4_ADMIN_MCP_ALLOW_DESTRUCTIVE = '1' }
  $servers['ga4-admin-mcp'] = [ordered]@{ command = $GA_ADMIN_MCP_BIN; args = @(); env = $e }
}
if ($WITH_ADS) {
  $e = [ordered]@{
    GOOGLE_APPLICATION_CREDENTIALS = $ADC_PATH
    GOOGLE_PROJECT_ID = $PROJECT
    GOOGLE_ADS_DEVELOPER_TOKEN = $ADS_DEV_TOKEN
    GRPC_DNS_RESOLVER = 'native'
  }
  if ($env:GA_MCP_GRPC_PROXY) { $e.grpc_proxy = $env:GA_MCP_GRPC_PROXY }
  if ($ADS_LOGIN_CUSTOMER_ID) { $e.GOOGLE_ADS_LOGIN_CUSTOMER_ID = $ADS_LOGIN_CUSTOMER_ID }
  $servers['google-ads-mcp'] = [ordered]@{ command = $ADS_MCP_BIN; args = @(); env = $e }
}
if ($WITH_GTM) {
  $e = [ordered]@{
    GOOGLE_APPLICATION_CREDENTIALS = $ADC_PATH
    GOOGLE_CLOUD_PROJECT = $PROJECT
    GOOGLE_CLOUD_QUOTA_PROJECT = $PROJECT
  }
  if ($GTM_ALLOW_DESTRUCTIVE -eq '1') { $e.GTM_MCP_ALLOW_DESTRUCTIVE = '1' }
  $servers['tagmanager-mcp'] = [ordered]@{ command = $GTM_MCP_BIN; args = @(); env = $e }
}
$SERVER_NAMES = $servers.Keys -join ', '
$utf8NoBom = New-Object Text.UTF8Encoding $false

# Claude Desktop: merge into its config JSON. The Microsoft Store (MSIX) build
# reads a virtualized copy under %LOCALAPPDATA%\Packages\Claude_*, so update that
# one too when it exists.
function Merge-DesktopConfig($cfg) {
  if (Test-Path $cfg) {
    Copy-Item $cfg "$cfg.bak.$(Get-Date -Format yyyyMMddHHmmss)"
    Ok "기존 Claude Desktop 설정 백업 완료 ($cfg)"
  }
  New-Item -ItemType Directory -Force (Split-Path $cfg) | Out-Null
  $data = $null
  if (Test-Path $cfg) {
    try { $data = [IO.File]::ReadAllText($cfg) | ConvertFrom-Json } catch { $data = $null }
  }
  if (-not $data) { $data = New-Object PSObject }
  if (-not $data.mcpServers) { $data | Add-Member -NotePropertyName mcpServers -NotePropertyValue (New-Object PSObject) -Force }
  foreach ($k in $servers.Keys) {
    $data.mcpServers | Add-Member -NotePropertyName $k -NotePropertyValue $servers[$k] -Force
  }
  [IO.File]::WriteAllText($cfg, ($data | ConvertTo-Json -Depth 20) + "`n", $utf8NoBom)
}

$DESKTOP_CONFIGS = @($CONFIG)
Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
  ForEach-Object { $DESKTOP_CONFIGS += Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json' }
if ($TARGET_DESKTOP) {
  foreach ($cfg in $DESKTOP_CONFIGS) { Merge-DesktopConfig $cfg }
  Ok "Claude Desktop 설정에 $SERVER_NAMES 추가 완료"
}

# Claude Code CLI: `claude mcp add` with -e pairs instead of add-json — passing a
# JSON string to a native .cmd/.exe from PS 5.1 strips its inner quotes.
if ($TARGET_CLI) {
  foreach ($name in $servers.Keys) {
    $s = $servers[$name]
    & $CLAUDE_BIN mcp remove -s user $name *> $null
    $cliArgs = @('mcp', 'add', '-s', 'user', $name)
    foreach ($k in $s.env.Keys) { $cliArgs += @('-e', "$k=$($s.env[$k])") }
    $cliArgs += @('--', $s.command) + $s.args
    & $CLAUDE_BIN @cliArgs *> $null
    if ($LASTEXITCODE -eq 0) {
      Ok "Claude Code CLI에 $name 추가 완료 (user 스코프)"
    } else {
      Err "Claude Code CLI에 $name 추가 실패 — 'claude mcp list'로 확인하세요."
    }
  }
}

# --- done ---------------------------------------------------------------------
Write-Host ''
Write-Host '설치가 끝났습니다 🎉' -ForegroundColor Green
Write-Host '다음 단계:'
if ($TARGET_DESKTOP) { Write-Host '  • Claude Desktop을 완전히 종료(작업 표시줄 트레이 아이콘 → Quit)했다가 다시 실행하세요.' }
if ($TARGET_CLI) { Write-Host '  • Claude Code CLI:  claude mcp list 로 등록을 확인하세요.' }
Write-Host ''
Write-Host '이렇게 물어보세요:'
if ($WITH_GA) { Write-Host '  • 내 Google Analytics 속성 목록을 보여줘' }
if ($WITH_GA_ADMIN) { Write-Host '  • 이 속성의 데이터 스트림과 최근 변경 기록을 보여줘' }
if ($WITH_ADS) { Write-Host '  • 내가 접근할 수 있는 Google Ads 계정 보여줘' }
if ($WITH_GTM) { Write-Host '  • 내 GTM 계정과 컨테이너 목록 보여줘' }
if ($WITH_ADS) { Write-Host ''; Write-Host '참고: developer token은 설정 파일에 평문으로 저장됩니다.' }
if ($TARGET_DESKTOP) {
  Write-Host ''
  Write-Host '문제가 있으면 Claude Desktop 설정 파일을 확인하세요:'
  foreach ($cfg in $DESKTOP_CONFIGS) { Write-Host "  $cfg" }
}
