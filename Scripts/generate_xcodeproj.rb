require "xcodeproj"

PROJECT_NAME = "ClipSync"
APP_TARGET_NAME = "ClipSync"
ROOT = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "#{PROJECT_NAME}.xcodeproj")
SOURCE_DIR = File.join(ROOT, "Sources", "MediaImporterMenuBar")
INFO_PLIST = File.join("App", "Info.plist")

project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2600"
project.root_object.attributes["LastUpgradeCheck"] = "2600"

main_group = project.main_group
sources_group = main_group.new_group("Sources", "Sources")
app_group = main_group.new_group("App", "App")

target = project.new_target(:application, APP_TARGET_NAME, :osx, "13.0")

[
  "AppSettings.swift",
  "AutoImportCoordinator.swift",
  "DiskMonitor.swift",
  "MediaImporter.swift",
  "MediaImporterMenuBarApp.swift",
  "MenuBarViews.swift"
].each do |file_name|
  file_ref = sources_group.new_file(File.join("MediaImporterMenuBar", file_name))
  target.source_build_phase.add_file_reference(file_ref)
end

app_group.new_file("Info.plist")

target.build_configurations.each do |config|
  config.build_settings["PRODUCT_NAME"] = APP_TARGET_NAME
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.kang.ClipSync"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "NO"
  config.build_settings["INFOPLIST_FILE"] = INFO_PLIST
  config.build_settings["SWIFT_VERSION"] = "6.0"
  config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "13.0"
  config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  config.build_settings["DEVELOPMENT_TEAM"] = ""
  config.build_settings["ENABLE_APP_SANDBOX"] = "NO"
  config.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = ""
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/../Frameworks"
  config.build_settings["SWIFT_EMIT_LOC_STRINGS"] = "NO"
  config.build_settings["ENABLE_HARDENED_RUNTIME"] = "NO"
end

project.save
