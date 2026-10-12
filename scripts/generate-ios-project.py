#!/usr/bin/env python3
"""Generate the small iPhone project without installing a project generator."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parents[1]
ios = root / 'ios'
project = ios / 'CmuxRemote.xcodeproj'
project.mkdir(exist_ok=True)

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
products = add('products', f'isa = PBXGroup; children = ({product}); name = Products; sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = ({", ".join(source_refs + [variant, products])}); sourceTree = "<group>";')
package = add('package', 'isa = XCLocalSwiftPackageReference; relativePath = "..";')
vendor_package = add('vendor-package', 'isa = XCLocalSwiftPackageReference; relativePath = "../Vendor/CmuxAgentChat";')
deps, frameworks = [], []
for name in ('CmuxRemoteCore', 'CmuxRemoteClient', 'CmuxAgentChat'):
    dep = add('dep:' + name, f'isa = XCSwiftPackageProductDependency; productName = {name};')
    deps.append(dep)
    frameworks.append(add('framework:' + name, f'isa = PBXBuildFile; productRef = {dep};'))
sources = add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(source_builds)}); runOnlyForDeploymentPostprocessing = 0;')
resources = add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({strings_build}); runOnlyForDeploymentPostprocessing = 0;')
frameworks_phase = add('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({", ".join(frameworks)}); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs = [], []
for config in ('Debug', 'Release'):
    debug_flags = 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"; SWIFT_OPTIMIZATION_LEVEL = "-Onone";' if config == 'Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O";'
    project_configs.append(add('project:' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; {debug_flags} }};'))
    target_configs.append(add('target:' + config, f'''isa = XCBuildConfiguration; name = {config}; buildSettings = {{
        PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.st0newan9.cmux-remote;
        GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = Info.plist; INFOPLIST_KEY_CFBundleDisplayName = "cmux remote";
        CREATE_INFOPLIST_SECTION_IN_BINARY = YES;
        INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Connect to your paired cmux Bridge on your local network.";
        INFOPLIST_KEY_NSCameraUsageDescription = "Scan your Mac Bridge pairing code.";
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
        INFOPLIST_KEY_UILaunchScreen_Generation = YES;
        SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; TARGETED_DEVICE_FAMILY = "1,2";
        CODE_SIGN_STYLE = Automatic; MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 1;
        CODE_SIGN_ENTITLEMENTS = CmuxRemote.entitlements;
        SWIFT_STRICT_CONCURRENCY = complete;
    }};'''))
project_list = add('project-list', f'isa = XCConfigurationList; buildConfigurations = ({", ".join(project_configs)}); defaultConfigurationName = Release; defaultConfigurationIsVisible = 0;')
target_list = add('target-list', f'isa = XCConfigurationList; buildConfigurations = ({", ".join(target_configs)}); defaultConfigurationName = Release; defaultConfigurationIsVisible = 0;')
target = add('target', f'isa = PBXNativeTarget; name = CmuxRemote; productName = CmuxRemote; productType = "com.apple.product-type.application"; productReference = {product}; buildConfigurationList = {target_list}; buildPhases = ({sources}, {frameworks_phase}, {resources}); buildRules = (); dependencies = (); packageProductDependencies = ({", ".join(deps)});')
project_id = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2660; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, "zh-Hans", Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = ({package}, {vendor_package}); targets = ({target});')
body = '\n'.join(f'{ident} = {{ {value} }};' for ident, value in objects.items())
(project / 'project.pbxproj').write_text(f'// !$*UTF8*$!\n{{ archiveVersion = 1; classes = {{}}; objectVersion = 56; objects = {{\n{body}\n}}; rootObject = {project_id}; }}\n')
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'CmuxRemote.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CmuxRemote.app" BlueprintName="CmuxRemote" ReferencedContainer="container:CmuxRemote.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CmuxRemote.app" BlueprintName="CmuxRemote" ReferencedContainer="container:CmuxRemote.xcodeproj"/></BuildableProductRunnable></LaunchAction><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
''')
print(project)
