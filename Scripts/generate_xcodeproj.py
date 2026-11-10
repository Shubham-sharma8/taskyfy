#!/usr/bin/env python3
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XCODEPROJ = os.path.join(ROOT, "Taskyfy.xcodeproj")
SCHEMES_DIR = os.path.join(XCODEPROJ, "xcshareddata", "xcschemes")
os.makedirs(SCHEMES_DIR, exist_ok=True)


def oid(label: str) -> str:
    return hashlib.sha1(label.encode("utf-8")).hexdigest()[:24].upper()


core_sources = [
    ("Models/TelemetryModels.swift", "Sources/TaskyfyCore/Models/TelemetryModels.swift"),
    ("Models/EventModels.swift", "Sources/TaskyfyCore/Models/EventModels.swift"),
    ("Models/Format.swift", "Sources/TaskyfyCore/Models/Format.swift"),
    ("Readers/CPUReader.swift", "Sources/TaskyfyCore/Readers/CPUReader.swift"),
    ("Readers/NetworkAndDiskReader.swift", "Sources/TaskyfyCore/Readers/NetworkAndDiskReader.swift"),
    ("Readers/SensorReader.swift", "Sources/TaskyfyCore/Readers/SensorReader.swift"),
    ("Readers/ProcessReader.swift", "Sources/TaskyfyCore/Readers/ProcessReader.swift"),
    ("Readers/Sampler.swift", "Sources/TaskyfyCore/Readers/Sampler.swift"),
    ("Services/ProcessLibrary.swift", "Sources/TaskyfyCore/Services/ProcessLibrary.swift"),
    ("Services/SignatureCache.swift", "Sources/TaskyfyCore/Services/SignatureCache.swift"),
    ("Services/HelperClient.swift", "Sources/TaskyfyCore/Services/HelperClient.swift"),
    ("Services/HistoryStore.swift", "Sources/TaskyfyCore/Services/HistoryStore.swift"),
    ("Services/EventDetector.swift", "Sources/TaskyfyCore/Services/EventDetector.swift"),
    ("State/SettingsAndUIState.swift", "Sources/TaskyfyCore/State/SettingsAndUIState.swift"),
    ("State/Monitor.swift", "Sources/TaskyfyCore/State/Monitor.swift"),
]

app_sources = [
    ("App/TaskyfyApp.swift", "Sources/Taskyfy/App/TaskyfyApp.swift"),
    ("Theme/GlassTheme.swift", "Sources/Taskyfy/Theme/GlassTheme.swift"),
    ("Components/ChartsAndRings.swift", "Sources/Taskyfy/Components/ChartsAndRings.swift"),
    ("Views/OverviewView.swift", "Sources/Taskyfy/Views/OverviewView.swift"),
    ("Views/AppsView.swift", "Sources/Taskyfy/Views/AppsView.swift"),
    ("Views/MemoryAndEnergyViews.swift", "Sources/Taskyfy/Views/MemoryAndEnergyViews.swift"),
    ("Views/SensorsNetworkAndTimelineViews.swift", "Sources/Taskyfy/Views/SensorsNetworkAndTimelineViews.swift"),
    ("Views/InspectorAndPaletteViews.swift", "Sources/Taskyfy/Views/InspectorAndPaletteViews.swift"),
    ("Views/PopoverAndSettingsViews.swift", "Sources/Taskyfy/Views/PopoverAndSettingsViews.swift"),
]

helper_sources = [
    ("main.swift", "Sources/TaskyfyHelper/main.swift"),
]

test_sources = [
    ("main.swift", "Tests/TaskyfyTests/main.swift"),
]

resources = [
    ("processes.json", "Sources/TaskyfyCore/Resources/processes.json", "text.json"),
    ("AppIcon.icns", "Resources/AppIcon.icns", "image.icns"),
    ("Info.plist", "Resources/Info.plist", "text.plist.xml"),
    ("Taskyfy.entitlements", "Resources/Taskyfy.entitlements", "text.plist.entitlements"),
    ("app.taskyfy.helper.plist", "Resources/LaunchDaemons/app.taskyfy.helper.plist", "text.plist.xml"),
]

