#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
swiftc -parse-as-library Sources/StudyDockCore/*.swift Scripts/CoreChecks.swift -o .build/checks/core-checks
.build/checks/core-checks
