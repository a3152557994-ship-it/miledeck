#!/usr/bin/env python3
"""Register MileDeck Bundle ID, create App Store Distribution profile, archive & export signed IPA.

Usage:
  python3 Scripts/asc_setup_and_build.py --provision-and-build
  python3 Scripts/asc_setup_and_build.py --check-app
"""
from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Optional

KEY_ID = "BD4GFRDCQ9"
ISSUER_ID = "ccf96e7a-0987-4f4b-aa61-863fccd82c33"
KEY_PATH = "/Users/wang/.appstoreconnect/private_keys/AuthKey_BD4GFRDCQ9.p8"
TEAM_ID = "KU364788TC"

APP_BUNDLE = "com.yanghe.miledeck"
APP_PROFILE_NAME = "MileDeck AppStore Dist"

ROOT = Path(__file__).resolve().parent.parent
DIST_DIR = ROOT / "dist"
ARCHIVE_PATH = DIST_DIR / "MileDeck.xcarchive"
IPA_DIR = DIST_DIR / "ipa"
IPA_PATH = IPA_DIR / "MileDeck.ipa"
PROFILES_DIR = Path.home() / "Library" / "Developer" / "Xcode" / "UserData" / "Provisioning Profiles"
LEGACY_PROFILES_DIR = Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles"


