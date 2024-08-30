#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint connect_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'TrinsicUI'
  s.version          = '0.3.14'
  s.summary          = 'Trinsic UI library.'
  s.description      = <<-DESC
We help you launch and capture the results of a Trinsic Acceptance session
                       DESC
  s.homepage         = 'https://trinsic.id'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Trinsic' => 'hello@trinsic.id' }
  s.source       = { :git => 'https://github.com/trinsic-id/sdk-swift-ui.git', :tag => 'v0.3.14' }
  s.source_files = 'Sources/**/*.{swift,h,m}'
  s.static_framework = true

  s.platform = :ios, '13.4'

    # Flutter.framework does not contain a i386 slice.
    # & Swift/Objective-C compatibility
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386', 
    'SWIFT_COMPILATION_MODE' => 'wholemodule' 
  }
  s.swift_version = '5.4'

end
