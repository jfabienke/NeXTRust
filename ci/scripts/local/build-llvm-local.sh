#!/bin/bash
# Local LLVM build script for faster iteration
# This builds LLVM once locally to avoid CI wait times

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build/llvm"
LLVM_DIR="$SCRIPT_DIR/llvm-project/llvm"
INSTALL_DIR="$SCRIPT_DIR/toolchain"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Local LLVM Build Setup ===${NC}"
echo "Build directory: $BUILD_DIR"
echo "Install directory: $INSTALL_DIR"

# Check if LLVM is already built
if [[ -f "$INSTALL_DIR/bin/clang" ]]; then
    echo -e "${YELLOW}LLVM already built at $INSTALL_DIR${NC}"
    echo "To rebuild, delete the build and toolchain directories"
    exit 0
fi

# Apply patches
echo -e "${GREEN}Applying LLVM patches...${NC}"
cd "$SCRIPT_DIR/llvm-project"
if git apply --check "$SCRIPT_DIR/patches/llvm/0001-m68k-mach-o-support.patch" 2>/dev/null; then
    git apply "$SCRIPT_DIR/patches/llvm/0001-m68k-mach-o-support.patch"
    echo "Patch applied successfully"
else
    echo -e "${YELLOW}Patch already applied or conflicts exist${NC}"
fi

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure LLVM with minimal options for faster build
echo -e "${GREEN}Configuring LLVM...${NC}"
cmake -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="M68k" \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLLVM_CCACHE_BUILD=ON \
    -DLLVM_USE_LINKER=lld \
    -DLLVM_PARALLEL_LINK_JOBS=2 \
    "$LLVM_DIR"

# Build LLVM
echo -e "${GREEN}Building LLVM (this will take 30-60 minutes)...${NC}"
echo "Using $(nproc 2>/dev/null || sysctl -n hw.ncpu) cores"

# Show progress
ninja -j$(nproc 2>/dev/null || sysctl -n hw.ncpu) install | while read line; do
    if [[ $line =~ \[([0-9]+)/([0-9]+)\] ]]; then
        current=${BASH_REMATCH[1]}
        total=${BASH_REMATCH[2]}
        percent=$((current * 100 / total))
        printf "\r[%-50s] %d%%" $(printf '#%.0s' $(seq 1 $((percent / 2)))) $percent
    fi
done

echo -e "\n${GREEN}LLVM built successfully!${NC}"
echo -e "Toolchain installed at: ${YELLOW}$INSTALL_DIR${NC}"

# Test the build
echo -e "${GREEN}Testing LLVM build...${NC}"
"$INSTALL_DIR/bin/clang" --version
"$INSTALL_DIR/bin/clang" -target m68k-next-nextstep --print-target-triple

echo -e "${GREEN}Local LLVM build complete!${NC}"
echo "To use this build, add to your PATH:"
echo "  export PATH=\"$INSTALL_DIR/bin:\$PATH\""