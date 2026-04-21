#!/usr/bin/env python3

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils


ROOT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_APP_ID = "6762634278"
DEFAULT_SUPPORT_URL = "https://souschefstudio.com/"
DEFAULT_MARKETING_URL = "https://souschefstudio.com/"
DEFAULT_PRIVACY_POLICY_URL = "https://souschefstudio.com/privacy"


def load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values

    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, raw_value = line.split("=", 1)
        key = key.strip()
        value = raw_value.strip()
        if value.startswith(("'", '"')) and value.endswith(("'", '"')) and len(value) >= 2:
            value = value[1:-1]
        values[key] = value
    return values


def env_value(name: str, defaults: dict[str, str], fallback: str | None = None) -> str | None:
    return os.environ.get(name) or defaults.get(name) or fallback


def base64url_json(payload: dict[str, Any]) -> bytes:
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=False).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=")


class AppStoreConnectClient:
    def __init__(self, key_id: str, issuer_id: str, key_path: Path):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.key_path = key_path
        self.private_key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
        self.session = requests.Session()

    def _token(self) -> str:
        now = int(time.time())
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload = {"iss": self.issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
        signing_input = b".".join([base64url_json(header), base64url_json(payload)])
        der_signature = self.private_key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
        r_value, s_value = utils.decode_dss_signature(der_signature)
        jose_signature = r_value.to_bytes(32, "big") + s_value.to_bytes(32, "big")
        return b".".join(
            [signing_input, base64.urlsafe_b64encode(jose_signature).rstrip(b"=")]
        ).decode()

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        payload: dict[str, Any] | None = None,
        expected: tuple[int, ...] = (200,),
        absolute_url: str | None = None,
        headers: dict[str, str] | None = None,
        data: bytes | None = None,
    ) -> dict[str, Any] | None:
        url = absolute_url or f"https://api.appstoreconnect.apple.com/v1/{path.lstrip('/')}"
        request_headers = {"Authorization": f"Bearer {self._token()}"}
        if payload is not None:
            request_headers["Content-Type"] = "application/json"
        if headers:
            request_headers.update(headers)

        response = self.session.request(
            method=method,
            url=url,
            params=params,
            json=payload,
            data=data,
            headers=request_headers,
            timeout=60,
        )

        if response.status_code not in expected:
            raise RuntimeError(f"{method} {url} failed with {response.status_code}: {response.text}")

        if not response.content:
            return None
        return response.json()


@dataclass
class MacSubmissionState:
    version_id: str
    version_string: str
    version_localization_id: str
    app_info_id: str
    app_info_localization_id: str
    age_rating_declaration_id: str
    screenshot_set_id: str | None
    attached_build_id: str | None


AGE_RATING_FALSE_FIELDS = [
    "advertising",
    "ageAssurance",
    "gambling",
    "healthOrWellnessTopics",
    "lootBox",
    "messagingAndChat",
    "parentalControls",
    "unrestrictedWebAccess",
    "userGeneratedContent",
]

AGE_RATING_NONE_FIELDS = [
    "alcoholTobaccoOrDrugUseOrReferences",
    "contests",
    "gamblingSimulated",
    "gunsOrOtherWeapons",
    "horrorOrFearThemes",
    "matureOrSuggestiveThemes",
    "medicalOrTreatmentInformation",
    "profanityOrCrudeHumor",
    "sexualContentGraphicAndNudity",
    "sexualContentOrNudity",
    "violenceCartoonOrFantasy",
    "violenceRealistic",
    "violenceRealisticProlongedGraphicOrSadistic",
]


def resolve_state(client: AppStoreConnectClient, app_id: str) -> MacSubmissionState:
    versions = client.request(
        "GET",
        f"apps/{app_id}/appStoreVersions",
        params={"limit": 50, "include": "appStoreVersionLocalizations,build"},
    )
    version_data = next(
        item for item in versions["data"] if item["attributes"]["platform"] == "MAC_OS"
    )
    version_localization_id = version_data["relationships"]["appStoreVersionLocalizations"]["data"][0]["id"]
    attached_build_id = None
    build_data = version_data["relationships"]["build"]["data"]
    if build_data is not None:
        attached_build_id = build_data["id"]

    app_infos = client.request("GET", f"apps/{app_id}/appInfos", params={"include": "appInfoLocalizations"})
    app_info = app_infos["data"][0]
    app_info_localization_id = app_info["relationships"]["appInfoLocalizations"]["data"][0]["id"]

    screenshot_sets = client.request(
        "GET",
        f"appStoreVersionLocalizations/{version_localization_id}/appScreenshotSets",
    )
    screenshot_set_id = None
    for item in screenshot_sets["data"]:
        if item["attributes"]["screenshotDisplayType"] == "APP_DESKTOP":
            screenshot_set_id = item["id"]
            break

    return MacSubmissionState(
        version_id=version_data["id"],
        version_string=version_data["attributes"]["versionString"],
        version_localization_id=version_localization_id,
        app_info_id=app_info["id"],
        app_info_localization_id=app_info_localization_id,
        age_rating_declaration_id=app_info["id"],
        screenshot_set_id=screenshot_set_id,
        attached_build_id=attached_build_id,
    )


