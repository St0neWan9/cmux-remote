#!/usr/bin/env python3
"""Generate the small iPhone project without installing a project generator."""
from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).resolve().parents[1]
ios = root / 'ios'
project = ios / 'CmuxRemote.xcodeproj'
project.mkdir(exist_ok=True)
release = json.loads((ios / 'Release.json').read_text())
for field, pattern in {'bundle_id': r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+',
                       'team_id': r'[A-Z0-9]{10}', 'version': r'\d+\.\d+\.\d+',
                       'profile_name': r'[^\x00-\x1f]+'}.items():
    if not re.fullmatch(pattern, release[field]):
        raise SystemExit(f'Invalid release setting: {field}')

def key(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

objects = {}
def add(name, value):
    ident = key(name)
    objects[ident] = value
    return ident

source_refs, source_builds = [], []
for path in sorted([*(ios / 'Sources').glob('*.swift'), *(ios / 'Sources').glob('*.metal')]):
    source_type = 'sourcecode.metal' if path.suffix == '.metal' else 'sourcecode.swift'
    ref = add(str(path.relative_to(ios)), f'isa = PBXFileReference; lastKnownFileType = {source_type}; path = "Sources/{path.name}"; sourceTree = "<group>";')
    source_refs.append(ref)
    source_builds.append(add('build:' + str(path.relative_to(ios)), f'isa = PBXBuildFile; fileRef = {ref};'))

locale_refs = []
for locale in ('en', 'zh-Hans'):
    locale_refs.append(add('locale:' + locale, f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = "{locale}"; path = "Resources/{locale}.lproj/Localizable.strings"; sourceTree = "<group>";'))
variant = add('strings', f'isa = PBXVariantGroup; children = ({", ".join(locale_refs)}); name = Localizable.strings; sourceTree = "<group>";')
strings_build = add('strings-build', f'isa = PBXBuildFile; fileRef = {variant};')
product = add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = CmuxRemote.app; sourceTree = BUILT_PRODUCTS_DIR;')
info_locale_refs = []
for locale in ('en', 'zh-Hans'):
    info_locale_refs.append(add('info-locale:' + locale, f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = "{locale}"; path = "Resources/{locale}.lproj/InfoPlist.strings"; sourceTree = "<group>";'))
info_variant = add('info-strings', f'isa = PBXVariantGroup; children = ({", ".join(info_locale_refs)}); name = InfoPlist.strings; sourceTree = "<group>";')
info_build = add('info-strings-build', f'isa = PBXBuildFile; fileRef = {info_variant};')
asset_ref = add('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "Resources/Assets.xcassets"; sourceTree = "<group>";')
asset_build = add('assets-build', f'isa = PBXBuildFile; fileRef = {asset_ref};')
privacy_ref = add('privacy', 'isa = PBXFileReference; lastKnownFileType = text.xml; path = "Resources/PrivacyInfo.xcprivacy"; sourceTree = "<group>";')
privacy_build = add('privacy-build', f'isa = PBXBuildFile; fileRef = {privacy_ref};')
test_refs, test_builds = [], []
for path in sorted((ios / 'Tests').glob('*.swift')):
    ref = add(str(path.relative_to(ios)), f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Tests/{path.name}"; sourceTree = "<group>";')
    test_refs.append(ref)
    test_builds.append(add('test-build:' + str(path.relative_to(ios)), f'isa = PBXBuildFile; fileRef = {ref};'))
test_product = add('test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = CmuxRemoteTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
ui_refs, ui_builds = [], []
for path in sorted((ios / 'UITests').glob('*.swift')):
    ref = add(str(path.relative_to(ios)), f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "UITests/{path.name}"; sourceTree = "<group>";')
    ui_refs.append(ref)
    ui_builds.append(add('ui-build:' + str(path.relative_to(ios)), f'isa = PBXBuildFile; fileRef = {ref};'))
ui_product = add('ui-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = CmuxRemoteUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; children = ({product}, {test_product}, {ui_product}); name = Products; sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = ({", ".join(source_refs + test_refs + ui_refs + [variant, info_variant, asset_ref, privacy_ref, products])}); sourceTree = "<group>";')
package = add('package', 'isa = XCLocalSwiftPackageReference; relativePath = "..";')
vendor_package = add('vendor-package', 'isa = XCLocalSwiftPackageReference; relativePath = "../Vendor/CmuxAgentChat";')
deps, frameworks = [], []
for name in ('CmuxRemoteCore', 'CmuxRemoteClient', 'CmuxAgentChat'):
    dep = add('dep:' + name, f'isa = XCSwiftPackageProductDependency; productName = {name};')
    deps.append(dep)
    frameworks.append(add('framework:' + name, f'isa = PBXBuildFile; productRef = {dep};'))
sources = add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(source_builds)}); runOnlyForDeploymentPostprocessing = 0;')
resources = add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({strings_build}, {info_build}, {asset_build}, {privacy_build}); runOnlyForDeploymentPostprocessing = 0;')
frameworks_phase = add('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({", ".join(frameworks)}); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs = [], []
for config in ('Debug', 'Release'):
    debug_flags = 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES;' if config == 'Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O";'
    project_configs.append(add('project:' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 18.0; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; {debug_flags} }};'))
    # Manual distribution signing belongs to the app target alone: package targets cannot
    # carry a profile, so a global setting reaches them and fails the Release archive.
    signing = (f'CODE_SIGN_STYLE = Manual; PROVISIONING_PROFILE_SPECIFIER = {json.dumps(release["profile_name"])}; '
               f'CODE_SIGN_IDENTITY = "Apple Distribution";') if config == 'Release' else 'CODE_SIGN_STYLE = Automatic;'
    target_configs.append(add('target:' + config, f'''isa = XCBuildConfiguration; name = {config}; buildSettings = {{
        PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = {release["bundle_id"]};
        GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = Info.plist; INFOPLIST_KEY_CFBundleDisplayName = {json.dumps(release["display_name"])};
        CREATE_INFOPLIST_SECTION_IN_BINARY = YES;
        INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Connect to your paired cmux Bridge on your local network.";
        INFOPLIST_KEY_NSCameraUsageDescription = "Scan your Mac Bridge pairing code.";
        INFOPLIST_KEY_NSMicrophoneUsageDescription = "Record speech on this device to prepare an editable conversation draft.";
        INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "Recognize speech on this device. Audio is not sent to your Bridge or agent.";
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
        INFOPLIST_KEY_UILaunchScreen_Generation = YES;
        SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; TARGETED_DEVICE_FAMILY = "1,2";
        {signing} DEVELOPMENT_TEAM = {release["team_id"]}; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; MARKETING_VERSION = {release["version"]}; CURRENT_PROJECT_VERSION = 1;
        CODE_SIGN_ENTITLEMENTS = CmuxRemote.entitlements;
        SWIFT_STRICT_CONCURRENCY = complete;
    }};'''))
project_list = add('project-list', f'isa = XCConfigurationList; buildConfigurations = ({", ".join(project_configs)}); defaultConfigurationName = Release; defaultConfigurationIsVisible = 0;')
target_list = add('target-list', f'isa = XCConfigurationList; buildConfigurations = ({", ".join(target_configs)}); defaultConfigurationName = Release; defaultConfigurationIsVisible = 0;')
target = add('target', f'isa = PBXNativeTarget; name = CmuxRemote; productName = CmuxRemote; productType = "com.apple.product-type.application"; productReference = {product}; buildConfigurationList = {target_list}; buildPhases = ({sources}, {frameworks_phase}, {resources}); buildRules = (); dependencies = (); packageProductDependencies = ({", ".join(deps)});')
test_configs = []
for config in ('Debug', 'Release'):
    test_configs.append(add('test-config:' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = {release["bundle_id"]}.tests; GENERATE_INFOPLIST_FILE = YES; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/CmuxRemote.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/CmuxRemote"; BUNDLE_LOADER = "$(TEST_HOST)"; SWIFT_STRICT_CONCURRENCY = complete; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = {release["team_id"]}; TARGETED_DEVICE_FAMILY = "1,2"; }};'))
test_list = add('test-list', f'isa = XCConfigurationList; buildConfigurations = ({", ".join(test_configs)}); defaultConfigurationName = Debug; defaultConfigurationIsVisible = 0;')
test_sources = add('test-sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(test_builds)}); runOnlyForDeploymentPostprocessing = 0;')
test_proxy = add('test-proxy', f'isa = PBXContainerItemProxy; containerPortal = {key("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = CmuxRemote;')
test_dependency = add('test-dependency', f'isa = PBXTargetDependency; target = {target}; targetProxy = {test_proxy};')
test_target = add('test-target', f'isa = PBXNativeTarget; name = CmuxRemoteTests; productName = CmuxRemoteTests; productType = "com.apple.product-type.bundle.unit-test"; productReference = {test_product}; buildConfigurationList = {test_list}; buildPhases = ({test_sources}); buildRules = (); dependencies = ({test_dependency});')
ui_configs = []
for config in ('Debug', 'Release'):
    ui_configs.append(add('ui-config:' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = {release["bundle_id"]}.uitests; GENERATE_INFOPLIST_FILE = YES; TEST_TARGET_NAME = CmuxRemote; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = {release["team_id"]}; TARGETED_DEVICE_FAMILY = "1,2"; }};'))
ui_list = add('ui-list', f'isa = XCConfigurationList; buildConfigurations = ({", ".join(ui_configs)}); defaultConfigurationName = Debug; defaultConfigurationIsVisible = 0;')
ui_sources = add('ui-sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(ui_builds)}); runOnlyForDeploymentPostprocessing = 0;')
ui_target = add('ui-target', f'isa = PBXNativeTarget; name = CmuxRemoteUITests; productName = CmuxRemoteUITests; productType = "com.apple.product-type.bundle.ui-testing"; productReference = {ui_product}; buildConfigurationList = {ui_list}; buildPhases = ({ui_sources}); buildRules = (); dependencies = ({test_dependency});')
project_id = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2660; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, "zh-Hans", Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = ({package}, {vendor_package}); targets = ({target}, {test_target}, {ui_target});')
body = '\n'.join(f'{ident} = {{ {value} }};' for ident, value in objects.items())
(project / 'project.pbxproj').write_text(f'// !$*UTF8*$!\n{{ archiveVersion = 1; classes = {{}}; objectVersion = 56; objects = {{\n{body}\n}}; rootObject = {project_id}; }}\n')
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'CmuxRemote.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CmuxRemote.app" BlueprintName="CmuxRemote" ReferencedContainer="container:CmuxRemote.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="CmuxRemoteTests.xctest" BlueprintName="CmuxRemoteTests" ReferencedContainer="container:CmuxRemote.xcodeproj"/></TestableReference><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="CmuxRemoteUITests.xctest" BlueprintName="CmuxRemoteUITests" ReferencedContainer="container:CmuxRemote.xcodeproj"/></TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CmuxRemote.app" BlueprintName="CmuxRemote" ReferencedContainer="container:CmuxRemote.xcodeproj"/></BuildableProductRunnable></LaunchAction><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
''')
print(project)
