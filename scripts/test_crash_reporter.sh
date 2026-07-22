#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
harness_tmp="$(mktemp -d "${TMPDIR:-/tmp}/whisper-crash-harness.XXXXXX")"
trap 'rm -rf "$harness_tmp"' EXIT

harness_binary="$harness_tmp/CrashReporterHarness"
swiftc \
    "$repo_root/Sources/MacApp/CrashReporter.swift" \
    "$repo_root/Tests/CrashReporterHarness/main.swift" \
    -o "$harness_binary"

default_log_directory="$($harness_binary --print-default-directory)"
if [[ "$default_log_directory" != */Library/Logs/Whisper ]]; then
    echo "Unexpected default crash log directory: $default_log_directory" >&2
    exit 1
fi

set +e
log_directory="$harness_tmp/Logs/Whisper"
WHISPER_CRASH_HARNESS_DIRECTORY="$log_directory" "$harness_binary" >/dev/null 2>&1
harness_status=$?
set -e

expected_status=134
if [[ "$harness_status" -ne "$expected_status" ]]; then
    echo "Expected SIGABRT exit $expected_status, got $harness_status" >&2
    exit 1
fi

crash_log="$log_directory/crash.log"
if [[ ! -f "$crash_log" ]]; then
    echo "Crash log missing: $crash_log" >&2
    exit 1
fi

if ! grep -Fq "[Whisper] Crash signal: SIGABRT" "$crash_log"; then
    echo "Crash log missing SIGABRT record" >&2
    exit 1
fi

echo "CrashReporter baseline passed: SIGABRT exit and crash log verified"
