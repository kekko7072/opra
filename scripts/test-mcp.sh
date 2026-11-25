#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -swift-version 5 -parse-as-library macos/Opra/LocalMCPServer.swift macos/Tests/MCPTests.swift -o "$test_dir/mcp-tests"
"$test_dir/mcp-tests"
