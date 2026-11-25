#!/usr/bin/env python3
"""Generate deterministic MileDeck.xcodeproj with 2 targets:
- MileDeck (iOS 18.0+ Universal iPhone + iPad App)
- MileDeckTests (XCTest Unit Test Bundle)
"""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJ_DIR = ROOT / "MileDeck.xcodeproj"
PROJ_DIR.mkdir(parents=True, exist_ok=True)


def uid(tag: str) -> str:
    return hashlib.md5(f"miledeck::{tag}".encode("utf-8")).hexdigest()[:24].upper()


def rel_sources(subdir: str, ext: str = ".swift") -> list[str]:
    base = ROOT / subdir
    if not base.exists():
        return []
    return sorted([p.relative_to(ROOT).as_posix() for p in base.rglob(f"*{ext}")])


def main() -> None:
    app_sources = rel_sources("Sources", ".swift")
    test_sources = rel_sources("Tests", ".swift")

    asset_catalog = "Resources/Assets.xcassets"
    privacy_manifest = "Resources/PrivacyInfo.xcprivacy"
    app_info_plist = "Config/Info.plist"
    app_entitlements = "Config/MileDeck.entitlements"
    storekit_config = "Config/MileDeck.storekit"

    file_refs: dict[str, tuple[str, str, str, str]] = {}
    build_files: dict[str, tuple[str, str, str | None]] = {}

    def add_file(rel_path: str, file_type: str, name: str | None = None, path_attr: str | None = None) -> str:
        if rel_path in file_refs:
            return file_refs[rel_path][0]
        fid = uid(f"fileref::{rel_path}")
        file_refs[rel_path] = (fid, file_type, name or Path(rel_path).name, path_attr or rel_path)
        return fid

    for s in app_sources:
        fid = add_file(s, "sourcecode.swift")
        build_files[f"app_src::{s}"] = (uid(f"bf_app::{s}"), fid, None)

    for s in test_sources:
        fid = add_file(s, "sourcecode.swift")
        build_files[f"test_src::{s}"] = (uid(f"bf_test::{s}"), fid, None)

    en_strings_fid = add_file(
        "Resources/en.lproj/InfoPlist.strings",
        "text.plist.strings",
        name="en",
        path_attr="Resources/en.lproj/InfoPlist.strings",
    )
    zh_strings_fid = add_file(
        "Resources/zh-Hans.lproj/InfoPlist.strings",
        "text.plist.strings",
        name="zh-Hans",
        path_attr="Resources/zh-Hans.lproj/InfoPlist.strings",
    )
    strings_vg_id = uid("variantgroup::InfoPlist.strings")
    build_files["app_res::InfoPlist.strings"] = (uid("bf_app_res::InfoPlist.strings"), strings_vg_id, None)

    assets_fid = add_file(asset_catalog, "folder.assetcatalog")
    build_files["app_res::Assets.xcassets"] = (uid("bf_app_res::Assets.xcassets"), assets_fid, None)

    privacy_fid = add_file(privacy_manifest, "text.xml")
    build_files["app_res::PrivacyInfo.xcprivacy"] = (uid("bf_app_res::PrivacyInfo.xcprivacy"), privacy_fid, None)

    storekit_fid = add_file(storekit_config, "text.json")
    build_files["test_res::MileDeck.storekit"] = (uid("bf_test_res::MileDeck.storekit"), storekit_fid, None)

    for cfg_file, ftype in [
        (app_info_plist, "text.plist.xml"),
        (app_entitlements, "text.plist.entitlements"),
    ]:
        add_file(cfg_file, ftype)

    app_prod_id = uid("product::MileDeck.app")
    test_prod_id = uid("product::MileDeckTests.xctest")

    project_id = uid("project")
    main_group_id = uid("group::main")
    products_group_id = uid("group::Products")
    sources_group_id = uid("group::Sources")
    tests_group_id = uid("group::Tests")
    resources_group_id = uid("group::Resources")
    config_group_id = uid("group::Config")

    app_target_id = uid("target::MileDeck")
    test_target_id = uid("target::MileDeckTests")

    app_sources_phase = uid("phase::app_sources")
    app_frameworks_phase = uid("phase::app_frameworks")
    app_resources_phase = uid("phase::app_resources")

    test_sources_phase = uid("phase::test_sources")
    test_frameworks_phase = uid("phase::test_frameworks")
    test_resources_phase = uid("phase::test_resources")

    dep_app_proxy = uid("proxy::app")
    dep_test_app_id = uid("dep::test_app")

    proj_debug_cfg = uid("cfg::proj_debug")
    proj_release_cfg = uid("cfg::proj_release")
    proj_cfg_list = uid("cfglist::proj")

    app_debug_cfg = uid("cfg::app_debug")
    app_release_cfg = uid("cfg::app_release")
    app_cfg_list = uid("cfglist::app")

    test_debug_cfg = uid("cfg::test_debug")
    test_release_cfg = uid("cfg::test_release")
    test_cfg_list = uid("cfglist::test")

    lines: list[str] = []
    w = lines.append

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")
    w("")

    w("/* Begin PBXBuildFile section */")
    for key, (bfid, fref, settings) in sorted(build_files.items()):
        extra = f" settings = {{{settings}}};" if settings else ""
        w(f"\t\t{bfid} /* {key} */ = {{isa = PBXBuildFile; fileRef = {fref};{extra} }};")
    w("/* End PBXBuildFile section */")
    w("")

    w("/* Begin PBXContainerItemProxy section */")
    w(f"\t\t{dep_app_proxy} /* PBXContainerItemProxy */ = {{")
    w("\t\t\tisa = PBXContainerItemProxy;")
    w(f"\t\t\tcontainerPortal = {project_id} /* Project object */;")
    w("\t\t\tproxyType = 1;")
    w(f"\t\t\tremoteGlobalIDString = {app_target_id};")
    w("\t\t\tremoteInfo = MileDeck;")
    w("\t\t};")
    w("/* End PBXContainerItemProxy section */")
    w("")

    w("/* Begin PBXFileReference section */")
    for _, (fid, ftype, name, path_attr) in sorted(file_refs.items()):
        w(f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; name = "{name}"; path = "{path_attr}"; sourceTree = "<group>"; }};')
    w(f'\t\t{app_prod_id} /* MileDeck.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MileDeck.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
    w(f'\t\t{test_prod_id} /* MileDeckTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = MileDeckTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
    w("/* End PBXFileReference section */")
    w("")

    w("/* Begin PBXFrameworksBuildPhase section */")
    for pid, label in [
        (app_frameworks_phase, "MileDeck"),
        (test_frameworks_phase, "MileDeckTests"),
    ]:
        w(f"\t\t{pid} /* Frameworks ({label}) */ = {{")
        w("\t\t\tisa = PBXFrameworksBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXFrameworksBuildPhase section */")
    w("")

    w("/* Begin PBXGroup section */")
    w(f"\t\t{main_group_id} = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{sources_group_id} /* Sources */,")
    w(f"\t\t\t\t{tests_group_id} /* Tests */,")
    w(f"\t\t\t\t{resources_group_id} /* Resources */,")
    w(f"\t\t\t\t{config_group_id} /* Config */,")
    w(f"\t\t\t\t{products_group_id} /* Products */,")
    w("\t\t\t);")
    w('\t\t\tsourceTree = "<group>";')
    w("\t\t};")

    def emit_group(gid: str, name: str, child_ids: list[str]) -> None:
        w(f"\t\t{gid} /* {name} */ = {{")
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for cid in child_ids:
            w(f"\t\t\t\t{cid},")
        w("\t\t\t);")
        w(f"\t\t\tname = {name};")
        w('\t\t\tsourceTree = "<group>";')
        w("\t\t};")

    emit_group(sources_group_id, "Sources", [file_refs[s][0] for s in app_sources])
    emit_group(tests_group_id, "Tests", [file_refs[s][0] for s in test_sources])
    emit_group(resources_group_id, "Resources", [assets_fid, privacy_fid, strings_vg_id])
    emit_group(config_group_id, "Config", [file_refs[p][0] for p in [app_info_plist, app_entitlements, storekit_config]])
    emit_group(products_group_id, "Products", [app_prod_id, test_prod_id])
    w("/* End PBXGroup section */")
    w("")

    w("/* Begin PBXNativeTarget section */")
    w(f"\t\t{app_target_id} /* MileDeck */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {app_cfg_list};")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{app_sources_phase} /* Sources */,")
    w(f"\t\t\t\t{app_frameworks_phase} /* Frameworks */,")
    w(f"\t\t\t\t{app_resources_phase} /* Resources */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = ();")
    w("\t\t\tdependencies = ();")
    w("\t\t\tname = MileDeck;")
    w("\t\t\tproductName = MileDeck;")
    w(f"\t\t\tproductReference = {app_prod_id};")
    w('\t\t\tproductType = "com.apple.product-type.application";')
    w("\t\t};")

    w(f"\t\t{test_target_id} /* MileDeckTests */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {test_cfg_list};")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{test_sources_phase} /* Sources */,")
    w(f"\t\t\t\t{test_frameworks_phase} /* Frameworks */,")
    w(f"\t\t\t\t{test_resources_phase} /* Resources */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = ();")
    w("\t\t\tdependencies = (")
    w(f"\t\t\t\t{dep_test_app_id} /* PBXTargetDependency */,")
    w("\t\t\t);")
    w("\t\t\tname = MileDeckTests;")
    w("\t\t\tproductName = MileDeckTests;")
    w(f"\t\t\tproductReference = {test_prod_id};")
    w('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
    w("\t\t};")
    w("/* End PBXNativeTarget section */")
    w("")

    w("/* Begin PBXProject section */")
    w(f"\t\t{project_id} /* Project object */ = {{")
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastSwiftUpdateCheck = 2720;")
    w("\t\t\t\tLastUpgradeCheck = 2720;")
    w("\t\t\t\tTargetAttributes = {")
    w(f"\t\t\t\t\t{app_target_id} = {{ DevelopmentTeam = KU364788TC; ProvisioningStyle = Automatic; }};")
    w(f"\t\t\t\t\t{test_target_id} = {{ DevelopmentTeam = KU364788TC; TestTargetID = {app_target_id}; }};")
    w("\t\t\t\t};")
    w("\t\t\t};")
    w(f"\t\t\tbuildConfigurationList = {proj_cfg_list};")
    w('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    w('\t\t\tdevelopmentRegion = en;')
    w("\t\t\thasScannedForEncodings = 0;")
    w('\t\t\tknownRegions = (en, "zh-Hans", Base);')
    w(f"\t\t\tmainGroup = {main_group_id};")
    w(f"\t\t\tproductRefGroup = {products_group_id};")
    w('\t\t\tprojectDirPath = "";')
    w('\t\t\tprojectRoot = "";')
    w("\t\t\ttargets = (")
    w(f"\t\t\t\t{app_target_id} /* MileDeck */,")
    w(f"\t\t\t\t{test_target_id} /* MileDeckTests */,")
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")
    w("")

    w("/* Begin PBXResourcesBuildPhase section */")
    for pid, keys in [
        (app_resources_phase, ["app_res::Assets.xcassets", "app_res::PrivacyInfo.xcprivacy", "app_res::InfoPlist.strings"]),
        (test_resources_phase, ["test_res::MileDeck.storekit"]),
    ]:
        w(f"\t\t{pid} = {{")
        w("\t\t\tisa = PBXResourcesBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        for k in keys:
            w(f"\t\t\t\t{build_files[k][0]} /* {k} */,")
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")
    w("")

    w("/* Begin PBXSourcesBuildPhase section */")
    for pid, prefix, items in [
        (app_sources_phase, "app_src", app_sources),
        (test_sources_phase, "test_src", test_sources),
    ]:
        w(f"\t\t{pid} = {{")
        w("\t\t\tisa = PBXSourcesBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        for s in items:
            w(f"\t\t\t\t{build_files[f'{prefix}::{s}'][0]} /* {s} */,")
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")
    w("")

    w("/* Begin PBXTargetDependency section */")
    w(f"\t\t{dep_test_app_id} = {{isa = PBXTargetDependency; target = {app_target_id}; targetProxy = {dep_app_proxy}; }};")
    w("/* End PBXTargetDependency section */")
    w("")

    w("/* Begin PBXVariantGroup section */")
    w(f"\t\t{strings_vg_id} /* InfoPlist.strings */ = {{")
    w("\t\t\tisa = PBXVariantGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{en_strings_fid} /* en */,")
    w(f"\t\t\t\t{zh_strings_fid} /* zh-Hans */,")
    w("\t\t\t);")
    w("\t\t\tname = InfoPlist.strings;")
    w('\t\t\tsourceTree = "<group>";')
    w("\t\t};")
    w("/* End PBXVariantGroup section */")
    w("")

    w("/* Begin XCBuildConfiguration section */")
    common_proj = [
        "ALWAYS_SEARCH_USER_PATHS = NO",
        "CLANG_ENABLE_MODULES = YES",
        "CLANG_ENABLE_OBJC_ARC = YES",
        "CODE_SIGN_STYLE = Automatic",
        "DEVELOPMENT_TEAM = KU364788TC",
        "ENABLE_USER_SCRIPT_SANDBOXING = YES",
        "IPHONEOS_DEPLOYMENT_TARGET = 18.0",
        "MARKETING_VERSION = 1.0.0",
        "CURRENT_PROJECT_VERSION = 1",
        "SDKROOT = iphoneos",
        'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"',
        "SWIFT_VERSION = 5.0",
        'TARGETED_DEVICE_FAMILY = "1,2"',
    ]

    def emit_cfg(cid: str, name: str, settings: list[str]) -> None:
        w(f"\t\t{cid} /* {name} */ = {{")
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        for line in settings:
            w(f"\t\t\t\t{line};")
        w("\t\t\t};")
        w(f"\t\t\tname = {name};")
        w("\t\t};")

    emit_cfg(proj_debug_cfg, "Debug", common_proj + [
        "DEBUG_INFORMATION_FORMAT = dwarf",
        "ENABLE_TESTABILITY = YES",
        "GCC_OPTIMIZATION_LEVEL = 0",
        "ONLY_ACTIVE_ARCH = YES",
        'SWIFT_OPTIMIZATION_LEVEL = "-Onone"',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG"',
    ])
    emit_cfg(proj_release_cfg, "Release", common_proj + [
        'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS = NO",
        'SWIFT_OPTIMIZATION_LEVEL = "-O"',
        "VALIDATE_PRODUCT = YES",
    ])

    app_common = [
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon",
        'CODE_SIGN_ENTITLEMENTS = "Config/MileDeck.entitlements"',
        "GENERATE_INFOPLIST_FILE = NO",
        'INFOPLIST_FILE = "Config/Info.plist"',
        'LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks"',
        "PRODUCT_BUNDLE_IDENTIFIER = com.yanghe.miledeck",
        "PRODUCT_NAME = MileDeck",
        "SWIFT_EMIT_LOC_STRINGS = YES",
    ]
    emit_cfg(app_debug_cfg, "Debug", app_common + ['CODE_SIGN_IDENTITY = "Apple Development"'])
    emit_cfg(app_release_cfg, "Release", app_common + [
        "CODE_SIGN_STYLE = Manual",
        'CODE_SIGN_IDENTITY = "Apple Distribution"',
        'PROVISIONING_PROFILE_SPECIFIER = "MileDeck AppStore Dist"',
    ])

    test_common = [
        'BUNDLE_LOADER = "$(TEST_HOST)"',
        "GENERATE_INFOPLIST_FILE = YES",
        'LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"',
        "PRODUCT_BUNDLE_IDENTIFIER = com.yanghe.miledeck.tests",
        'PRODUCT_NAME = "$(TARGET_NAME)"',
        'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/MileDeck.app/MileDeck"',
    ]
    emit_cfg(test_debug_cfg, "Debug", test_common)
    emit_cfg(test_release_cfg, "Release", test_common)
    w("/* End XCBuildConfiguration section */")
    w("")

    w("/* Begin XCConfigurationList section */")
    for list_id, label, d_id, r_id in [
        (proj_cfg_list, "PBXProject MileDeck", proj_debug_cfg, proj_release_cfg),
        (app_cfg_list, "PBXNativeTarget MileDeck", app_debug_cfg, app_release_cfg),
        (test_cfg_list, "PBXNativeTarget MileDeckTests", test_debug_cfg, test_release_cfg),
    ]:
        w(f"\t\t{list_id} /* Build configuration list for {label} */ = {{")
        w("\t\t\tisa = XCConfigurationList;")
        w("\t\t\tbuildConfigurations = (")
        w(f"\t\t\t\t{d_id} /* Debug */,")
        w(f"\t\t\t\t{r_id} /* Release */,")
        w("\t\t\t);")
        w("\t\t\tdefaultConfigurationIsVisible = 0;")
        w("\t\t\tdefaultConfigurationName = Release;")
        w("\t\t};")
    w("/* End XCConfigurationList section */")
    w("\t};")
    w(f"\trootObject = {project_id} /* Project object */;")
    w("}")

    (PROJ_DIR / "project.pbxproj").write_text("\n".join(lines) + "\n", encoding="utf-8")

    schemes_dir = PROJ_DIR / "xcshareddata" / "xcschemes"
    schemes_dir.mkdir(parents=True, exist_ok=True)
    scheme_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2720"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target_id}"
               BuildableName = "MileDeck.app"
               BlueprintName = "MileDeck"
               ReferencedContainer = "container:MileDeck.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target_id}"
               BuildableName = "MileDeckTests.xctest"
               BlueprintName = "MileDeckTests"
               ReferencedContainer = "container:MileDeck.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target_id}"
            BuildableName = "MileDeck.app"
            BlueprintName = "MileDeck"
            ReferencedContainer = "container:MileDeck.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
      <StoreKitConfigurationFileReference
         identifier = "../../Config/MileDeck.storekit">
      </StoreKitConfigurationFileReference>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target_id}"
            BuildableName = "MileDeck.app"
            BlueprintName = "MileDeck"
            ReferencedContainer = "container:MileDeck.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug" />
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES" />
</Scheme>
"""
    (schemes_dir / "MileDeck.xcscheme").write_text(scheme_xml, encoding="utf-8")
    print(f"Generated {PROJ_DIR} ({len(app_sources)} app files, {len(test_sources)} test files)")


if __name__ == "__main__":
    main()
