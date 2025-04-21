set -xeuo pipefail

export CI=true

source $(dirname $BASH_SOURCE)/utils.sh

echo "Selecting Xcode 16.0"
sudo xcode-select -s /Applications/Xcode16.0_16A242d.app/Contents/Developer
echo "Building and testing rules_swift..."

# From bazelbuild/rules_swift/.bazelci/presubmit.yml
echo "Building and testing rules_swift..."
bzl build //... --disk_cache="" --remote_cache=""

deploy ""
