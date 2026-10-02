#!/usr/bin/env bash
# Builds the Chumbucket Android release and refuses anything that must not ship.
#
#   scripts/build_release.sh               # signed release APK (dApp Store)
#   scripts/build_release.sh --aab         # signed app bundle (Google Play)
#   scripts/build_release.sh --check-only  # validate configuration, build nothing
#
# Refuses, before Gradle starts, when the configuration (env.release.json plus
# the Supabase values from your machine) is not: CALL_RECEIPT_EXPERIENCE=true,
# SOLANA_NETWORK=mainnet-beta, CALLS_BACKEND=bff, CALLS_LINK_HOST=chumbucket.fun.
# See tool/release_config.dart for every rule.
#
# Then refuses, after the build, when the artifact is not signed by the
# certificate the Solana dApp Store pins (publishing/config.yaml
# cert_fingerprint). A debug-signed or wrongly signed build never comes out of
# this script.
#
# Inputs from your machine (never from git):
#   SUPABASE_URL, SUPABASE_ANON_KEY   environment, else env.local.json
#   CHUMBUCKET_KEY_PROPERTIES         path to key.properties, else android/key.properties
#
# This script never uploads, publishes or signs anything but the local build.
set -euo pipefail

cd "$(dirname "$0")/.."

mode="apk"
check_only=0
for arg in "$@"; do
  case "$arg" in
    --aab) mode="aab" ;;
    --check-only) check_only=1 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

fail() { echo "build_release: $*" >&2; exit 1; }

command -v flutter >/dev/null || fail "flutter is not on PATH"
command -v dart >/dev/null || fail "dart is not on PATH"

defines="build/release/dart-defines.json"
cleanup() { rm -f "$defines"; }
trap cleanup EXIT

# 1. The committed file on its own, then merged with the local Supabase values.
dart run tool/check_release_config.dart
if [[ $check_only -eq 1 ]]; then
  echo "build_release: configuration OK (check only, nothing built)."
  exit 0
fi
dart run tool/check_release_config.dart --out "$defines"

# 2. Signing. Gradle enforces this too; failing here is just faster.
if [[ "${CHUMBUCKET_ALLOW_DEBUG_SIGNED_RELEASE:-}" == "true" ]]; then
  fail "CHUMBUCKET_ALLOW_DEBUG_SIGNED_RELEASE is set. That is for compile checks only; unset it to build a release."
fi
key_properties="${CHUMBUCKET_KEY_PROPERTIES:-android/key.properties}"
[[ -f "$key_properties" ]] || fail "no key.properties at $key_properties. Restore the original upload key (see android/app/build.gradle.kts) and point CHUMBUCKET_KEY_PROPERTIES at it."

expected=$(awk '/cert_fingerprint:/ {print $2}' publishing/config.yaml | tr -d ':' | tr '[:upper:]' '[:lower:]')
[[ ${#expected} -eq 64 ]] || fail "publishing/config.yaml has no 64-hex cert_fingerprint"

# 3. Build. The R8 mapping goes to Crashlytics so native stack traces stay readable.
export CHUMBUCKET_UPLOAD_CRASHLYTICS_MAPPING="${CHUMBUCKET_UPLOAD_CRASHLYTICS_MAPPING:-true}"
if [[ "$mode" == "aab" ]]; then
  flutter build appbundle --release --dart-define-from-file="$defines"
  artifact="build/app/outputs/bundle/release/app-release.aab"
else
  # ARM only: every Seeker and Saga is arm64, and older Android phones are
  # armv7. x86_64 exists only for emulators and adds ~25 MB.
  flutter build apk --release --target-platform android-arm,android-arm64 \
    --dart-define-from-file="$defines"
  artifact="build/app/outputs/flutter-apk/app-release.apk"
fi
[[ -f "$artifact" ]] || fail "expected $artifact after the build"

# 4. The signer must be the certificate the dApp Store pins.
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk" && -f android/local.properties ]]; then
  sdk=$(awk -F= '/^sdk.dir=/ {print $2}' android/local.properties)
fi
actual=""
if [[ "$mode" == "apk" ]]; then
  apksigner=$(ls -d "$sdk"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)
  [[ -n "$apksigner" ]] || fail "apksigner not found under \$ANDROID_HOME/build-tools; cannot verify the signer"
  actual=$("$apksigner" verify --print-certs "$artifact" | awk '/Signer #1 certificate SHA-256 digest:/ {print $NF; exit}')
else
  command -v keytool >/dev/null || fail "keytool not found; cannot verify the signer"
  actual=$(keytool -printcert -jarfile "$artifact" | awk '/SHA256:/ {print $2; exit}')
fi
actual=$(echo "$actual" | tr -d ':' | tr '[:upper:]' '[:lower:]')
if [[ "$actual" != "$expected" ]]; then
  rm -f "$artifact"
  fail "the build is signed by ${actual:-nothing}, not the pinned dApp Store certificate $expected. Deleted $artifact."
fi

version=$(awk '/^version:/ {print $2}' pubspec.yaml)
sha=$(shasum -a 256 "$artifact" | awk '{print $1}')
echo
echo "Release built: $artifact"
echo "  version     $version"
echo "  signer      $actual (matches publishing/config.yaml)"
echo "  sha256      $sha"
echo "  commit      $(git rev-parse --short HEAD 2>/dev/null || echo unknown)$(git diff --quiet 2>/dev/null || echo ' (working tree has uncommitted changes)')"
echo
echo "Next: smoke-test on a Seeker (MWA connect, Google sign-in, a call, a share link, push), then publish."
