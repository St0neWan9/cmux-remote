#!/usr/bin/env python3
"""Generate the Mac Companion for native cmux workspace-group integration."""
from pathlib import Path
import hashlib
import os
import re

root = Path(__file__).resolve().parents[1]
mac = root / 'mac'
project = mac / 'CmuxRemoteMac.xcodeproj'
project.mkdir(exist_ok=True)
objects = {}
def add(name, value):
    ident = hashlib.sha1(name.encode()).hexdigest()[:24].upper()
    objects[ident] = value
    return ident

package = add('package', 'isa = XCLocalSwiftPackageReference; relativePath = "..";')
product_refs, targets, all_refs, project_configs = [], [], [], []
for config in ('Debug', 'Release'):
    flags = 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; SWIFT_OPTIMIZATION_LEVEL = "-Onone";' if config == 'Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O";'
    project_configs.append(add('project-config:' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; {flags} }};'))

for target_name, folder, suffix, extension in [('CmuxRemoteMac', 'Companion', '', False)]:
    source_builds, refs = [], []
    for path in sorted([*(mac / folder).glob('*.swift'), *(mac / 'Shared').glob('*.swift')]):
        relative = str(path.relative_to(mac))
        ref = add('file:' + relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = "<group>";')
        refs.append(ref)
        source_builds.append(add(target_name + ':build:' + relative, f'isa = PBXBuildFile; fileRef = {ref};'))
    resource_builds = []
    for resource in ('Localizable.strings', 'InfoPlist.strings'):
        locales = [add('locale:' + locale + resource, f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = "{locale}"; path = "Resources/{locale}.lproj/{resource}"; sourceTree = "<group>";') for locale in ('en', 'zh-Hans')]
        variant = add('variant:' + resource, f'isa = PBXVariantGroup; children = ({", ".join(locales)}); name = "{resource}"; sourceTree = "<group>";')
        refs.append(variant); resource_builds.append(add(target_name + ':resource:' + resource, f'isa = PBXBuildFile; fileRef = {variant};'))
    product_stem = target_name if extension else 'CmuxRemote'
    product_name = product_stem + ('.appex' if extension else '.app')
    product = add(target_name + ':product', f'isa = PBXFileReference; explicitFileType = {"wrapper.app-extension" if extension else "wrapper.application"}; path = "{product_name}"; sourceTree = BUILT_PRODUCTS_DIR;')
    product_refs.append(product); all_refs.extend(refs)
    deps, frameworks = [], []
    for name in (['CmuxRemoteMac', 'CmuxRemoteClient', 'CmuxRemoteCore', 'CmuxExtensionKit'] if extension else ['CmuxRemoteMac', 'CmuxRemoteBridge', 'CmuxRemoteClient', 'CmuxRemoteCore']):
        dep = add(target_name + ':dep:' + name, f'isa = XCSwiftPackageProductDependency; productName = {name};')
        deps.append(dep); frameworks.append(add(target_name + ':framework:' + name, f'isa = PBXBuildFile; productRef = {dep};'))
    sources = add(target_name + ':sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(source_builds)}); runOnlyForDeploymentPostprocessing = 0;')
    resources = add(target_name + ':resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(resource_builds)}); runOnlyForDeploymentPostprocessing = 0;')
    frameworks_phase = add(target_name + ':frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({", ".join(frameworks)}); runOnlyForDeploymentPostprocessing = 0;')
    phases = [sources, frameworks_phase, resources]
    dependencies = []
    configs = []
    for config in ('Debug', 'Release'):
        additional = 'APPLICATION_EXTENSION_API_ONLY = YES; SKIP_INSTALL = YES; ENABLE_APP_SANDBOX = YES; CODE_SIGN_ENTITLEMENTS = Extension/RemoteSidebar.entitlements;' if extension else 'ENABLE_APP_SANDBOX = NO; PRODUCT_MODULE_NAME = CmuxRemoteCompanionApp;'
        configs.append(add(target_name + ':' + config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ PRODUCT_NAME = "{product_stem}"; PRODUCT_BUNDLE_IDENTIFIER = "cmux-remote.desktop{suffix}"; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = {folder}/Info.plist; INFOPLIST_KEY_CFBundleDisplayName = "Cmux Remote Desktop"; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; CREATE_INFOPLIST_SECTION_IN_BINARY = YES; SWIFT_STRICT_CONCURRENCY = complete; MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 1; {additional} }};'))
    config_list = add(target_name + ':config-list', f'isa = XCConfigurationList; buildConfigurations = ({", ".join(configs)}); defaultConfigurationName = Release; defaultConfigurationIsVisible = 0;')
    targets.append(add(target_name + ':target', f'isa = PBXNativeTarget; name = {target_name}; productName = {target_name}; productType = "com.apple.product-type.{"app-extension" if extension else "application"}"; productReference = {product}; buildConfigurationList = {config_list}; buildPhases = ({", ".join(phases)}); buildRules = (); dependencies = ({", ".join(dependencies)}); packageProductDependencies = ({", ".join(deps)});'))

products = add('products', f'isa = PBXGroup; children = ({", ".join(product_refs)}); name = Products; sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = ({", ".join(dict.fromkeys(all_refs))}, {products}); sourceTree = "<group>";')
project_list = add('project-list', f'isa = XCConfigurationList; buildConfigurations = ({", ".join(project_configs)}); defaultConfigurationName = Release; defaultConfigurationIsVisible = 0;')
project_id = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2660; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, "zh-Hans", Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = ({package}); targets = ({", ".join(targets)});')
body = '\n'.join(f'{ident} = {{ {value} }};' for ident, value in objects.items())
(project / 'project.pbxproj').write_text(f'// !$*UTF8*$!\n{{ archiveVersion = 1; classes = {{}}; objectVersion = 56; objects = {{\n{body}\n}}; rootObject = {project_id}; }}\n')
schemes = project / 'xcshareddata/xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'CmuxRemoteMac.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[0]}" BuildableName="CmuxRemote.app" BlueprintName="CmuxRemoteMac" ReferencedContainer="container:CmuxRemoteMac.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[0]}" BuildableName="CmuxRemote.app" BlueprintName="CmuxRemoteMac" ReferencedContainer="container:CmuxRemoteMac.xcodeproj"/></BuildableProductRunnable></LaunchAction><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
''')
print(project)
