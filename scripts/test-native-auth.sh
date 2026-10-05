#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work="$(mktemp -d "${TMPDIR:-/tmp}/chatpop-auth-checks.XXXXXX")"
trap 'rm -rf "$work"' EXIT
sources="ios/App/App"
xcrun swiftc -swift-version 5 -D DEBUG -parse-as-library -module-cache-path "$work/cache" \
  "$sources/NativeAPIConfiguration.swift" "$sources/NativeAuthSession.swift" \
  tests/native/NativeAuthSessionTests.swift -o "$work/session-tests"
"$work/session-tests"
for mode in debug release; do
  flag=""
  if [ "$mode" = debug ]; then flag="-DDEBUG"; fi
  xcrun swiftc -swift-version 5 $flag -parse-as-library -module-cache-path "$work/cache" \
    "$sources/NativeAPIConfiguration.swift" tests/native/NativeAPIConfigurationTests.swift \
    -o "$work/config-tests"
  "$work/config-tests"
done