def latest_matching_build(client: AppStoreConnectClient, app_id: str, version_string: str) -> dict[str, Any]:
    builds = client.request(
        "GET",
        "builds",
        params={
            "filter[app]": app_id,
            "filter[preReleaseVersion.platform]": "MAC_OS",
            "include": "preReleaseVersion",
            "sort": "-uploadedDate",
            "limit": 50,
        },
    )

    prerelease_versions = {item["id"]: item for item in builds.get("included", []) if item["type"] == "preReleaseVersions"}
    for build in builds["data"]:
        relationships = build.get("relationships", {})
        prerelease_data = relationships.get("preReleaseVersion", {}).get("data")
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
        f"No valid macOS build found for App Store version {version_string}. Upload a build whose short version matches."
    )


def ensure_primary_category(client: AppStoreConnectClient, app_info_id: str) -> str | None:
    try:
        client.request(
            "PATCH",
            f"appInfos/{app_info_id}",
            payload={
                "data": {
                    "type": "appInfos",
                    "id": app_info_id,
                    "relationships": {
                        "primaryCategory": {
                            "data": {
                                "type": "appCategories",
                                "id": "PRODUCTIVITY",
                            }
                        }
                    },
                }
            },
            expected=(200,),
        )
        return None
    except RuntimeError as exc:
        return f"Primary category still needs manual setup in App Store Connect ({exc})."


def ensure_age_rating(client: AppStoreConnectClient, age_rating_declaration_id: str) -> None:
    attributes = {field: False for field in AGE_RATING_FALSE_FIELDS}
    attributes.update({field: "NONE" for field in AGE_RATING_NONE_FIELDS})
    attributes["ageRatingOverrideV2"] = "NONE"
    attributes["koreaAgeRatingOverride"] = "NONE"

    client.request(
        "PATCH",
        f"ageRatingDeclarations/{age_rating_declaration_id}",
        payload={
            "data": {
                "type": "ageRatingDeclarations",
                "id": age_rating_declaration_id,
                "attributes": attributes,
            }
        },
        expected=(200,),
    )


def update_localizations(
    client: AppStoreConnectClient,
    state: MacSubmissionState,
    support_url: str,
    marketing_url: str,
    privacy_policy_url: str,
) -> None:
    client.request(
        "PATCH",
        f"appStoreVersionLocalizations/{state.version_localization_id}",
        payload={
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": state.version_localization_id,
                "attributes": {
                    "supportUrl": support_url,
                    "marketingUrl": marketing_url,
                },
            }
        },
        expected=(200,),
    )

    client.request(
        "PATCH",
        f"appInfoLocalizations/{state.app_info_localization_id}",
        payload={
            "data": {
                "type": "appInfoLocalizations",
                "id": state.app_info_localization_id,
                "attributes": {
                    "privacyPolicyUrl": privacy_policy_url,
                },
            }
        },
        expected=(200,),
    )


def attach_build(client: AppStoreConnectClient, version_id: str, build_id: str) -> None:
    client.request(
        "PATCH",
        f"appStoreVersions/{version_id}/relationships/build",
        payload={"data": {"type": "builds", "id": build_id}},
        expected=(200, 204),
    )


def ensure_screenshot_set(client: AppStoreConnectClient, state: MacSubmissionState) -> str:
    if state.screenshot_set_id is not None:
        return state.screenshot_set_id

    created = client.request(
        "POST",
        "appScreenshotSets",
        payload={
            "data": {
                "type": "appScreenshotSets",
                "attributes": {
                    "screenshotDisplayType": "APP_DESKTOP",
                },
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "id": state.version_localization_id,
                        }
                    }
                },
            }
        },
        expected=(201,),
    )
    return created["data"]["id"]


def clear_existing_screenshots(client: AppStoreConnectClient, screenshot_set_id: str) -> None:
    screenshots = client.request("GET", f"appScreenshotSets/{screenshot_set_id}/appScreenshots")
    for screenshot in screenshots["data"]:
        client.request("DELETE", f"appScreenshots/{screenshot['id']}", expected=(204,))


