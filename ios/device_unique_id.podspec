#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint device_unique_id.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'device_unique_id'
  s.version          = '0.4.0'
  s.summary          = 'Stable per-device unique ID for Flutter apps (Android & iOS).'
  s.description      = <<-DESC
A Flutter plugin providing a stable per-device unique ID: deterministically
derived on Android (ANDROID_ID / MediaDRM seed), Keychain-persisted on iOS,
with risk-control signals and privacy-consent-friendly explicit collection.
                       DESC
  s.homepage         = 'https://github.com/ehangwork/device_unique_id'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'ehangwork' => 'https://github.com/ehangwork' }
  s.source           = { :path => '.' }
  s.source_files = 'device_unique_id/Sources/device_unique_id/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'device_unique_id_privacy' => ['device_unique_id/Sources/device_unique_id/PrivacyInfo.xcprivacy']}
end
