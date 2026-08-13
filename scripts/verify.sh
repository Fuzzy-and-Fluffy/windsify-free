#!/bin/zsh

set -euo pipefail

PROJECT_DIR=${0:A:h:h}
PROJECT_SPEC=${WINDSIFY_FREE_PROJECT_SPEC:-"$PROJECT_DIR/project-free.yml"}
if [[ ! -f "$PROJECT_SPEC" ]]; then
  PROJECT_SPEC="$PROJECT_DIR/project.yml"
fi

PROJECT_GENERATION_DIR=$(mktemp -d /private/tmp/windsify-free-project.XXXXXX)
DERIVED_DATA=$(mktemp -d /private/tmp/windsify-free-derived.XXXXXX)

cleanup() {
  [[ ! -d "$PROJECT_GENERATION_DIR" ]] || /bin/rm -R "$PROJECT_GENERATION_DIR"
  [[ ! -d "$DERIVED_DATA" ]] || /bin/rm -R "$DERIVED_DATA"
}
trap cleanup EXIT

xcodegen generate \
  --quiet \
  --spec "$PROJECT_SPEC" \
  --project "$PROJECT_GENERATION_DIR" \
  --project-root "$PROJECT_DIR"
ln -s "$PROJECT_DIR/FreeApp" "$PROJECT_GENERATION_DIR/FreeApp"

xcodebuild \
  -project "$PROJECT_GENERATION_DIR/WindsifyFree.xcodeproj" \
  -scheme WindsifyFree \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project "$PROJECT_GENERATION_DIR/WindsifyFree.xcodeproj" \
  -scheme WindsifyFree \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  test
