#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work="$(mktemp -d "${TMPDIR:-/tmp}/chatpop-dictation-checks.XXXXXX")"
trap 'rm -rf "$work"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$work/cache" \
  ios/App/App/DictationText.swift tests/native/DictationTextTests.swift -o "$work/text-tests"
"$work/text-tests"
