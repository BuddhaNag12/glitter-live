#!/bin/sh
# Xcode Cloud runs this after cloning. The Xcode project, the depth model and the real AdMob IDs
# aren't in the repository, so they're made here.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH"

brew install xcodegen
xcodegen generate
./scripts/fetch-depth-model.sh
xcodebuild -downloadComponent MetalToolchain

# Secret environment variables set on the Xcode Cloud workflow. Without them a release shows no ads.
if [ -n "$GAD_APPLICATION_ID" ] && [ -n "$GAD_REWARDED_AD_UNIT_ID" ]; then
    printf 'GAD_APPLICATION_ID = %s\nGAD_REWARDED_AD_UNIT_ID = %s\n' "$GAD_APPLICATION_ID" "$GAD_REWARDED_AD_UNIT_ID" > Config/AdMob.secrets.xcconfig
else
    echo "warning: GAD_APPLICATION_ID or GAD_REWARDED_AD_UNIT_ID isn't set; this build uses Google's sample ad IDs."
fi
