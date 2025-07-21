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
        echo "  - Checking $(basename "$patch")"
        # Check if patch is already applied
        if patch -p1 -d "$LLVM_DIR" --dry-run -R < "$patch" >/dev/null 2>&1; then
            echo "    Patch already applied, skipping"
        else
            echo "    Applying patch"
            if ! patch -p1 -d "$LLVM_DIR" < "$patch"; then
                emit_error "PatchError" "E003" "Failed to apply patch" "$(basename "$patch")"
            fi
        fi
    fi
done

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || emit_error "FileSystemError" "E004" "Cannot create build directory" "$BUILD_DIR"

# Clean build if requested
if [[ "${CLEAN_BUILD:-}" == "1" ]]; then
    echo "Performing clean build..."
    rm -rf *
fi

# Configure build
echo "Configuring LLVM build..."
# Enable ccache if available
CCACHE_OPTION="OFF"
if command -v ccache &> /dev/null; then
    echo "Using ccache for faster builds"
    export CMAKE_C_COMPILER_LAUNCHER=ccache
    export CMAKE_CXX_COMPILER_LAUNCHER=ccache
    CCACHE_OPTION="ON"
    ccache -s # Show ccache stats
else
    echo "ccache not found, building without cache"
fi

if ! cmake -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DLLVM_TARGETS_TO_BUILD="X86;M68k" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="M68k" \
    -DLLVM_CCACHE_BUILD="$CCACHE_OPTION" \
    "../../$LLVM_DIR/llvm"; then
    
    emit_error "ConfigurationError" "E005" "CMake configuration failed" "Check CMakeLists.txt and patches"
fi

# Build
echo "Building LLVM (this may take a while)..."
BUILD_LOG="${BUILD_DIR}/build.log"
cmake --build . --target install -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4) 2>&1 | tee "$BUILD_LOG"
BUILD_RESULT=${PIPESTATUS[0]}

# Check if build actually failed or if everything is just up-to-date
if [[ $BUILD_RESULT -ne 0 ]]; then
    # Check if this is just an "up-to-date" situation
    if grep -q "Up-to-date:" "$BUILD_LOG" && grep -q "Install configuration:" "$BUILD_LOG"; then
        echo "Build artifacts are up-to-date, skipping rebuild"
    else
        # Try to extract specific error
        if grep -q "undefined reference" "$BUILD_LOG" 2>/dev/null; then
            emit_error "LinkError" "E006" "Linker error during build" "Check symbol definitions in patches"
        elif grep -q "No rule to make target" "$BUILD_LOG" 2>/dev/null; then
            emit_error "BuildError" "E007" "Missing build target" "Check CMake configuration"
        elif grep -q "error: unknown type name" "$BUILD_LOG" 2>/dev/null; then
            emit_error "CompileError" "E011" "Compilation error" "Check patch syntax and includes"
        elif grep -q "CMake Error" "$BUILD_LOG" 2>/dev/null; then
            emit_error "ConfigurationError" "E012" "CMake configuration error" "Check CMakeLists.txt files"
        else
            emit_error "BuildError" "E008" "Generic build failure" "See build.log for details"
        fi
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