#!/usr/bin/env python3

from __future__ import annotations

import pathlib
import plistlib
import shlex
import shutil
import sys


ROOT = pathlib.Path(__file__).resolve().parent.parent
ENV_PATH = ROOT / ".env"
SOURCE_ENV_KEY = "GOOGLE_CLIENT_PLIST_PATH"
PROJECT_DIR = ROOT / "Calendar Busy Sync"
APP_DIR = PROJECT_DIR / "Calendar Busy Sync"
APP_DEFAULT_PLIST = APP_DIR / "DefaultGoogleOAuth.plist"
APP_INFO_PLIST = PROJECT_DIR / "Info.plist"


def load_env(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values

    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, raw_value = line.split("=", 1)
        key = key.strip()
        raw_value = raw_value.strip()
        if not key:
            continue
        if raw_value:
            parsed = shlex.split(raw_value, posix=True)
            values[key] = parsed[0] if parsed else ""
        else:
            values[key] = ""
    return values


def require_source_plist() -> pathlib.Path:
    env = load_env(ENV_PATH)
    raw_path = env.get(SOURCE_ENV_KEY, "").strip()
    if not raw_path:
        raise SystemExit(f"missing {SOURCE_ENV_KEY} in {ENV_PATH}")

    source = pathlib.Path(raw_path)
    if not source.is_absolute():
        source = ROOT / source
    source = source.resolve()
    if not source.exists():
        raise SystemExit(f"google client plist does not exist: {source}")
    return source


def load_google_client_config(path: pathlib.Path) -> dict[str, str]:
    with path.open("rb") as handle:
        payload = plistlib.load(handle)

    required_keys = ["CLIENT_ID", "REVERSED_CLIENT_ID", "BUNDLE_ID"]
    missing = [key for key in required_keys if not payload.get(key)]
    if missing:
        raise SystemExit(f"google client plist missing keys: {', '.join(missing)}")
    return payload


def write_info_plist(client_config: dict[str, str]) -> None:
    info = {
        "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "CFBundleURLTypes": [
            {
                "CFBundleTypeRole": "Editor",
                "CFBundleURLSchemes": [client_config["REVERSED_CLIENT_ID"]],
            }
        ],
        "GIDClientID": client_config["CLIENT_ID"],
    }

    APP_INFO_PLIST.parent.mkdir(parents=True, exist_ok=True)
    with APP_INFO_PLIST.open("wb") as handle:
        plistlib.dump(info, handle, sort_keys=False)


def copy_default_plist(source: pathlib.Path) -> None:
    APP_DEFAULT_PLIST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, APP_DEFAULT_PLIST)


def main() -> int:
    source = require_source_plist()
    config = load_google_client_config(source)
    copy_default_plist(source)
    write_info_plist(config)
    print(f"synced Google client plist from {source}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
