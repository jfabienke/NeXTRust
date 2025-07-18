#!/usr/bin/env bash
# ci/scripts/test-pipeline.sh - Wrapper for test-all.sh (backward compatibility)
#
# Purpose: Maintain compatibility with existing references to test-pipeline.sh
# Usage: ./ci/scripts/test-pipeline.sh
#
exec "$(dirname "$0")/test-all.sh" all