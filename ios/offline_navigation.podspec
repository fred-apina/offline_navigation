#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint offline_navigation.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'offline_navigation'
  s.version          = '0.3.1'
  s.summary          = 'Offline turn-by-turn navigation powered by the Organic Maps engine.'
  s.description      = <<-DESC
Drop-in offline turn-by-turn navigation page for Flutter. The map and routing engine is Organic Maps,
packaged as OfflineNavEngine.xcframework; the shared map data ships in the offline_navigation_data bundle.
                       DESC
  s.homepage         = 'https://github.com/fred-apina/offline_navigation'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'fred-apina' => 'https://github.com/fred-apina' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'

  # The engine: a dynamic framework (arm64 device + arm64 simulator slices).
  s.vendored_frameworks = 'Frameworks/OfflineNavEngine.xcframework'

  # The engine's shared data: fonts, symbols, style rules, polygons. Folders are listed by name so
  # their structure is kept; loose files are flattened into the bundle root, which is what the
  # engine expects.
  s.resource_bundles = {
    'offline_navigation_data' => [
      'Resources/fonts',
      'Resources/symbols',
      'Resources/countries-strings',
      'Resources/sound-strings',
      'Resources/*.txt',
      'Resources/*.bin',
      'Resources/*.json',
      'Resources/*.dat',
      'Resources/editor.config',
    ],
  }

  # No Intel simulator slice: Flutter apps run in arm64 simulators on Apple Silicon Macs.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
  }
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
  }
end
