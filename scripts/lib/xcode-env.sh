#!/bin/zsh

set -euo pipefail

if [[ -n "${ZSH_VERSION:-}" ]]; then
  XCODE_ENV_SOURCE_PATH="${(%):-%x}"
elif [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  XCODE_ENV_SOURCE_PATH="${BASH_SOURCE[0]}"
else
  XCODE_ENV_SOURCE_PATH="$0"
fi

ROOT_DIR="$(cd "$(dirname "${XCODE_ENV_SOURCE_PATH}")/../.." && pwd)"
source "${ROOT_DIR}/scripts/lib/product-identity.sh"
LOCAL_ENV_PATH="${ROOT_DIR}/.env"
DEFAULT_APPLE_SIGNING_TEAM_ID="GG34PA8F4A"
DEFAULT_APPLE_DISTRIBUTION_SIGNING_IDENTITY="Apple Distribution: Sous Chef Studio, Inc. (GG34PA8F4A)"
DEFAULT_APPLE_DISTRIBUTION_SIGNING_SHA1="2C2851AE3C7CD73F56F377FEC2F0696AC66957DC"
LOCAL_ENV_LOADED=0

PROJECT_PATH="${ROOT_DIR}/${APP_PROJECT_DIR_NAME}/${APP_PROJECT_FILE_NAME}"
SCHEME_NAME="${APP_SCHEME_NAME}"
BUNDLE_IDENTIFIER="${APP_BUNDLE_IDENTIFIER}"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
XCODEBUILD_DIR="${ARTIFACTS_DIR}/xcodebuild"
TEST_RESULTS_DIR="${ARTIFACTS_DIR}/test-results"
CHECKPOINTS_DIR="${ARTIFACTS_DIR}/checkpoints"
DERIVED_DATA_DIR="${ARTIFACTS_DIR}/DerivedData"
SIGNED_DERIVED_DATA_DIR="${ARTIFACTS_DIR}/DerivedDataSigned"
FIXTURE_ROOT="${ROOT_DIR}/Fixtures/scenarios"
GOOGLE_CLIENT_CONFIG_SYNC_SCRIPT="${ROOT_DIR}/scripts/sync-google-client-config.py"
GOOGLE_DEFAULT_CLIENT_PLIST_PATH="${ROOT_DIR}/Calendar Busy Sync/Calendar Busy Sync/DefaultGoogleOAuth.plist"
GOOGLE_INFO_PLIST_PATH="${ROOT_DIR}/Calendar Busy Sync/Info.plist"

MAC_DESTINATION="platform=macOS,arch=arm64"

load_local_env() {
  if [[ "${LOCAL_ENV_LOADED}" -eq 1 ]]; then
    return 0
  fi

  if [[ -f "${LOCAL_ENV_PATH}" ]]; then
    set -a
    source "${LOCAL_ENV_PATH}"
    set +a
  fi

  LOCAL_ENV_LOADED=1
}

apple_signing_team_id() {
  load_local_env
  printf '%s\n' "${APPLE_SIGNING_TEAM_ID:-${DEFAULT_APPLE_SIGNING_TEAM_ID}}"
}

apple_distribution_signing_identity() {
  load_local_env
  printf '%s\n' "${APPLE_DISTRIBUTION_SIGNING_IDENTITY:-${DEFAULT_APPLE_DISTRIBUTION_SIGNING_IDENTITY}}"
}

apple_distribution_signing_sha1() {
  load_local_env
  printf '%s\n' "${APPLE_DISTRIBUTION_SIGNING_SHA1:-${DEFAULT_APPLE_DISTRIBUTION_SIGNING_SHA1}}"
}

appstore_connect_api_key_id() {
  load_local_env
  printf '%s\n' "${ASC_KEY_ID:-}"
}

appstore_connect_api_issuer_id() {
  load_local_env
  printf '%s\n' "${ASC_ISSUER_ID:-}"
}

appstore_connect_api_key_path() {
  load_local_env
  local key_path="${ASC_KEY_PATH:-}"
  if [[ -z "${key_path}" ]]; then
    return 0
  fi
  if [[ "${key_path}" = /* ]]; then
    printf '%s\n' "${key_path}"
  else
    printf '%s\n' "${ROOT_DIR}/${key_path#./}"
  fi
}

ensure_dirs() {
  mkdir -p "${ARTIFACTS_DIR}" "${XCODEBUILD_DIR}" "${TEST_RESULTS_DIR}" "${CHECKPOINTS_DIR}" "${DERIVED_DATA_DIR}" "${SIGNED_DERIVED_DATA_DIR}"
}

sync_google_client_config() {
  python3 "${GOOGLE_CLIENT_CONFIG_SYNC_SCRIPT}"
}

preferred_sim_id() {
  python3 - "$@" <<'PY'
import json
import subprocess
import sys

preferred_names = sys.argv[1:]
payload = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j", "devices", "available"], text=True))
devices_by_runtime = payload.get("devices", {})

for runtime in sorted(devices_by_runtime.keys(), reverse=True):
    devices = [device for device in devices_by_runtime[runtime] if device.get("isAvailable")]
    names_to_ids = {device.get("name"): device.get("udid") for device in devices}
    for name in preferred_names:
        if name in names_to_ids:
            print(names_to_ids[name])
            raise SystemExit(0)
raise SystemExit(1)
PY
}

iphone_sim_id() {
  local id
  id="$(preferred_sim_id \
    "iPhone 17" \
    "iPhone 17 Pro" \
    "iPhone 16e" \
    "iPhone Air" \
    "iPhone 16" \
    "iPhone 15 Pro" \
    "iPhone 15" \
    "iPhone SE (3rd generation)")"
  [[ -n "${id}" ]] || return 1
  printf '%s\n' "${id}"
}

ipad_sim_id() {
  local id
  id="$(preferred_sim_id \
    "iPad Air 11-inch (M3)" \
    "iPad Pro 11-inch (M5)" \
    "iPad mini (A17 Pro)" \
    "iPad (A16)" \
    "iPad Pro 11-inch (M4)" \
    "iPad Pro (11-inch) (4th generation)" \
    "iPad Air 11-inch (M2)" \
    "iPad (10th generation)")"
  [[ -n "${id}" ]] || return 1
  printf '%s\n' "${id}"
}

result_bundle_path() {
  local name="$1"
  printf '%s/%s.xcresult\n' "${XCODEBUILD_DIR}" "${name}"
}

app_bundle_path() {
  printf '%s/Build/Products/Debug/%s.app\n' "${DERIVED_DATA_DIR}" "${APP_PRODUCT_NAME}"
}

signed_app_bundle_path() {
  printf '%s/Build/Products/Debug/%s.app\n' "${SIGNED_DERIVED_DATA_DIR}" "${APP_PRODUCT_NAME}"
}

ios_app_bundle_path() {
  printf '%s/Build/Products/Debug-iphonesimulator/%s.app\n' "${DERIVED_DATA_DIR}" "${APP_PRODUCT_NAME}"
}

app_binary_path() {
  printf '%s/Contents/MacOS/%s\n' "$(app_bundle_path)" "${APP_PRODUCT_NAME}"
}

ios_platform_installed() {
  [[ -d "${PROJECT_PATH}" ]] || return 1
  xcodebuild -showdestinations -project "${PROJECT_PATH}" -scheme "${SCHEME_NAME}" 2>/dev/null | grep -q "platform:iOS Simulator"
}

require_project() {
  [[ -d "${PROJECT_PATH}" ]] || {
    echo "Missing project at ${PROJECT_PATH}" >&2
    echo "Create the Xcode project before using build/test harness commands." >&2
    exit 1
  }
}
