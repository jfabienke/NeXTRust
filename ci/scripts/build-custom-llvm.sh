#!/usr/bin/env bash
# ci/scripts/build-custom-llvm.sh - Build custom LLVM with structured error handling
#
# Purpose: Apply patches and build LLVM for m68k-next-nextstep target
# Usage: ./ci/scripts/build-custom-llvm.sh
#
set -uo pipefail

# Trigger pre-hook if in CI
if [[ -n "${GITHUB_ACTIONS:-}" ]] && [[ -x "ci/scripts/trigger-hook.sh" ]]; then
    echo "=== Triggering pre-hook for LLVM build ==="
    ci/scripts/trigger-hook.sh pre Bash "$0 $*" || true
    echo "=== Pre-hook completed ==="
fi

# Error handling function
emit_error() {
    local error_type="$1"
    local error_code="$2"
    local details="$3"
    local context="${4:-}"
    
    # Emit structured JSON error to stderr
    cat >&2 << EOF
{
  "error_type": "$error_type",
  "error_code": "$error_code",
  "details": "$details",
  "context": "$context",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "script": "build-custom-llvm.sh",
  "phase": "${PHASE_ID:-phase-2}"
}
EOF
    
    # Trigger post-hook on failure if in CI
    if [[ -n "${GITHUB_ACTIONS:-}" ]] && [[ -x "ci/scripts/trigger-hook.sh" ]]; then
        echo "=== Triggering post-hook for LLVM build failure ===" >&2
        ci/scripts/trigger-hook.sh post Bash "build-custom-llvm.sh" 1 || true
        echo "=== Post-hook completed ===" >&2
    fi
    
    exit 1
}

echo "=== Building Custom LLVM for NeXTSTEP ==="
echo

# Configuration
LLVM_DIR="llvm-project"
BUILD_DIR="build/llvm"
INSTALL_DIR="$PWD/toolchain"
PATCHES_DIR="patches/llvm"

# Check prerequisites
if [[ ! -d "$LLVM_DIR" ]]; then
    emit_error "MissingDependency" "E001" "LLVM source directory not found" "$LLVM_DIR"
fi

if [[ ! -d "$PATCHES_DIR" ]]; then
    emit_error "MissingDependency" "E002" "Patches directory not found" "$PATCHES_DIR"
fi

# Apply patches
echo "Applying NeXTSTEP patches..."
for patch in "$PATCHES_DIR"/*.patch; do
    if [[ -f "$patch" ]]; then
        echo "  - Applying $(basename "$patch")"
        if ! patch -p1 -d "$LLVM_DIR" < "$patch"; then
            emit_error "PatchError" "E003" "Failed to apply patch" "$(basename "$patch")"
        fi
    fi
done

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || emit_error "FileSystemError" "E004" "Cannot create build directory" "$BUILD_DIR"

# Configure build
echo "Configuring LLVM build..."
# Enable ccache if available
if command -v ccache &> /dev/null; then
    echo "Using ccache for faster builds"
    export CMAKE_C_COMPILER_LAUNCHER=ccache
    export CMAKE_CXX_COMPILER_LAUNCHER=ccache
    ccache -s # Show ccache stats
fi

if ! cmake -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DLLVM_TARGETS_TO_BUILD="X86;M68k" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="M68k" \
    -DLLVM_CCACHE_BUILD=ON \
    "../../$LLVM_DIR/llvm"; then
    
    emit_error "ConfigurationError" "E005" "CMake configuration failed" "Check CMakeLists.txt and patches"
fi

# Build
echo "Building LLVM (this may take a while)..."
if ! cmake --build . --target install -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4); then
    # Try to extract specific error
    if grep -q "undefined reference" build.log 2>/dev/null; then
        emit_error "LinkError" "E006" "Linker error during build" "Check symbol definitions in patches"
    elif grep -q "No rule to make target" build.log 2>/dev/null; then
        emit_error "BuildError" "E007" "Missing build target" "Check CMake configuration"
    else
        emit_error "BuildError" "E008" "Generic build failure" "See build.log for details"
    fi
fi

# Validate build
echo "Validating build..."
if [[ ! -x "$INSTALL_DIR/bin/clang" ]]; then
    emit_error "ValidationError" "E009" "Clang binary not found after build" "$INSTALL_DIR/bin/clang"
fi

# Test with simple program
echo "Testing custom LLVM..."
cat > test.c << 'EOF'
int main() { return 0; }
EOF

if ! "$INSTALL_DIR/bin/clang" -target m68k-next-nextstep -c test.c -o test.o; then
    emit_error "TestError" "E010" "Clang cannot compile for m68k-next-nextstep" "Check triple support"
fi

# Success
echo "✅ Custom LLVM built successfully!"
echo "Installation directory: $INSTALL_DIR"

# Show ccache stats if available
if command -v ccache &> /dev/null; then
    echo "ccache statistics:"
    ccache -s
fi

# Trigger post-hook if in CI
if [[ -n "${GITHUB_ACTIONS:-}" ]] && [[ -x "ci/scripts/trigger-hook.sh" ]]; then
    echo "=== Triggering post-hook for LLVM build success ==="
    ci/scripts/trigger-hook.sh post Bash "$0 $*" 0 || true
    echo "=== Post-hook completed ==="
fi

# Log success with nextrust CLI
if command -v ./ci/scripts/nextrust &> /dev/null; then
    ./ci/scripts/nextrust update-status \
        "LLVM build completed successfully" \
        --status-type success \
        --metadata "{\"install_dir\": \"$INSTALL_DIR\", \"version\": \"$(${INSTALL_DIR}/bin/clang --version | head -1)\"}"
fi

# Clean up
rm -f test.c test.o

exit 0