file_refs = []
build_files = []

all_swift = core_sources + app_sources + helper_sources + test_sources
for name, rel in all_swift:
    f_id = oid("fileref:" + rel)
    b_id = oid("buildfile:" + rel)
    base = os.path.basename(rel)
    file_refs.append(f'\t\t{f_id} /* {base} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{base}"; path = "{rel}"; sourceTree = "<group>"; }};')
    build_files.append(f'\t\t{b_id} /* {base} in Sources */ = {{isa = PBXBuildFile; fileRef = {f_id} /* {base} */; }};')

for base, rel, ftype in resources:
    f_id = oid("fileref:" + rel)
    file_refs.append(f'\t\t{f_id} /* {base} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; name = "{base}"; path = "{rel}"; sourceTree = "<group>"; }};')

# Resource build files for Taskyfy app target
for rel in ["Sources/TaskyfyCore/Resources/processes.json", "Resources/AppIcon.icns"]:
    base = os.path.basename(rel)
    f_id = oid("fileref:" + rel)
    b_id = oid("buildfile:res:" + rel)
    build_files.append(f'\t\t{b_id} /* {base} in Resources */ = {{isa = PBXBuildFile; fileRef = {f_id} /* {base} */; }};')

# CopyFiles build files for LaunchDaemon plist and TaskyfyHelper binary
daemon_plist_f = oid("fileref:Resources/LaunchDaemons/app.taskyfy.helper.plist")
daemon_plist_b = oid("buildfile:copy:daemonplist")
build_files.append(f'\t\t{daemon_plist_b} /* app.taskyfy.helper.plist in Copy LaunchDaemons */ = {{isa = PBXBuildFile; fileRef = {daemon_plist_f} /* app.taskyfy.helper.plist */; }};')

# Products
prod_core = oid("prod:TaskyfyCore")
prod_app = oid("prod:Taskyfy.app")
prod_helper = oid("prod:TaskyfyHelper")
prod_tests = oid("prod:TaskyfyTests")

file_refs.extend([
    f'\t\t{prod_core} /* libTaskyfyCore.a */ = {{isa = PBXFileReference; explicitFileType = archive.ar; includeInIndex = 0; path = libTaskyfyCore.a; sourceTree = BUILT_PRODUCTS_DIR; }};',
    f'\t\t{prod_app} /* Taskyfy.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Taskyfy.app; sourceTree = BUILT_PRODUCTS_DIR; }};',
    f'\t\t{prod_helper} /* TaskyfyHelper */ = {{isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; includeInIndex = 0; path = TaskyfyHelper; sourceTree = BUILT_PRODUCTS_DIR; }};',
    f'\t\t{prod_tests} /* TaskyfyTests */ = {{isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; includeInIndex = 0; path = TaskyfyTests; sourceTree = BUILT_PRODUCTS_DIR; }};',
])

helper_embed_b = oid("buildfile:copy:helperbin")
build_files.append(f'\t\t{helper_embed_b} /* TaskyfyHelper in Embed Helper */ = {{isa = PBXBuildFile; fileRef = {prod_helper} /* TaskyfyHelper */; settings = {{ATTRIBUTES = (CodeSignOnCopy, ); }}; }};')

core_link_app = oid("buildfile:link:core:app")
core_link_helper = oid("buildfile:link:core:helper")
core_link_tests = oid("buildfile:link:core:tests")
build_files.extend([
    f'\t\t{core_link_app} /* libTaskyfyCore.a in Frameworks */ = {{isa = PBXBuildFile; fileRef = {prod_core} /* libTaskyfyCore.a */; }};',
    f'\t\t{core_link_helper} /* libTaskyfyCore.a in Frameworks */ = {{isa = PBXBuildFile; fileRef = {prod_core} /* libTaskyfyCore.a */; }};',
    f'\t\t{core_link_tests} /* libTaskyfyCore.a in Frameworks */ = {{isa = PBXBuildFile; fileRef = {prod_core} /* libTaskyfyCore.a */; }};',
])

