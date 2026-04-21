#!/usr/bin/env python3

from __future__ import annotations

import argparse
import importlib.util
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_APP_ID = "6762634278"
DEFAULT_SUPPORT_URL = "https://souschefstudio.com/"
DEFAULT_MARKETING_URL = "https://souschefstudio.com/"
DEFAULT_PRIVACY_POLICY_URL = "https://souschefstudio.com/privacy"
IPHONE_DISPLAY_TYPE = "APP_IPHONE_67"
IPAD_DISPLAY_TYPE = "APP_IPAD_PRO_3GEN_129"


def load_mac_submission_module():
    module_path = ROOT_DIR / "scripts" / "prepare-appstore-macos-submission.py"
    spec = importlib.util.spec_from_file_location("mac_submission", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load shared App Store helper from {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


mac_submission = load_mac_submission_module()
AppStoreConnectClient = mac_submission.AppStoreConnectClient
load_env_file = mac_submission.load_env_file
env_value = mac_submission.env_value
ensure_primary_category = mac_submission.ensure_primary_category
ensure_age_rating = mac_submission.ensure_age_rating
update_localizations = mac_submission.update_localizations
attach_build = mac_submission.attach_build
clear_existing_screenshots = mac_submission.clear_existing_screenshots
upload_screenshot = mac_submission.upload_screenshot
maybe_update_review_detail = mac_submission.maybe_update_review_detail


@dataclass
class IOSSubmissionState:
    version_id: str
    version_string: str
    version_localization_id: str
    app_info_id: str
    app_info_localization_id: str
    age_rating_declaration_id: str
    screenshot_set_ids: dict[str, str]
    attached_build_id: str | None


def resolve_state(client: AppStoreConnectClient, app_id: str) -> IOSSubmissionState:
    versions = client.request("GET", f"apps/{app_id}/appStoreVersions", params={"limit": 50})
    version_data = next(item for item in versions["data"] if item["attributes"]["platform"] == "IOS")

    localization_payload = client.request(
        "GET",
        f"appStoreVersions/{version_data['id']}/appStoreVersionLocalizations",
    )
    if not localization_payload["data"]:
        raise RuntimeError("iOS App Store version has no localization record.")
    version_localization_id = localization_payload["data"][0]["id"]

    build_payload = client.request("GET", f"appStoreVersions/{version_data['id']}/build")
    attached_build_id = None if build_payload["data"] is None else build_payload["data"]["id"]

    app_infos = client.request("GET", f"apps/{app_id}/appInfos", params={"include": "appInfoLocalizations"})
    app_info = app_infos["data"][0]
    app_info_localization_id = app_info["relationships"]["appInfoLocalizations"]["data"][0]["id"]

    screenshot_sets = client.request(
        "GET",
        f"appStoreVersionLocalizations/{version_localization_id}/appScreenshotSets",
    )
    screenshot_set_ids = {
        item["attributes"]["screenshotDisplayType"]: item["id"] for item in screenshot_sets["data"]
    }

    return IOSSubmissionState(
        version_id=version_data["id"],
        version_string=version_data["attributes"]["versionString"],
        version_localization_id=version_localization_id,
        app_info_id=app_info["id"],
        app_info_localization_id=app_info_localization_id,
        age_rating_declaration_id=app_info["id"],
        screenshot_set_ids=screenshot_set_ids,
        attached_build_id=attached_build_id,
    )


def latest_matching_build(client: AppStoreConnectClient, app_id: str, version_string: str) -> dict[str, Any]:
    builds = client.request(
        "GET",
        "builds",
        params={
            "filter[app]": app_id,
            "filter[preReleaseVersion.platform]": "IOS",
            "include": "preReleaseVersion",
            "sort": "-uploadedDate",
            "limit": 50,
        },
    )

    prerelease_versions = {
        item["id"]: item for item in builds.get("included", []) if item["type"] == "preReleaseVersions"
    }
    for build in builds["data"]:
        prerelease_data = build.get("relationships", {}).get("preReleaseVersion", {}).get("data")
        if prerelease_data is None:
            continue
        prerelease = prerelease_versions.get(prerelease_data["id"])
        if prerelease is None:
            continue
        if prerelease["attributes"]["version"] != version_string:
            continue
        if build["attributes"]["processingState"] != "VALID":
            continue
        if build["attributes"]["buildAudienceType"] != "APP_STORE_ELIGIBLE":
            continue
        return build

    raise RuntimeError(
        f"No valid iOS build found for App Store version {version_string}. Upload a build whose short version matches."
    )


def ensure_screenshot_set(
    client: AppStoreConnectClient,
    version_localization_id: str,
    display_type: str,
    existing_screenshot_set_id: str | None,
) -> str:
    if existing_screenshot_set_id is not None:
        return existing_screenshot_set_id

    created = client.request(
        "POST",
        "appScreenshotSets",
        payload={
            "data": {
                "type": "appScreenshotSets",
                "attributes": {
                    "screenshotDisplayType": display_type,
                },
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "id": version_localization_id,
                        }
                    }
                },
            }
        },
        expected=(201,),
    )
    return created["data"]["id"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare the iOS App Store submission state for Calendar Busy Sync.")
    parser.add_argument("--app-id", default=DEFAULT_APP_ID)
    parser.add_argument("--iphone-dir", type=Path, required=True)
    parser.add_argument("--ipad-dir", type=Path, required=True)
    parser.add_argument("--support-url", default=DEFAULT_SUPPORT_URL)
    parser.add_argument("--marketing-url", default=DEFAULT_MARKETING_URL)
    parser.add_argument("--privacy-policy-url", default=DEFAULT_PRIVACY_POLICY_URL)
    args = parser.parse_args()

    env_defaults = load_env_file(ROOT_DIR / ".env")
    key_id = env_value("ASC_KEY_ID", env_defaults)
    issuer_id = env_value("ASC_ISSUER_ID", env_defaults)
    key_path_value = env_value("ASC_KEY_PATH", env_defaults)

    if not key_id or not issuer_id or not key_path_value:
        raise RuntimeError("Missing App Store Connect API credentials in the environment or .env.")

    key_path = Path(key_path_value)
    if not key_path.is_absolute():
        key_path = ROOT_DIR / key_path
    if not key_path.exists():
        raise RuntimeError(f"Missing App Store Connect API key file at {key_path}")

    iphone_paths = sorted(path for path in args.iphone_dir.glob("*.png"))
    ipad_paths = sorted(path for path in args.ipad_dir.glob("*.png"))
    if not iphone_paths:
        raise RuntimeError(f"No PNG screenshots found in {args.iphone_dir}")
    if not ipad_paths:
        raise RuntimeError(f"No PNG screenshots found in {args.ipad_dir}")

    client = AppStoreConnectClient(key_id, issuer_id, key_path)
    state = resolve_state(client, args.app_id)

    warnings: list[str] = []

    category_warning = ensure_primary_category(client, state.app_info_id)
    if category_warning:
        warnings.append(category_warning)
    ensure_age_rating(client, state.age_rating_declaration_id)
    update_localizations(
        client,
        state,
        support_url=args.support_url,
        marketing_url=args.marketing_url,
        privacy_policy_url=args.privacy_policy_url,
    )

    build: dict[str, Any] | None = None
    build_warning: str | None = None
    try:
        build = latest_matching_build(client, args.app_id, state.version_string)
        attach_build(client, state.version_id, build["id"])
    except RuntimeError as exc:
        build_warning = str(exc)

    iphone_set_id = ensure_screenshot_set(
        client,
        state.version_localization_id,
        IPHONE_DISPLAY_TYPE,
        state.screenshot_set_ids.get(IPHONE_DISPLAY_TYPE),
    )
    clear_existing_screenshots(client, iphone_set_id)
    for screenshot_path in iphone_paths:
        upload_screenshot(client, iphone_set_id, screenshot_path)

    ipad_set_id = ensure_screenshot_set(
        client,
        state.version_localization_id,
        IPAD_DISPLAY_TYPE,
        state.screenshot_set_ids.get(IPAD_DISPLAY_TYPE),
    )
    clear_existing_screenshots(client, ipad_set_id)
    for screenshot_path in ipad_paths:
        upload_screenshot(client, ipad_set_id, screenshot_path)

    review_warning = maybe_update_review_detail(client, state.version_id, env_defaults)
    if review_warning:
        warnings.append(review_warning)
    if build_warning:
        warnings.append(build_warning)

    print(f"Prepared iOS App Store version {state.version_string} for app {args.app_id}.")
    if build is not None:
        print(f"Attached build: {build['id']} (build number {build['attributes']['version']})")
    print(f"Uploaded iPhone screenshots: {len(iphone_paths)} to screenshot set {iphone_set_id}")
    print(f"Uploaded iPad screenshots: {len(ipad_paths)} to screenshot set {ipad_set_id}")
    for warning in warnings:
        print(warning)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
