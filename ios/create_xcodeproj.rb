require "xcodeproj"
require "fileutils"
require "pathname"

root = File.expand_path("..", __dir__)
ios_dir = File.join(root, "ios")
sources_dir = File.join(ios_dir, "MessageApp", "Sources")
project_path = File.join(ios_dir, "MessageApp.xcodeproj")

FileUtils.rm_rf(project_path) if Dir.exist?(project_path)

project = Xcodeproj::Project.new(project_path)
main_group = project.main_group

app_group = main_group.new_group("MessageApp", "MessageApp")
sources_group = app_group.new_group("Sources", "Sources")

target = project.new_target(:application, "MessageApp", :ios, "17.0")

swift_files = Dir.glob(File.join(sources_dir, "*.swift")).sort
swift_files.each do |file_path|
  rel = Pathname.new(file_path).relative_path_from(Pathname.new(ios_dir)).to_s
  file_ref = sources_group.new_file(rel)
  target.add_file_references([file_ref])
end

project.build_configurations.each do |config|
  config.build_settings["SWIFT_VERSION"] = "5.0"
  config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
end

target.build_configurations.each do |config|
  config.build_settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.message.app"
  config.build_settings["MARKETING_VERSION"] = "1.0"
  config.build_settings["CURRENT_PROJECT_VERSION"] = "1"
  config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["INFOPLIST_KEY_UIApplicationSceneManifest_Generation"] = "YES"
  config.build_settings["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
  config.build_settings["INFOPLIST_KEY_NSMicrophoneUsageDescription"] = "Нужно для записи голосовых сообщений."
  config.build_settings["INFOPLIST_KEY_NSCameraUsageDescription"] = "Нужно для записи видеосообщений."
  config.build_settings["INFOPLIST_KEY_NSPhotoLibraryUsageDescription"] = "Нужно для выбора и отправки медиа."
  config.build_settings["INFOPLIST_KEY_NSSupportsLiveActivities"] = "NO"
  config.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  config.build_settings["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = "AccentColor"
  config.build_settings["DEVELOPMENT_ASSET_PATHS"] = "\"MessageApp/Preview Content\""
  config.build_settings["TARGETED_DEVICE_FAMILY"] = "1,2"
end

project.save
puts "Created: #{project_path}"
