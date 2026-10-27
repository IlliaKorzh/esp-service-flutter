#
# CocoaPods spec of the iOS part of esp_service. The sources are shared with
# Swift Package Manager (esp_service/Package.swift).
#
Pod::Spec.new do |s|
  s.name             = 'esp_service'
  s.version          = '0.4.0'
  s.summary          = 'ESP push client: APNs token, permission and notification taps.'
  s.description      = <<-DESC
iOS part of the esp_service Flutter package: gets the APNs device token, asks for
the notification permission and hands taps on ESP pushes to Dart.
                       DESC
  s.homepage         = 'https://github.com/IlliaKorzh/esp-service-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'ESP (Email & Push Service) authors'
  s.source           = { :path => '.' }
  s.source_files     = 'esp_service/Sources/esp_service/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