# System library sqlite3
sqlite_f = oid("fileref:libsqlite3.tbd")
sqlite_b_app = oid("buildfile:sqlite:app")
sqlite_b_helper = oid("buildfile:sqlite:helper")
sqlite_b_tests = oid("buildfile:sqlite:tests")
file_refs.append(f'\t\t{sqlite_f} /* libsqlite3.tbd */ = {{isa = PBXFileReference; lastKnownFileType = "sourcecode.text-based-dylib-definition"; name = libsqlite3.tbd; path = usr/lib/libsqlite3.tbd; sourceTree = SDKROOT; }};')
build_files.extend([
    f'\t\t{sqlite_b_app} /* libsqlite3.tbd in Frameworks */ = {{isa = PBXBuildFile; fileRef = {sqlite_f} /* libsqlite3.tbd */; }};',
    f'\t\t{sqlite_b_helper} /* libsqlite3.tbd in Frameworks */ = {{isa = PBXBuildFile; fileRef = {sqlite_f} /* libsqlite3.tbd */; }};',
    f'\t\t{sqlite_b_tests} /* libsqlite3.tbd in Frameworks */ = {{isa = PBXBuildFile; fileRef = {sqlite_f} /* libsqlite3.tbd */; }};',
])

# Target IDs
tgt_core = oid("target:TaskyfyCore")
tgt_app = oid("target:Taskyfy")
tgt_helper = oid("target:TaskyfyHelper")
tgt_tests = oid("target:TaskyfyTests")
proj_id = oid("project:Taskyfy")

