Pod::Spec.new do |s|
  s.name             = 'unixconn'
  s.version          = '0.0.1'
  s.summary          = 'A Flutter FFI plugin that embeds a Go unix proxy.'
  s.description      = <<-DESC
unixconn starts a Go proxy over a unix domain socket and lets Dart HttpClient reach it through FFI.
                       DESC
  s.homepage         = 'https://github.com/wdsgyj/unixproxy-go'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Clark' => 'clark@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/include/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.static_framework = true
  s.vendored_frameworks = 'Frameworks/unixconn_proxy.xcframework'
  s.resource_bundles = { 'unixconn_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++17'
  }
  s.user_target_xcconfig = { 'OTHER_LDFLAGS' => '$(inherited) -ObjC' }
end