def b64u(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_jwt() -> str:
    header = b64u(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}, separators=(",", ":")).encode())
    now = int(time.time())
    payload = b64u(json.dumps({"iss": ISSUER_ID, "iat": now - 10, "exp": now + 900, "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
    msg = f"{header}.{payload}".encode()
    der = subprocess.check_output(["openssl", "dgst", "-sha256", "-sign", KEY_PATH], input=msg)
    idx = 2 + ((der[1] & 0x7F) if (der[1] & 0x80) else 0)
    rlen = der[idx + 1]
    r = der[idx + 2 : idx + 2 + rlen].lstrip(b"\x00").rjust(32, b"\x00")
    idx = idx + 2 + rlen
    slen = der[idx + 1]
    s = der[idx + 2 : idx + 2 + slen].lstrip(b"\x00").rjust(32, b"\x00")
    return f"{header}.{payload}.{b64u(r + s)}"


def asc(method: str, path: str, body: dict | None = None) -> tuple[int, Any]:
    token = make_jwt()
    data = json.dumps(body).encode() if body is not None else None
    url = path if path.startswith("http") else f"https://api.appstoreconnect.apple.com{path}"
    req = urllib.request.Request(url, data=data, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


def ensure_bundle_id(identifier: str, name: str) -> str:
    st, res = asc("GET", f"/v1/bundleIds?filter[identifier]={identifier}&limit=10")
    if st == 200 and isinstance(res, dict):
        for item in res.get("data", []):
            if item["attributes"]["identifier"] == identifier:
                print(f"  ✓ Bundle ID exists: {identifier} ({item['id']})")
                return item["id"]
    st, res = asc("POST", "/v1/bundleIds", {
        "data": {
            "type": "bundleIds",
            "attributes": {"identifier": identifier, "name": name, "platform": "IOS"},
        }
    })
    if st not in (200, 201):
        raise RuntimeError(f"Failed creating bundleId {identifier}: {st} {res}")
    bid = res["data"]["id"]
    print(f"  + Created Bundle ID: {identifier} ({bid})")
    return bid


def get_distribution_cert_id() -> str:
    st, res = asc("GET", "/v1/certificates?filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION&limit=20")
    if st != 200 or not isinstance(res, dict):
        raise RuntimeError(f"Failed listing certificates: {st} {res}")
    certs = res.get("data", [])
    if not certs:
        raise RuntimeError("No Apple Distribution certificate found in ASC!")
    certs.sort(key=lambda c: c["attributes"].get("expirationDate", ""), reverse=True)
    cid = certs[0]["id"]
    print(f"  ✓ Using Distribution Cert: {cid} ({certs[0]['attributes'].get('name')})")
    return cid


def ensure_appstore_profile(profile_name: str, bundle_id_resource: str, cert_id: str) -> tuple[str, str]:
    st, res = asc("GET", f"/v1/profiles?filter[name]={urllib.parse.quote(profile_name)}&limit=10")
    existing = None
    if st == 200 and isinstance(res, dict):
        for p in res.get("data", []):
            if p["attributes"]["name"] == profile_name and p["attributes"].get("profileState") == "ACTIVE":
                existing = p
                break
    if existing is None:
        st_c, res_c = asc("POST", "/v1/profiles", {
            "data": {
                "type": "profiles",
                "attributes": {"name": profile_name, "profileType": "IOS_APP_STORE"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_id_resource}},
                    "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
                },
            }
        })
        if st_c not in (200, 201):
            raise RuntimeError(f"Failed creating profile {profile_name}: {st_c} {res_c}")
        existing = res_c["data"]
        print(f"  + Created Profile: {profile_name}")
    else:
        print(f"  ✓ Profile exists: {profile_name}")

    uuid = existing["attributes"]["uuid"]
    raw_bytes = base64.b64decode(existing["attributes"]["profileContent"])
    legacy_dup = LEGACY_PROFILES_DIR / f"{uuid}.mobileprovision"
    if legacy_dup.exists():
        legacy_dup.unlink()
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    target_path = PROFILES_DIR / f"{uuid}.mobileprovision"
    target_path.write_bytes(raw_bytes)
    print(f"  ✓ Installed {target_path}")
    return uuid, existing["attributes"]["name"]


def archive_and_export() -> None:
    DIST_DIR.mkdir(parents=True, exist_ok=True)
    if ARCHIVE_PATH.exists():
        subprocess.run(["rm", "-rf", str(ARCHIVE_PATH)], check=True)
    if IPA_DIR.exists():
        subprocess.run(["rm", "-rf", str(IPA_DIR)], check=True)

    print("[1/2] Archiving Release build for iOS...")
    subprocess.run([
        "xcodebuild",
        "-project", str(ROOT / "MileDeck.xcodeproj"),
        "-scheme", "MileDeck",
        "-configuration", "Release",
        "-destination", "generic/platform=iOS",
        "-archivePath", str(ARCHIVE_PATH),
        "archive",
    ], check=True)

    export_plist = DIST_DIR / "ExportOptions.plist"
    export_plist.write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>teamID</key>
    <string>{TEAM_ID}</string>
    <key>uploadSymbols</key>
    <true/>
    <key>provisioningProfiles</key>
    <dict>
        <key>{APP_BUNDLE}</key>
        <string>{APP_PROFILE_NAME}</string>
    </dict>
</dict>
</plist>
""", encoding="utf-8")

    print("[2/2] Exporting official App Store signed IPA...")
    subprocess.run([
        "xcodebuild",
        "-exportArchive",
        "-archivePath", str(ARCHIVE_PATH),
        "-exportOptionsPlist", str(export_plist),
        "-exportPath", str(IPA_DIR),
    ], check=True)

    if IPA_PATH.exists():
        size_mb = IPA_PATH.stat().st_size / (1024 * 1024)
        print(f"✓ Exported signed IPA: {IPA_PATH} ({size_mb:.2f} MB)")
    else:
        raise RuntimeError(f"Expected IPA not found at {IPA_PATH}")


def find_app_id() -> Optional[str]:
    st, res = asc("GET", f"/v1/apps?filter[bundleId]={APP_BUNDLE}")
    if st == 200 and isinstance(res, dict) and res.get("data"):
        return res["data"][0]["id"]
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provision-and-build", action="store_true")
    parser.add_argument("--check-app", action="store_true")
    args = parser.parse_args()

    if args.provision_and_build:
        print("Registering Bundle ID & App Store Distribution Profile...")
        app_bid = ensure_bundle_id(APP_BUNDLE, "MileDeck Auto Mileage Log")
        cert_id = get_distribution_cert_id()
        ensure_appstore_profile(APP_PROFILE_NAME, app_bid, cert_id)
        archive_and_export()

    if args.check_app:
        app_id = find_app_id()
        if not app_id:
            print(f"! App shell for {APP_BUNDLE} not yet created in App Store Connect web portal.")
            return 2
        print(f"✓ Found ASC App ID: {app_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
