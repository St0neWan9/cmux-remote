#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
unsigned=0
upload=0
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --unsigned) unsigned=1 ;;
    --upload) upload=1 ;;
    --dry-run) dry_run=1 ;;
    --version=*) export CMUX_REMOTE_IOS_VERSION="${arg#*=}" ;;
    --build-number=*) export CMUX_REMOTE_IOS_BUILD_NUMBER="${arg#*=}" ;;
    -h|--help) echo 'Usage: scripts/package-ios.sh --build-number=1 [--version=0.1.0] [--unsigned] [--upload] [--dry-run]'; exit 0 ;;
    *) echo 'Unknown packaging option' >&2; exit 1 ;;
  esac
done
[[ "$unsigned" == 0 || "$upload" == 0 ]] || { echo 'Unsigned archives cannot upload to TestFlight' >&2; exit 1; }
# Validate public metadata even for dry runs; never print credentials.
ruby -r ./ios/fastlane/release_config.rb -r json -e 'c=ReleaseConfig.new; puts JSON.generate({bundle:c.bundle_id,team:c.team_id,version:c.version,build:c.build_number,output:c.output})'
[[ "$dry_run" == 0 ]] || exit 0
python3 scripts/generate-ios-project.py
if [[ "$unsigned" == 1 ]]; then
  output=$(ruby -r ./ios/fastlane/release_config.rb -e 'print ReleaseConfig.new.output')
  version=$(ruby -r ./ios/fastlane/release_config.rb -e 'print ReleaseConfig.new.version')
  bundle_id=$(ruby -r ./ios/fastlane/release_config.rb -e 'print ReleaseConfig.new.bundle_id')
  if ! xcrun --sdk iphoneos metal --version >/dev/null 2>&1; then xcodebuild -downloadComponent MetalToolchain; fi
  xcodebuild -project ios/CmuxRemote.xcodeproj -scheme CmuxRemote -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' -archivePath "$output/CmuxRemote.xcarchive" \
    -derivedDataPath "$output/DerivedData" CODE_SIGNING_ALLOWED=NO \
    "PRODUCT_BUNDLE_IDENTIFIER=$bundle_id" "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$CMUX_REMOTE_IOS_BUILD_NUMBER" archive
  exit 0
fi
ruby -e 'abort "Use Ruby 3.3+ (valuz uses 3.3.12) for Fastlane" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3")'
cd ios
bundle check
export FASTLANE_OPT_OUT_USAGE=1
bundle exec fastlane ios build_testflight
if [[ "$upload" == 1 ]]; then bundle exec fastlane ios upload_testflight; fi
