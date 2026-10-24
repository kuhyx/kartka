#!/bin/bash
# Runs the QuickJS engine tests against flutter_js's bundled Linux library.
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
lib="$(find "$HOME/.pub-cache/hosted/pub.dev" \
  -path '*flutter_js-*/linux/shared/libquickjs_c_bridge_plugin.so' | sort | tail -1)"
[[ -f "$lib" ]] || { echo "flutter_js Linux library not found" >&2; exit 1; }
cd "$root"
LIBQUICKJSC_TEST_PATH="$lib" fvm flutter test test/plugins/runtime/session_quickjs_test.dart "$@"