pbxproj = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{oid("proxy:core:app")} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {proj_id} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {tgt_core};
			remoteInfo = TaskyfyCore;
		}};
		{oid("proxy:helper:app")} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {proj_id} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {tgt_helper};
			remoteInfo = TaskyfyHelper;
		}};
		{oid("proxy:core:helper")} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {proj_id} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {tgt_core};
			remoteInfo = TaskyfyCore;
		}};
		{oid("proxy:core:tests")} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {proj_id} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {tgt_core};
			remoteInfo = TaskyfyCore;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		{oid("phase:copy:helper")} /* Embed Helper */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = Contents/Library/LaunchServices;
			dstSubfolderSpec = 1;
			files = (
				{helper_embed_b} /* TaskyfyHelper in Embed Helper */,
			);
			name = "Embed Helper";
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{oid("phase:copy:daemonplist")} /* Copy LaunchDaemons */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = Contents/Library/LaunchDaemons;
			dstSubfolderSpec = 1;
			files = (
				{daemon_plist_b} /* app.taskyfy.helper.plist in Copy LaunchDaemons */,
			);
			name = "Copy LaunchDaemons";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{oid("fw:core")} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{oid("fw:app")} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{core_link_app} /* libTaskyfyCore.a in Frameworks */,
				{sqlite_b_app} /* libsqlite3.tbd in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{oid("fw:helper")} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{core_link_helper} /* libTaskyfyCore.a in Frameworks */,
				{sqlite_b_helper} /* libsqlite3.tbd in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{oid("fw:tests")} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{core_link_tests} /* libTaskyfyCore.a in Frameworks */,
				{sqlite_b_tests} /* libsqlite3.tbd in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{oid("grp:root")} = {{
			isa = PBXGroup;
			children = (
				{oid("grp:TaskyfyCore")} /* TaskyfyCore */,
				{oid("grp:Taskyfy")} /* Taskyfy */,
				{oid("grp:TaskyfyHelper")} /* TaskyfyHelper */,
				{oid("grp:TaskyfyTests")} /* TaskyfyTests */,
				{oid("grp:Resources")} /* Resources */,
				{oid("grp:Products")} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{oid("grp:TaskyfyCore")} /* TaskyfyCore */ = {{
			isa = PBXGroup;
			children = (
{chr(10).join(f'\t\t\t\t{oid("fileref:" + rel)} /* {os.path.basename(rel)} */,' for _, rel in core_sources)}
			);
			name = TaskyfyCore;
			sourceTree = "<group>";
		}};
		{oid("grp:Taskyfy")} /* Taskyfy */ = {{
			isa = PBXGroup;
			children = (
{chr(10).join(f'\t\t\t\t{oid("fileref:" + rel)} /* {os.path.basename(rel)} */,' for _, rel in app_sources)}
			);
			name = Taskyfy;
			sourceTree = "<group>";
		}};
		{oid("grp:TaskyfyHelper")} /* TaskyfyHelper */ = {{
			isa = PBXGroup;
			children = (
{chr(10).join(f'\t\t\t\t{oid("fileref:" + rel)} /* {os.path.basename(rel)} */,' for _, rel in helper_sources)}
			);
			name = TaskyfyHelper;
			sourceTree = "<group>";
		}};
		{oid("grp:TaskyfyTests")} /* TaskyfyTests */ = {{
			isa = PBXGroup;
			children = (
{chr(10).join(f'\t\t\t\t{oid("fileref:" + rel)} /* {os.path.basename(rel)} */,' for _, rel in test_sources)}
			);
			name = TaskyfyTests;
			sourceTree = "<group>";
		}};
		{oid("grp:Resources")} /* Resources */ = {{
			isa = PBXGroup;
			children = (
{chr(10).join(f'\t\t\t\t{oid("fileref:" + rel)} /* {base} */,' for base, rel, _ in resources)}
				{sqlite_f} /* libsqlite3.tbd */,
			);
			name = Resources;
			sourceTree = "<group>";
		}};
		{oid("grp:Products")} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{prod_app} /* Taskyfy.app */,
				{prod_helper} /* TaskyfyHelper */,
				{prod_core} /* libTaskyfyCore.a */,
				{prod_tests} /* TaskyfyTests */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{tgt_core} /* TaskyfyCore */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {oid("cfglist:core")} /* Build configuration list for PBXNativeTarget "TaskyfyCore" */;
			buildPhases = (
				{oid("src:core")} /* Sources */,
				{oid("fw:core")} /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = TaskyfyCore;
			productName = TaskyfyCore;
			productReference = {prod_core} /* libTaskyfyCore.a */;
			productType = "com.apple.product-type.library.static";
		}};
		{tgt_app} /* Taskyfy */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {oid("cfglist:app")} /* Build configuration list for PBXNativeTarget "Taskyfy" */;
			buildPhases = (
				{oid("src:app")} /* Sources */,
				{oid("fw:app")} /* Frameworks */,
				{oid("res:app")} /* Resources */,
				{oid("phase:copy:helper")} /* Embed Helper */,
				{oid("phase:copy:daemonplist")} /* Copy LaunchDaemons */,
			);
			buildRules = (
			);
			dependencies = (
				{oid("dep:core:app")} /* PBXTargetDependency */,
				{oid("dep:helper:app")} /* PBXTargetDependency */,
			);
			name = Taskyfy;
			productName = Taskyfy;
			productReference = {prod_app} /* Taskyfy.app */;
			productType = "com.apple.product-type.application";
		}};
		{tgt_helper} /* TaskyfyHelper */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {oid("cfglist:helper")} /* Build configuration list for PBXNativeTarget "TaskyfyHelper" */;
			buildPhases = (
				{oid("src:helper")} /* Sources */,
				{oid("fw:helper")} /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				{oid("dep:core:helper")} /* PBXTargetDependency */,
			);
			name = TaskyfyHelper;
			productName = TaskyfyHelper;
			productReference = {prod_helper} /* TaskyfyHelper */;
			productType = "com.apple.product-type.tool";
		}};
		{tgt_tests} /* TaskyfyTests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {oid("cfglist:tests")} /* Build configuration list for PBXNativeTarget "TaskyfyTests" */;
			buildPhases = (
				{oid("src:tests")} /* Sources */,
				{oid("fw:tests")} /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				{oid("dep:core:tests")} /* PBXTargetDependency */,
			);
			name = TaskyfyTests;
			productName = TaskyfyTests;
			productReference = {prod_tests} /* TaskyfyTests */;
			productType = "com.apple.product-type.tool";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{proj_id} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1540;
				LastUpgradeCheck = 1540;
				TargetAttributes = {{
					{tgt_app} = {{
						CreatedOnToolsVersion = 15.4;
					}};
					{tgt_core} = {{
						CreatedOnToolsVersion = 15.4;
					}};
					{tgt_helper} = {{
						CreatedOnToolsVersion = 15.4;
					}};
					{tgt_tests} = {{
						CreatedOnToolsVersion = 15.4;
					}};
				}};
			}};
			buildConfigurationList = {oid("cfglist:proj")} /* Build configuration list for PBXProject "Taskyfy" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {oid("grp:root")};
			productRefGroup = {oid("grp:Products")} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{tgt_core} /* TaskyfyCore */,
				{tgt_helper} /* TaskyfyHelper */,
				{tgt_app} /* Taskyfy */,
				{tgt_tests} /* TaskyfyTests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{oid("res:app")} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{oid("buildfile:res:Sources/TaskyfyCore/Resources/processes.json")} /* processes.json in Resources */,
				{oid("buildfile:res:Resources/AppIcon.icns")} /* AppIcon.icns in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{oid("src:core")} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(f'\t\t\t\t{oid("buildfile:" + rel)} /* {os.path.basename(rel)} in Sources */,' for _, rel in core_sources)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{oid("src:app")} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(f'\t\t\t\t{oid("buildfile:" + rel)} /* {os.path.basename(rel)} in Sources */,' for _, rel in app_sources)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{oid("src:helper")} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(f'\t\t\t\t{oid("buildfile:" + rel)} /* {os.path.basename(rel)} in Sources */,' for _, rel in helper_sources)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{oid("src:tests")} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(f'\t\t\t\t{oid("buildfile:" + rel)} /* {os.path.basename(rel)} in Sources */,' for _, rel in test_sources)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{oid("dep:core:app")} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {tgt_core} /* TaskyfyCore */;
			targetProxy = {oid("proxy:core:app")} /* PBXContainerItemProxy */;
		}};
		{oid("dep:helper:app")} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {tgt_helper} /* TaskyfyHelper */;
			targetProxy = {oid("proxy:helper:app")} /* PBXContainerItemProxy */;
		}};
		{oid("dep:core:helper")} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {tgt_core} /* TaskyfyCore */;
			targetProxy = {oid("proxy:core:helper")} /* PBXContainerItemProxy */;
		}};
		{oid("dep:core:tests")} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {tgt_core} /* TaskyfyCore */;
			targetProxy = {oid("proxy:core:tests")} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{oid("cfg:proj:debug")} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CODE_SIGN_STYLE = Automatic;
				COPY_PHASE_STRIP = NO;
				 current_project_version = 200;
				CURRENT_PROJECT_VERSION = 200;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = 2.0.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			}};
			name = Debug;
		}};
		{oid("cfg:proj:release")} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CODE_SIGN_STYLE = Automatic;
				COPY_PHASE_STRIP = NO;
				CURRENT_PROJECT_VERSION = 200;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = 2.0.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
			}};
			name = Release;
		}};
		{oid("cfg:core:debug")} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				DEFINES_MODULE = YES;
				PRODUCT_MODULE_NAME = TaskyfyCore;
				PRODUCT_NAME = TaskyfyCore;
				SKIP_INSTALL = YES;
			}};
			name = Debug;
		}};
		{oid("cfg:core:release")} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				DEFINES_MODULE = YES;
				PRODUCT_MODULE_NAME = TaskyfyCore;
				PRODUCT_NAME = TaskyfyCore;
				SKIP_INSTALL = YES;
			}};
			name = Release;
		}};
		{oid("cfg:app:debug")} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = Resources/Taskyfy.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				INFOPLIST_FILE = Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				OTHER_LDFLAGS = (
					"-framework",
					"IOKit",
					"-framework",
					"Security",
					"-framework",
					"ServiceManagement",
					"-framework",
					"AppKit",
					"-framework",
					"SwiftUI",
					"-framework",
					"Charts",
					"-framework",
					"Symbols",
					"-framework",
					"Carbon",
					"-framework",
					"ApplicationServices",
					"-framework",
					"UserNotifications",
				);
				PRODUCT_BUNDLE_IDENTIFIER = app.taskyfy.mac;
				PRODUCT_NAME = Taskyfy;
			}};
			name = Debug;
		}};
		{oid("cfg:app:release")} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = Resources/Taskyfy.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				INFOPLIST_FILE = Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				OTHER_LDFLAGS = (
					"-framework",
					"IOKit",
					"-framework",
					"Security",
					"-framework",
					"ServiceManagement",
					"-framework",
					"AppKit",
					"-framework",
					"SwiftUI",
					"-framework",
					"Charts",
					"-framework",
					"Symbols",
					"-framework",
					"Carbon",
					"-framework",
					"ApplicationServices",
					"-framework",
					"UserNotifications",
				);
				PRODUCT_BUNDLE_IDENTIFIER = app.taskyfy.mac;
				PRODUCT_NAME = Taskyfy;
			}};
			name = Release;
		}};
		{oid("cfg:helper:debug")} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				PRODUCT_BUNDLE_IDENTIFIER = app.taskyfy.helper;
				PRODUCT_NAME = TaskyfyHelper;
				SKIP_INSTALL = YES;
			}};
			name = Debug;
		}};
		{oid("cfg:helper:release")} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				PRODUCT_BUNDLE_IDENTIFIER = app.taskyfy.helper;
				PRODUCT_NAME = TaskyfyHelper;
				SKIP_INSTALL = YES;
			}};
			name = Release;
		}};
		{oid("cfg:tests:debug")} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				PRODUCT_BUNDLE_IDENTIFIER = app.taskyfy.tests;
				PRODUCT_NAME = TaskyfyTests;
				SKIP_INSTALL = YES;
			}};
			name = Debug;
		}};
		{oid("cfg:tests:release")} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				PRODUCT_BUNDLE_IDENTIFIER = app.taskyfy.tests;
				PRODUCT_NAME = TaskyfyTests;
				SKIP_INSTALL = YES;
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{oid("cfglist:proj")} /* Build configuration list for PBXProject "Taskyfy" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{oid("cfg:proj:debug")} /* Debug */,
				{oid("cfg:proj:release")} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{oid("cfglist:core")} /* Build configuration list for PBXNativeTarget "TaskyfyCore" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{oid("cfg:core:debug")} /* Debug */,
				{oid("cfg:core:release")} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{oid("cfglist:app")} /* Build configuration list for PBXNativeTarget "Taskyfy" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{oid("cfg:app:debug")} /* Debug */,
				{oid("cfg:app:release")} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{oid("cfglist:helper")} /* Build configuration list for PBXNativeTarget "TaskyfyHelper" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{oid("cfg:helper:debug")} /* Debug */,
				{oid("cfg:helper:release")} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{oid("cfglist:tests")} /* Build configuration list for PBXNativeTarget "TaskyfyTests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{oid("cfg:tests:debug")} /* Debug */,
				{oid("cfg:tests:release")} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {proj_id} /* Project object */;
}}
"""

with open(os.path.join(XCODEPROJ, "project.pbxproj"), "w") as f:
    f.write(pbxproj)

scheme_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1540"
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
               BlueprintIdentifier = "{tgt_app}"
               BuildableName = "Taskyfy.app"
               BlueprintName = "Taskyfy"
               ReferencedContainer = "container:Taskyfy.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
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
            BlueprintIdentifier = "{tgt_app}"
            BuildableName = "Taskyfy.app"
            BlueprintName = "Taskyfy"
            ReferencedContainer = "container:Taskyfy.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

with open(os.path.join(SCHEMES_DIR, "Taskyfy.xcscheme"), "w") as f:
    f.write(scheme_xml)

print("Generated Taskyfy.xcodeproj successfully!")
