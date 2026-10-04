Pod::Spec.new do |s|
  s.name = 'SpotifyiOS'
  s.version = '3.0.0'
  s.summary = 'Spotify official iOS App Remote SDK'
  s.homepage = 'https://github.com/spotify/ios-sdk'
  s.license = { :type => 'Spotify Developer Terms' }
  s.author = { 'Spotify' => 'https://developer.spotify.com' }
  s.source = { :git => 'https://github.com/spotify/ios-sdk.git', :commit => 'af71ec0bcf3baa7ec88c72119b7fdf65eb91fd67' }
  s.ios.deployment_target = '13.0'
  s.vendored_frameworks = 'SpotifyiOS.xcframework'
  s.frameworks = 'UIKit', 'Security'
  s.user_target_xcconfig = { 'OTHER_LDFLAGS' => '$(inherited) -ObjC' }
end
