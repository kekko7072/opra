#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -swift-version 5 -parse-as-library \
  macos/Opra/AudioWAV.swift \
  macos/Opra/SpeechTextChunker.swift \
  macos/Opra/OpenAISpeechOptions.swift \
  macos/Opra/OllamaSpeechClient.swift \
  macos/Opra/PDFTextNormalizer.swift \
  macos/Tests/SpeechTests.swift \
  -framework PDFKit \
  -o "$test_dir/speech-tests"
"$test_dir/speech-tests"