def upload_screenshot(client: AppStoreConnectClient, screenshot_set_id: str, image_path: Path) -> None:
    file_bytes = image_path.read_bytes()
    checksum = hashlib.md5(file_bytes).hexdigest()

    created = client.request(
        "POST",
        "appScreenshots",
        payload={
            "data": {
                "type": "appScreenshots",
                "attributes": {
                    "fileName": image_path.name,
                    "fileSize": len(file_bytes),
                },
                "relationships": {
                    "appScreenshotSet": {
                        "data": {
                            "type": "appScreenshotSets",
                            "id": screenshot_set_id,
                        }
                    }
                },
            }
        },
        expected=(201,),
    )

    screenshot_id = created["data"]["id"]
    upload_operations = created["data"]["attributes"]["uploadOperations"]
    for operation in upload_operations:
        method = operation["method"]
        url = operation["url"]
        headers = {header["name"]: header["value"] for header in operation.get("requestHeaders", [])}
        response = requests.request(method, url, headers=headers, data=file_bytes, timeout=120)
        if response.status_code not in (200, 201):
            raise RuntimeError(f"{method} {url} failed with {response.status_code}: {response.text}")

    client.request(
        "PATCH",
        f"appScreenshots/{screenshot_id}",
        payload={
            "data": {
                "type": "appScreenshots",
                "id": screenshot_id,
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": checksum,
                },
            }
        },
        expected=(200,),
    )


def maybe_update_review_detail(client: AppStoreConnectClient, version_id: str, env_defaults: dict[str, str]) -> str | None:
    first_name = env_value("APPSTORE_REVIEW_CONTACT_FIRST_NAME", env_defaults)
    last_name = env_value("APPSTORE_REVIEW_CONTACT_LAST_NAME", env_defaults)
    email = env_value("APPSTORE_REVIEW_CONTACT_EMAIL", env_defaults)
    phone = env_value("APPSTORE_REVIEW_CONTACT_PHONE", env_defaults)

    if not all([first_name, last_name, email, phone]):
        return "Review contact details are still missing (`APPSTORE_REVIEW_CONTACT_FIRST_NAME`, `APPSTORE_REVIEW_CONTACT_LAST_NAME`, `APPSTORE_REVIEW_CONTACT_EMAIL`, `APPSTORE_REVIEW_CONTACT_PHONE`)."

    existing = client.request("GET", f"appStoreVersions/{version_id}/appStoreReviewDetail")
    payload = {
        "contactFirstName": first_name,
        "contactLastName": last_name,
        "contactEmail": email,
        "contactPhone": phone,
        "demoAccountRequired": False,
        "notes": "Calendar Busy Sync is a calendar mirroring utility. Reviewers can navigate the Settings and Logs windows without signing in. Google account connection uses standard OAuth, and Apple Calendar access uses the system permission prompt.",
    }

    if existing["data"] is None:
        client.request(
            "POST",
            "appStoreReviewDetails",
            payload={
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": payload,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {
                                "type": "appStoreVersions",
                                "id": version_id,
                            }
                        }
                    },
                }
            },
            expected=(201,),
        )
    else:
        client.request(
            "PATCH",
            f"appStoreReviewDetails/{existing['data']['id']}",
            payload={
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": existing["data"]["id"],
                    "attributes": payload,
                }
            },
            expected=(200,),
        )

    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare the macOS App Store submission state for Calendar Busy Sync.")
    parser.add_argument("--app-id", default=DEFAULT_APP_ID)
    parser.add_argument("--screenshot-dir", type=Path, required=True)
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

    screenshot_paths = sorted(path for path in args.screenshot_dir.glob("*.png"))
    if not screenshot_paths:
        raise RuntimeError(f"No PNG screenshots found in {args.screenshot_dir}")

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

    screenshot_set_id = ensure_screenshot_set(client, state)
    clear_existing_screenshots(client, screenshot_set_id)
    for screenshot_path in screenshot_paths:
        upload_screenshot(client, screenshot_set_id, screenshot_path)

    review_detail_warning = maybe_update_review_detail(client, state.version_id, env_defaults)

    print(f"Prepared macOS App Store version {state.version_string} for app {args.app_id}.")
    if build is not None:
        print(f"Attached build: {build['id']} (build number {build['attributes']['version']})")
    if build_warning:
        print(build_warning)
    print(f"Uploaded screenshots: {len(screenshot_paths)} to screenshot set {screenshot_set_id}")
    if review_detail_warning:
        print(review_detail_warning)
    for warning in warnings:
        print(warning)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # Explicit top-level failure surface for release automation.
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
