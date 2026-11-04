#!/bin/sh
# Writes BuildNumber.xcconfig (gitignored) with CURRENT_PROJECT_VERSION set to the current UTC time as YYMMDD.HHMM
# without leading zeros in the second part (2026-11-04 09:05 -> 261104.905). Every App Store Connect upload needs a
# higher build number than the last; this one rises every minute. XcodeGen runs it before each `xcodegen generate`
# (project.yml's preGenCommand), and Signing.xcconfig includes the file.
set -eu
cd "$(dirname "$0")"
now=$(date -u +%y%m%d%H%M)
day=${now%????}
time=${now#??????}
time=$(echo "$time" | sed 's/^0*//')
build="$day.${time:-0}"
printf '// Written by stamp_build_number.sh on each `xcodegen generate`. Not committed.\nCURRENT_PROJECT_VERSION = %s\n' "$build" > BuildNumber.xcconfig
echo "Build number: $build"
