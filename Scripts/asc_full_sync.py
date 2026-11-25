#!/usr/bin/env python3
"""Complete end-to-end App Store Connect sync, IAP/Subscription setup & review submission for MileDeck (com.yanghe.miledeck)."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Optional

KEY_ID = "BD4GFRDCQ9"
ISSUER_ID = "ccf96e7a-0987-4f4b-aa61-863fccd82c33"
KEY_PATH = "/Users/wang/.appstoreconnect/private_keys/AuthKey_BD4GFRDCQ9.p8"
BUNDLE_ID = "com.yanghe.miledeck"

ROOT = Path(__file__).resolve().parent.parent
META_PATH = ROOT / "release" / "ASC_METADATA_READY.json"
IPA_PATH = ROOT / "dist" / "ipa" / "MileDeck.ipa"
SHOT_ROOT = Path("/Users/wang/OPC/media/20261125-miledeck/appstore")


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


def get_all_territories() -> list[str]:
    st, res = asc("GET", "/v1/territories?limit=200")
    if st == 200 and isinstance(res, dict):
        return [t["id"] for t in res.get("data", [])]
    return ["USA", "CHN"]


def find_price_point(endpoint: str, target: float) -> Optional[str]:
    next_url: Optional[str] = endpoint
    best_id, best_diff = None, 99999.0
    for _ in range(8):
        if not next_url:
            break
        st, res = asc("GET", next_url)
        if st != 200 or not isinstance(res, dict):
            break
        for pp in res.get("data", []):
            p = pp.get("attributes", {}).get("customerPrice")
            if p is None:
                continue
            try:
                diff = abs(float(p) - target)
            except ValueError:
                continue
            if diff < best_diff:
                best_diff, best_id = diff, pp["id"]
                if diff <= 0.01:
                    return best_id
        next_url = res.get("links", {}).get("next")
    return best_id


def upload_binary_asset(reserve_ep: str, commit_ep: str, rtype: str, rel_key: str, rel_type: str, rel_id: str, png: Path) -> None:
    raw = png.read_bytes()
    md5 = hashlib.md5(raw).hexdigest()
    st, res = asc("POST", reserve_ep, {
        "data": {
            "type": rtype,
            "attributes": {"fileSize": len(raw), "fileName": png.name},
            "relationships": {rel_key: {"data": {"type": rel_type, "id": rel_id}}},
        }
    })
    if st not in (200, 201):
        print(f"    ! Reserve {png.name} failed ({st}): {res}")
        return
    asset_id = res["data"]["id"]
    for op in res["data"]["attributes"].get("uploadOperations", []):
        chunk = raw[op["offset"] : op["offset"] + op["length"]]
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        req = urllib.request.Request(op["url"], data=chunk, headers=headers, method=op["method"])
        with urllib.request.urlopen(req, timeout=60):
            pass
    st2, res2 = asc("PATCH", f"{commit_ep}/{asset_id}", {
        "data": {"type": rtype, "id": asset_id, "attributes": {"uploaded": True, "sourceFileChecksum": md5}}
    })
    if st2 in (200, 204):
        print(f"    ✓ Uploaded {png.name}")
    else:
        print(f"    ! Commit {png.name} failed ({st2}): {res2}")


def sync_shots(vloc_id: str, display_type: str, folder: Path) -> None:
    pngs = sorted(folder.glob("*.png"))
    if not pngs:
        return
    _, sets = asc("GET", f"/v1/appStoreVersionLocalizations/{vloc_id}/appScreenshotSets?limit=20")
    set_id = None
    for s in sets.get("data", []) if isinstance(sets, dict) else []:
        if s["attributes"]["screenshotDisplayType"] == display_type:
            set_id = s["id"]
            _, existing = asc("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=20")
            for item in existing.get("data", []):
                asc("DELETE", f"/v1/appScreenshots/{item['id']}")
            break
    if not set_id:
        st, cset = asc("POST", "/v1/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": vloc_id}}},
            }
        })
        if st in (200, 201):
            set_id = cset["data"]["id"]
    if set_id:
        for png in pngs:
            upload_binary_asset("/v1/appScreenshots", "/v1/appScreenshots", "appScreenshots", "appScreenshotSet", "appScreenshotSets", set_id, png)


def sync_core_metadata(app_id: str, meta: dict[str, Any], territories: list[str], do_shots: bool) -> str:
    print("[1/5] Syncing Rights, Categories & Age Rating (4+)...")
    asc("PATCH", f"/v1/apps/{app_id}", {
        "data": {
            "type": "apps", "id": app_id,
            "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT", "primaryLocale": "en-US"},
        }
    })
    _, infos = asc("GET", f"/v1/apps/{app_id}/appInfos")
    info_id = infos["data"][0]["id"]
    st_cat, _ = asc("PATCH", f"/v1/appInfos/{info_id}", {
        "data": {
            "type": "appInfos", "id": info_id,
            "relationships": {
                "primaryCategory": {"data": {"type": "appCategories", "id": meta["primaryCategory"]}},
                "secondaryCategory": {"data": {"type": "appCategories", "id": meta["secondaryCategory"]}},
            },
        }
    })
    print(f"  ✓ Categories ({meta['primaryCategory']} / {meta['secondaryCategory']}) -> {st_cat}")

    _, age_res = asc("GET", f"/v1/appInfos/{info_id}/ageRatingDeclaration")
    if isinstance(age_res, dict) and age_res.get("data"):
        age_id = age_res["data"]["id"]
        st_age, _ = asc("PATCH", f"/v1/ageRatingDeclarations/{age_id}", {
            "data": {
                "type": "ageRatingDeclarations", "id": age_id,
                "attributes": {
                    "advertising": False,
                    "alcoholTobaccoOrDrugUseOrReferences": "NONE",
                    "contests": "NONE",
                    "gambling": False,
                    "gamblingSimulated": "NONE",
                    "gunsOrOtherWeapons": "NONE",
                    "healthOrWellnessTopics": False,
                    "kidsAgeBand": None,
                    "lootBox": False,
                    "medicalOrTreatmentInformation": "NONE",
                    "messagingAndChat": False,
                    "parentalControls": False,
                    "profanityOrCrudeHumor": "NONE",
                    "ageAssurance": False,
                    "sexualContentGraphicAndNudity": "NONE",
                    "sexualContentOrNudity": "NONE",
                    "socialMedia": False,
                    "socialMediaAgeRestricted": False,
                    "horrorOrFearThemes": "NONE",
                    "matureOrSuggestiveThemes": "NONE",
                    "unrestrictedWebAccess": False,
                    "userGeneratedContent": False,
                    "violenceCartoonOrFantasy": "NONE",
                    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
                    "violenceRealistic": "NONE",
                },
            }
        })
        print(f"  ✓ Age rating (4+) -> {st_age}")

    print("[2/5] Setting Global Availability & Free Base Price...")
    st_av, _ = asc("GET", f"/v2/appAvailabilities/{app_id}")
    if st_av == 404:
        st_p, _ = asc("POST", "/v2/appAvailabilities", {
            "data": {
                "type": "appAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                    "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": f"${{ta-{t}}}"} for t in territories]},
                },
            },
            "included": [
                {
                    "type": "territoryAvailabilities",
                    "id": f"${{ta-{t}}}",
                    "attributes": {"available": True, "releaseDate": None, "preOrderEnabled": False},
                    "relationships": {"territory": {"data": {"type": "territories", "id": t}}},
                }
                for t in territories
            ],
        })
        print(f"  ✓ Availability ({len(territories)} territories) -> {st_p}")

    usa_pp = find_price_point(f"/v1/apps/{app_id}/appPricePoints?filter[territory]=USA&limit=50", 0.0)
    chn_pp = find_price_point(f"/v1/apps/{app_id}/appPricePoints?filter[territory]=CHN&limit=50", 0.0)
    if usa_pp:
        mrefs = [{"type": "appPrices", "id": "${p-usa}"}]
        incs = [{"type": "appPrices", "id": "${p-usa}", "attributes": {"startDate": None}, "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": usa_pp}}}}]
        if chn_pp:
            mrefs.append({"type": "appPrices", "id": "${p-chn}"})
            incs.append({"type": "appPrices", "id": "${p-chn}", "attributes": {"startDate": None}, "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": chn_pp}}}})
        st_ps, _ = asc("POST", "/v1/appPriceSchedules", {
            "data": {
                "type": "appPriceSchedules",
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": mrefs},
                },
            },
            "included": incs,
        })
        print(f"  ✓ Base Price FREE -> {st_ps}")

    print("[3/5] Syncing EN + CN Metadata, Screenshots & Review Info...")
    _, vers = asc("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS")
    ver_id = vers["data"][0]["id"]
    asc("PATCH", f"/v1/appStoreVersions/{ver_id}", {
        "data": {"type": "appStoreVersions", "id": ver_id, "attributes": {"versionString": "1.0.0", "copyright": meta["copyright"], "releaseType": "AFTER_APPROVAL"}}
    })

    _, info_locs = asc("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations?limit=50")
    imap = {x["attributes"]["locale"]: x["id"] for x in info_locs.get("data", [])}
    _, ver_locs = asc("GET", f"/v1/appStoreVersions/{ver_id}/appStoreVersionLocalizations?limit=50")
    vmap = {x["attributes"]["locale"]: x["id"] for x in ver_locs.get("data", [])}

    for loc, data in meta["localizations"].items():
        iattrs = {"name": data["name"], "subtitle": data["subtitle"], "privacyPolicyUrl": meta["urls"]["privacy"]}
        if loc in imap:
            asc("PATCH", f"/v1/appInfoLocalizations/{imap[loc]}", {"data": {"type": "appInfoLocalizations", "id": imap[loc], "attributes": iattrs}})
        else:
            asc("POST", "/v1/appInfoLocalizations", {"data": {"type": "appInfoLocalizations", "attributes": {"locale": loc, **iattrs}, "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info_id}}}}})

        vattrs = {
            "description": data["description"],
            "keywords": data["keywords"],
            "promotionalText": data["promotionalText"],
            "supportUrl": meta["urls"]["support"],
            "marketingUrl": meta["urls"]["marketing"],
        }
        if loc in vmap:
            vloc_id = vmap[loc]
            st_vl, res_vl = asc("PATCH", f"/v1/appStoreVersionLocalizations/{vloc_id}", {"data": {"type": "appStoreVersionLocalizations", "id": vloc_id, "attributes": vattrs}})
            if st_vl not in (200, 204):
                print(f"  ! PATCH vloc {loc} failed ({st_vl}): {res_vl}")
        else:
            st_vl, c = asc("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations", "attributes": {"locale": loc, **vattrs}, "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}}}}})
            vloc_id = c["data"]["id"] if st_vl in (200, 201) and isinstance(c, dict) and "data" in c else None
        print(f"  ✓ Localization {loc} synced")
        if do_shots and vloc_id:
            sync_shots(vloc_id, "APP_IPHONE_65", SHOT_ROOT / loc / "iphone65")
            sync_shots(vloc_id, "APP_IPAD_PRO_3GEN_129", SHOT_ROOT / loc / "ipad13")

    review_notes = (
        "MileDeck is a 100% offline, native SwiftUI + CoreLocation + CoreMotion + PDFKit automatic mileage and 2026 IRS tax deduction tracker (zero login required, zero cloud servers, zero ad SDKs).\n\n"
        "Quick Review Guide:\n"
        "1. Drives Tab & Swipe Deck: Launches with 6 realistic 2026 starter drives (3 unclassified ready to swipe right for Business or left for Personal, plus 3 classified drives spanning both official 2026 IRS split periods: Jan–Jun $0.725/mi and Jul–Dec $0.76/mi). Tap 'Open Deck' to test card-swipe classification with Undo, or tap 'Start Live Drive' (includes '+2.4 mi Test' button for easy indoor/Simulator verification) and 'Stop & Log Drive'.\n"
        "2. Background Location Justification: UIBackgroundModes=location is requested strictly when the user enables Automatic Drive Detection so hands-free business trips are captured accurately with zero cloud upload.\n"
        "3. Reports & Vehicles Tabs: View the interactive 2026 month-by-month deduction breakdown, embedded live vector PDFKit IRS Schedule C Logbook, 1-tap Share PDF / CSV exports, and multi-vehicle odometer tracking.\n"
        "4. StoreKit 2 In-App Purchases & Subscriptions: Tap the top-left 'Lifetime $14.99' pill or Settings > Upgrade to inspect PaywallView — includes Lifetime Pro ($14.99 one-time), Annual Pro ($9.99/yr with 3-day free trial), Monthly Pro ($1.99/mo), non-hostile free tier exit (20 classified/exported drives/month), working Restore Purchases, Privacy Policy & Terms of Use (EULA) links."
    )
    rattrs = {
        "contactFirstName": "Yang",
        "contactLastName": "He",
        "contactPhone": "+86 196 3394 8182",
        "contactEmail": "a3152557994@gmail.com",
        "demoAccountRequired": False,
        "notes": review_notes,
    }
    st_r, res_r = asc("GET", f"/v1/appStoreVersions/{ver_id}/appStoreReviewDetail")
    if st_r == 200 and isinstance(res_r, dict) and res_r.get("data"):
        rd_id = res_r["data"]["id"]
        asc("PATCH", f"/v1/appStoreReviewDetails/{rd_id}", {"data": {"type": "appStoreReviewDetails", "id": rd_id, "attributes": rattrs}})
    else:
        asc("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": rattrs, "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}}}}})
    print("  ✓ App Review Details saved")
    return ver_id


def sync_all_iaps(app_id: str, territories: list[str]) -> tuple[Optional[str], Optional[str], list[str]]:
    print("[4/5] Syncing Lifetime IAP ($14.99/¥48) & Yearly ($9.99/¥28 + 3d trial) + Monthly ($1.99/¥8) Subscriptions...")
    review_shot = SHOT_ROOT / "en-US" / "iphone65" / "05_paywall.png"

    # A. Non-Consumable Lifetime ($14.99 / ¥48)
    _, iap_list = asc("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50")
    emap = {x["attributes"]["productId"]: x["id"] for x in iap_list.get("data", []) if isinstance(iap_list, dict)}
    life_pid = "com.yanghe.miledeck.pro.lifetime"
    life_id = emap.get(life_pid)
    if not life_id:
        st, created = asc("POST", "/v2/inAppPurchases", {
            "data": {
                "type": "inAppPurchases",
                "attributes": {
                    "name": "MileDeck Pro Lifetime",
                    "productId": life_pid,
                    "inAppPurchaseType": "NON_CONSUMABLE",
                    "familySharable": True,
                    "reviewNote": "Presented inside PaywallView when tapping Lifetime pill, Settings > Upgrade, or exceeding 20 free monthly classified/exported drives.",
                },
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        if st not in (200, 201):
            print("  ! Failed creating lifetime IAP:", st, created)
        else:
            life_id = created["data"]["id"]
            print(f"  + Created Lifetime IAP ({life_id})")

    if life_id:
        _, cur_l = asc("GET", f"/v2/inAppPurchases/{life_id}/inAppPurchaseLocalizations")
        ex_l = {x["attributes"]["locale"]: x["id"] for x in cur_l.get("data", [])}
        for loc, attrs in {
            "en-US": {"name": "MileDeck Pro Lifetime", "description": "Pay once to unlock unlimited drive classifications, IRS PDF logbooks & CSV exports forever."},
            "zh-Hans": {"name": "MileDeck 永久买断版", "description": "一次买断终身解锁无限里程分类、IRS 报税 PDF 日志与 CSV 表格导出。"},
        }.items():
            if loc in ex_l:
                asc("PATCH", f"/v1/inAppPurchaseLocalizations/{ex_l[loc]}", {"data": {"type": "inAppPurchaseLocalizations", "id": ex_l[loc], "attributes": attrs}})
            else:
                asc("POST", "/v1/inAppPurchaseLocalizations", {"data": {"type": "inAppPurchaseLocalizations", "attributes": {"locale": loc, **attrs}, "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": life_id}}}}})

        st_ia, _ = asc("GET", f"/v2/inAppPurchases/{life_id}/inAppPurchaseAvailability")
        if st_ia == 404:
            asc("POST", "/v1/inAppPurchaseAvailabilities", {
                "data": {
                    "type": "inAppPurchaseAvailabilities",
                    "attributes": {"availableInNewTerritories": True},
                    "relationships": {
                        "inAppPurchase": {"data": {"type": "inAppPurchases", "id": life_id}},
                        "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]},
                    },
                }
            })

        usa_pp = find_price_point(f"/v2/inAppPurchases/{life_id}/pricePoints?filter[territory]=USA&limit=200", 14.99)
        chn_pp = find_price_point(f"/v2/inAppPurchases/{life_id}/pricePoints?filter[territory]=CHN&limit=200", 48.0)
        if usa_pp:
            mrefs = [{"type": "inAppPurchasePrices", "id": "${lp-usa}"}]
            incs = [{"type": "inAppPurchasePrices", "id": "${lp-usa}", "attributes": {"startDate": None}, "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": life_id}}, "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": usa_pp}}}}]
            if chn_pp:
                mrefs.append({"type": "inAppPurchasePrices", "id": "${lp-chn}"})
                incs.append({"type": "inAppPurchasePrices", "id": "${lp-chn}", "attributes": {"startDate": None}, "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": life_id}}, "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": chn_pp}}}})
            st_ip, _ = asc("POST", "/v1/inAppPurchasePriceSchedules", {
                "data": {"type": "inAppPurchasePriceSchedules", "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": life_id}}, "baseTerritory": {"data": {"type": "territories", "id": "USA"}}, "manualPrices": {"data": mrefs}}},
                "included": incs,
            })
            print(f"  ✓ Lifetime price ($14.99 / ¥48) -> {st_ip}")

        st_is, res_is = asc("GET", f"/v2/inAppPurchases/{life_id}/appStoreReviewScreenshot")
        if (st_is == 404 or not (isinstance(res_is, dict) and res_is.get("data"))) and review_shot.exists():
            upload_binary_asset("/v1/inAppPurchaseAppStoreReviewScreenshots", "/v1/inAppPurchaseAppStoreReviewScreenshots", "inAppPurchaseAppStoreReviewScreenshots", "inAppPurchaseV2", "inAppPurchases", life_id, review_shot)

    # B. Subscription Group + Yearly ($9.99 / ¥28 + 3-Day Free Trial) + Monthly ($1.99 / ¥8)
    _, sgs = asc("GET", f"/v1/apps/{app_id}/subscriptionGroups")
    if sgs.get("data"):
        sg_id = sgs["data"][0]["id"]
    else:
        st_sg, res_sg = asc("POST", "/v1/subscriptionGroups", {
            "data": {"type": "subscriptionGroups", "attributes": {"referenceName": "MileDeck Pro"}, "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}
        })
        sg_id = res_sg["data"]["id"]
        print(f"  + Created Subscription Group ({sg_id}) -> {st_sg}")

    _, cur_sgl = asc("GET", f"/v1/subscriptionGroups/{sg_id}/subscriptionGroupLocalizations")
    ex_sgl = {x["attributes"]["locale"]: x["id"] for x in cur_sgl.get("data", [])}
    for loc, attrs in {
        "en-US": {"name": "MileDeck Pro", "customAppName": "MileDeck"},
        "zh-Hans": {"name": "MileDeck Pro 会员", "customAppName": "MileDeck里程"},
    }.items():
        if loc not in ex_sgl:
            asc("POST", "/v1/subscriptionGroupLocalizations", {
                "data": {"type": "subscriptionGroupLocalizations", "attributes": {"locale": loc, **attrs}, "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": sg_id}}}}
            })

    _, subs_res = asc("GET", f"/v1/subscriptionGroups/{sg_id}/subscriptions")
    sub_map = {x["attributes"]["productId"]: x["id"] for x in subs_res.get("data", [])}

    sub_specs = [
        {
            "pid": "com.yanghe.miledeck.pro.yearly",
            "ref": "MileDeck Pro Annual",
            "period": "ONE_YEAR",
            "groupLevel": 1,
            "usaPrice": 9.99,
            "chnPrice": 28.0,
            "trial3d": True,
            "locs": {
                "en-US": {"name": "MileDeck Pro Annual", "description": "3-day free trial, then annual unlimited drive classifications, IRS PDF logbooks & CSV exports."},
                "zh-Hans": {"name": "MileDeck Pro 年度版", "description": "含3天免费试用，全年无限里程分类、IRS 报税 PDF 日志与 CSV 导出。"},
            },
        },
        {
            "pid": "com.yanghe.miledeck.pro.monthly",
            "ref": "MileDeck Pro Monthly",
            "period": "ONE_MONTH",
            "groupLevel": 2,
            "usaPrice": 1.99,
            "chnPrice": 8.0,
            "trial3d": False,
            "locs": {
                "en-US": {"name": "MileDeck Pro Monthly", "description": "Monthly unlimited drive classifications, IRS Schedule C PDF logbooks & CSV exports."},
                "zh-Hans": {"name": "MileDeck Pro 月度版", "description": "按月解锁无限里程分类、IRS 报税 PDF 日志与 CSV 导出。"},
            },
        },
    ]

    sub_ids: list[str] = []
    for spec in sub_specs:
        sid = sub_map.get(spec["pid"])
        if not sid:
            st_s, res_s = asc("POST", "/v1/subscriptions", {
                "data": {
                    "type": "subscriptions",
                    "attributes": {
                        "name": spec["ref"],
                        "productId": spec["pid"],
                        "subscriptionPeriod": spec["period"],
                        "groupLevel": spec["groupLevel"],
                        "familySharable": True,
                        "reviewNote": "Presented inside PaywallView with clear price, duration, Restore Purchases, Privacy Policy & Terms of Use (EULA).",
                    },
                    "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": sg_id}}},
                }
            })
            if st_s not in (200, 201):
                print(f"  ! Failed creating sub {spec['pid']}: {st_s} {res_s}")
                continue
            sid = res_s["data"]["id"]
            print(f"  + Created Subscription {spec['pid']} ({sid})")
        sub_ids.append(sid)

        _, cur_sl = asc("GET", f"/v1/subscriptions/{sid}/subscriptionLocalizations")
        ex_sl = {x["attributes"]["locale"]: x["id"] for x in cur_sl.get("data", [])}
        for loc, attrs in spec["locs"].items():
            if loc in ex_sl:
                asc("PATCH", f"/v1/subscriptionLocalizations/{ex_sl[loc]}", {"data": {"type": "subscriptionLocalizations", "id": ex_sl[loc], "attributes": attrs}})
            else:
                asc("POST", "/v1/subscriptionLocalizations", {"data": {"type": "subscriptionLocalizations", "attributes": {"locale": loc, **attrs}, "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}}}})

        st_sa, _ = asc("GET", f"/v1/subscriptions/{sid}/subscriptionAvailability")
        if st_sa == 404:
            asc("POST", "/v1/subscriptionAvailabilities", {
                "data": {
                    "type": "subscriptionAvailabilities",
                    "attributes": {"availableInNewTerritories": True},
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": sid}},
                        "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]},
                    },
                }
            })

        _, cur_sp = asc("GET", f"/v1/subscriptions/{sid}/prices?limit=200")
        if len(cur_sp.get("data", []) if isinstance(cur_sp, dict) else []) < 5:
            usa_sp = find_price_point(f"/v1/subscriptions/{sid}/pricePoints?filter[territory]=USA&limit=200", spec["usaPrice"])
            chn_sp = find_price_point(f"/v1/subscriptions/{sid}/pricePoints?filter[territory]=CHN&limit=200", spec["chnPrice"])
            if usa_sp:
                eq_url: Optional[str] = f"/v1/subscriptionPricePoints/{usa_sp}/equalizations?limit=200&include=territory"
                ter_pp: dict[str, str] = {"USA": usa_sp}
                while eq_url:
                    st_eq, eq_res = asc("GET", eq_url)
                    if st_eq != 200 or not isinstance(eq_res, dict):
                        break
                    for item in eq_res.get("data", []):
                        tid = item.get("relationships", {}).get("territory", {}).get("data", {}).get("id")
                        if tid:
                            ter_pp[tid] = item["id"]
                    eq_url = eq_res.get("links", {}).get("next")
                if chn_sp:
                    ter_pp["CHN"] = chn_sp
                ok_cnt = 0
                for _, pp_id in ter_pp.items():
                    st_p, _ = asc("POST", "/v1/subscriptionPrices", {
                        "data": {
                            "type": "subscriptionPrices",
                            "attributes": {"preserveCurrentPrice": False, "startDate": None},
                            "relationships": {
                                "subscription": {"data": {"type": "subscriptions", "id": sid}},
                                "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pp_id}},
                            },
                        }
                    })
                    if st_p in (200, 201):
                        ok_cnt += 1
                print(f"  ✓ Set {ok_cnt}/{len(ter_pp)} territory prices for {spec['pid']}")

        if spec["trial3d"]:
            _, cur_io = asc("GET", f"/v1/subscriptions/{sid}/introductoryOffers?limit=200")
            if len(cur_io.get("data", []) if isinstance(cur_io, dict) else []) < 5:
                ok_t = 0
                for tid in territories:
                    st_t, _ = asc("POST", "/v1/subscriptionIntroductoryOffers", {
                        "data": {
                            "type": "subscriptionIntroductoryOffers",
                            "attributes": {"duration": "THREE_DAYS", "offerMode": "FREE_TRIAL", "numberOfPeriods": 1, "startDate": None, "endDate": None},
                            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}, "territory": {"data": {"type": "territories", "id": tid}}},
                        }
                    })
                    if st_t in (200, 201):
                        ok_t += 1
                print(f"  ✓ Added 3-Day Free Trial to {ok_t}/{len(territories)} territories on {spec['pid']}")

        st_ss, res_ss = asc("GET", f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
        if (st_ss == 404 or not (isinstance(res_ss, dict) and res_ss.get("data"))) and review_shot.exists():
            upload_binary_asset("/v1/subscriptionAppStoreReviewScreenshots", "/v1/subscriptionAppStoreReviewScreenshots", "subscriptionAppStoreReviewScreenshots", "subscription", "subscriptions", sid, review_shot)

    return life_id, sg_id, sub_ids


def wait_and_attach_build(app_id: str, ver_id: str, wait_secs: int = 360) -> bool:
    print("[5/5] Waiting for VALID build to attach...")
    deadline = time.time() + wait_secs
    while True:
        _, blds = asc("GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5")
        data = blds.get("data", []) if isinstance(blds, dict) else []
        valid = next((b for b in data if b["attributes"].get("processingState") == "VALID"), None)
        if valid:
            st, _ = asc("PATCH", f"/v1/appStoreVersions/{ver_id}/relationships/build", {"data": {"type": "builds", "id": valid["id"]}})
            print(f"  ✓ Attached VALID build {valid['attributes']['version']} ({valid['id']}) -> {st}")
            return st in (200, 204)
        states = [(b["attributes"].get("version"), b["attributes"].get("processingState")) for b in data]
        print(f"  ... builds so far: {states}")
        if time.time() >= deadline:
            return False
        time.sleep(15)


def submit_for_review(app_id: str, ver_id: str, life_id: Optional[str], sg_id: Optional[str], sub_ids: list[str]) -> None:
    print("[SUBMIT] Submitting MileDeck 1.0.0 + Lifetime IAP + Subscriptions to Apple App Review...")
    _, existing_rs = asc("GET", f"/v1/apps/{app_id}/reviewSubmissions?filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES")
    rs_id = None
    if isinstance(existing_rs, dict) and existing_rs.get("data"):
        rs_id = existing_rs["data"][0]["id"]
    if not rs_id:
        st_rs, res_rs = asc("POST", "/v1/reviewSubmissions", {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        if st_rs not in (200, 201):
            print("  ! reviewSubmissions create returned:", st_rs, res_rs)
            return
        rs_id = res_rs["data"]["id"]

    st_i, _ = asc("POST", "/v1/reviewSubmissionItems", {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rs_id}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}},
            },
        }
    })
    print(f"  + Added appStoreVersion -> {st_i}")

    if life_id:
        st_l, res_l = asc("POST", "/v1/inAppPurchaseSubmissions", {
            "data": {
                "type": "inAppPurchaseSubmissions",
                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": life_id}}},
            }
        })
        print(f"  + Submitted Lifetime IAP ({life_id}) -> {st_l}")
        if st_l not in (200, 201):
            print("    detail:", res_l)

    if sg_id:
        st_g, res_g = asc("POST", "/v1/subscriptionGroupSubmissions", {
            "data": {
                "type": "subscriptionGroupSubmissions",
                "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": sg_id}}},
            }
        })
        print(f"  + Submitted Subscription Group ({sg_id}) -> {st_g}")
        if st_g not in (200, 201):
            print("    detail:", res_g)

    for sid in sub_ids:
        st_s, res_s = asc("POST", "/v1/subscriptionSubmissions", {
            "data": {
                "type": "subscriptionSubmissions",
                "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}},
            }
        })
        print(f"  + Submitted Subscription ({sid}) -> {st_s}")
        if st_s not in (200, 201):
            print("    detail:", res_s)

    st_sub, res_sub = asc("PATCH", f"/v1/reviewSubmissions/{rs_id}", {
        "data": {"type": "reviewSubmissions", "id": rs_id, "attributes": {"submitted": True}}
    })
    print(f"  🚀 Submitted reviewSubmission ({rs_id}) -> {st_sub}")
    if st_sub not in (200, 201):
        print("   ", res_sub)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upload-ipa", action="store_true")
    parser.add_argument("--screenshots", action="store_true")
    parser.add_argument("--submit", action="store_true")
    args = parser.parse_args()

    meta = json.loads(META_PATH.read_text(encoding="utf-8"))
    st, res = asc("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if st != 200 or not res.get("data"):
        print(f"ERROR: App shell {BUNDLE_ID} not found in ASC yet.")
        return 2
    app_id = res["data"][0]["id"]
    print(f"✅ Found MileDeck App ID: {app_id}")

    if args.upload_ipa:
        print(f"🚀 Uploading {IPA_PATH} via xcrun altool...")
        subprocess.run([
            "xcrun", "altool", "--upload-app", "-t", "ios",
            "-f", str(IPA_PATH), "--apiKey", KEY_ID, "--apiIssuer", ISSUER_ID,
        ], check=True)
        print("  ✓ IPA upload accepted by Apple!")

    territories = get_all_territories()
    ver_id = sync_core_metadata(app_id, meta, territories, do_shots=args.screenshots)
    life_id, sg_id, sub_ids = sync_all_iaps(app_id, territories)

    if args.submit:
        attached = wait_and_attach_build(app_id, ver_id, wait_secs=360)
        if attached:
            submit_for_review(app_id, ver_id, life_id, sg_id, sub_ids)
        else:
            print("  ! Build still processing; re-run with --submit in 2 minutes.")

    print("--- Final Readiness Check ---")
    _, iaps = asc("GET", f"/v1/apps/{app_id}/inAppPurchasesV2")
    for x in iaps.get("data", []):
        print("  IAP:", x["attributes"]["productId"], "->", x["attributes"]["state"])
    _, sgs = asc("GET", f"/v1/apps/{app_id}/subscriptionGroups")
    for sg in sgs.get("data", []):
        _, subs = asc("GET", f"/v1/subscriptionGroups/{sg['id']}/subscriptions")
        for x in subs.get("data", []):
            print("  Sub:", x["attributes"]["productId"], "->", x["attributes"]["state"])
    _, vers = asc("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS")
    for v in vers.get("data", []):
        print("  Version:", v["attributes"]["versionString"], "->", v["attributes"]["appStoreState"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
