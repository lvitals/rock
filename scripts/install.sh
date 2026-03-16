#!/bin/sh
# install.sh - Standard Unix installer for Rock CLI
# Respects ROCK_ROOT environment variable for custom installation paths.

set -e

ROCK_VERSION="v0.1.5"
LUA_VERSION="5.4.7"
REPO_URL="https://github.com/lvitals/rock"

# 1. Directory Setup
# Default to ~/.rock if ROCK_ROOT is not set
ROCK_ROOT="${ROCK_ROOT:-$HOME/.rock}"
INTERNAL_DIR="$ROCK_ROOT/internal"
BIN_DIR="$ROCK_ROOT/bin"
LUA_LOGIC_DIR="$ROCK_ROOT/lua"

# ANSI Color Codes
BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper for colorized output
info() { printf "${BOLD}=== %b ===${NC}\n" "$1"; }
success() { printf "${GREEN}${BOLD}=== %b ===${NC}\n" "$1"; }

info "Installing Rock CLI ${CYAN}$ROCK_VERSION${NC}"
echo "-> Target directory: $ROCK_ROOT"

# 2. Check basic dependencies
for cmd in make tar; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "Error: '$cmd' not found. Please install basic build tools."
        exit 1
    fi
done

# Detect compiler (gcc > clang > cc)
if command -v gcc > /dev/null 2>&1; then
    CC="gcc"
elif command -v clang > /dev/null 2>&1; then
    CC="clang"
elif command -v cc > /dev/null 2>&1; then
    CC="cc"
else
    echo "Error: No C compiler found (gcc/clang/cc). Please install one."
    exit 1
fi
echo "-> Using compiler: $CC"

# Detect downloader (curl > wget)
if command -v curl > /dev/null 2>&1; then
    DOWNLOAD="curl -fsSL"
elif command -v wget > /dev/null 2>&1; then
    DOWNLOAD="wget -qO-"
else
    echo "Error: Neither 'curl' nor 'wget' found. Please install one of them."
    exit 1
fi

# 3. Create directory structure
mkdir -p "$BIN_DIR"
mkdir -p "$LUA_LOGIC_DIR"
mkdir -p "$INTERNAL_DIR"

# 4. Handle Source Code (Local Dev vs Remote)
SRC_ROOT=""
if [ -f "./lua/rock/init.lua" ]; then
    SRC_ROOT="."
    echo "-> Local development mode detected (root)."
elif [ -f "../lua/rock/init.lua" ]; then
    SRC_ROOT=".."
    echo "-> Local development mode detected (scripts folder)."
fi

if [ -n "$SRC_ROOT" ]; then
    echo "Using local source files from $SRC_ROOT..."
    cp -r "$SRC_ROOT/lua/"* "$LUA_LOGIC_DIR/"
    cp "$SRC_ROOT/src/main.c" "$ROCK_ROOT/src_main.c"
    BUILD_DIR="$SRC_ROOT"
else
    echo "Downloading Rock source from GitHub..."
    TEMP_SRC=$(mktemp -d 2>/dev/null || mktemp -d -t 'rock')
    $DOWNLOAD "$REPO_URL/archive/refs/tags/$ROCK_VERSION.tar.gz" | tar -xz -C "$TEMP_SRC" --strip-components=1
    cp -r "$TEMP_SRC/lua/"* "$LUA_LOGIC_DIR/"
    BUILD_DIR="$TEMP_SRC"
fi

# 5. Lua Bootstrap
LUA_INSTALL_PATH="$INTERNAL_DIR/lua-$LUA_VERSION"
MANAGED_LUA_PATH="$ROCK_ROOT/versions/lua-$LUA_VERSION"

if [ ! -f "$LUA_INSTALL_PATH/bin/lua" ]; then
    echo "Performing Lua $LUA_VERSION bootstrap..."
    TEMP_LUA=$(mktemp -d 2>/dev/null || mktemp -d -t 'lua')
    $DOWNLOAD "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz" | tar -xz -C "$TEMP_LUA" --strip-components=1
    cd "$TEMP_LUA"
    
    PLAT="linux"
    case "$(uname)" in
        Darwin*) PLAT="macosx" ;;
        *) PLAT="linux" ;;
    esac
    
    make "$PLAT" CC="$CC" MYCFLAGS="-fPIC"
    make install INSTALL_TOP="$LUA_INSTALL_PATH"
    
    mkdir -p "$MANAGED_LUA_PATH"
    cp -r "$LUA_INSTALL_PATH/"* "$MANAGED_LUA_PATH/"
    cd - > /dev/null
else
    echo "Lua engine already bootstrapped at $LUA_INSTALL_PATH"
fi

# 6. Compile Rock
echo "Compiling Rock CLI..."
INCDIR="-I$LUA_INSTALL_PATH/include"
LIBDIR="-L$LUA_INSTALL_PATH/lib"
LUA_LDFLAGS="-llua"

cd "$BUILD_DIR"
make clean
make CC="$CC" INCDIR="$INCDIR" LIBDIR="$LIBDIR" LUA_LDFLAGS="$LUA_LDFLAGS" LUA_CFLAGS=""

# 7. Install binary
mv bin/rock bin/rock-bin
cp bin/rock-bin "$BIN_DIR/"

# 8. Shell Configuration
SHELL_PROFILE=""
case "$SHELL" in
    */bash) SHELL_PROFILE="$HOME/.bashrc" ;;
    */zsh) SHELL_PROFILE="$HOME/.zshrc" ;;
    *) SHELL_PROFILE="$HOME/.profile" ;;
esac

HOOK_CONTENT="
# rock configuration
export ROCK_ROOT=\"$ROCK_ROOT\"
export PATH=\"\$ROCK_ROOT/bin:\$PATH\"
if [ -d \"\$ROCK_ROOT\" ]; then
  eval \"\$(rock-bin init --path)\"
  eval \"\$(rock-bin init -)\"
fi
# end rock configuration
"

if [ -f "$SHELL_PROFILE" ]; then
    if ! grep -q "rock configuration" "$SHELL_PROFILE" 2>/dev/null; then
        printf "%s" "$HOOK_CONTENT" >> "$SHELL_PROFILE"
        echo "Configuration added to $SHELL_PROFILE"
    else
        echo "Rock configuration verified in $SHELL_PROFILE"
    fi
else
    warn "Shell profile $SHELL_PROFILE not found. Please add the following manually:"
    echo "$HOOK_CONTENT"
fi

echo ""
success "Rock installed successfully in $BIN_DIR/rock-bin"
echo ""
printf "${BOLD}To complete the installation:${NC}\n"
printf "  1. Restart your terminal or run: ${YELLOW}source %s${NC}\n" "$SHELL_PROFILE"
printf "  2. Use the bootstrapped Lua:     ${YELLOW}rock use %s${NC}\n" "$LUA_VERSION"
printf "  3. Update and upgrade rocks:     ${YELLOW}rock update && rock upgrade-rocks${NC}\n"
echo ""
printf "Try running: ${CYAN}rock --version${NC}\n"
