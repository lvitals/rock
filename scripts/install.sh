#!/bin/sh
# install.sh - Self-contained installer for Rock CLI (nvm/pyenv style)
# Supports both remote install and local development testing.

set -e

ROCK_VERSION="v0.1.5"
LUA_VERSION="5.4.7"
ROCK_ROOT="$HOME/.rock"
INTERNAL_DIR="$ROCK_ROOT/internal"
BIN_DIR="$ROCK_ROOT/bin"
LUA_LOGIC_DIR="$ROCK_ROOT/lua"
REPO_URL="https://github.com/lvitals/rock"

# ANSI Color Codes
BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper for colorized output
info() { printf "${BOLD}=== %b ===${NC}\n" "$1"; }
success() { printf "${GREEN}${BOLD}=== %b ===${NC}\n" "$1"; }
warn() { printf "${YELLOW}%b${NC}\n" "$1"; }

info "Installing Rock CLI ${CYAN}$ROCK_VERSION${NC}"

# 1. Check basic dependencies
for cmd in make tar; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "Error: '$cmd' not found. Please install basic build tools."
        exit 1
    fi
done

# Detect compiler
if command -v gcc > /dev/null 2>&1; then
    CC="gcc"
elif command -v clang > /dev/null 2>&1; then
    CC="clang"
else
    echo "Error: Neither 'gcc' nor 'clang' found. Please install a C compiler."
    exit 1
fi
echo "-> Using compiler: $CC"

# Detect downloader
if command -v curl > /dev/null 2>&1; then
    DOWNLOAD="curl -fsSL"
elif command -v wget > /dev/null 2>&1; then
    DOWNLOAD="wget -qO-"
else
    echo "Error: Neither 'curl' nor 'wget' found. Please install one of them."
    exit 1
fi

# 2. Identify Source Root (Local Dev vs Remote)
SRC_ROOT=""
if [ -f "./lua/rock/init.lua" ]; then
    SRC_ROOT="."
    echo "-> Local development mode detected (root)."
elif [ -f "../lua/rock/init.lua" ]; then
    SRC_ROOT=".."
    echo "-> Local development mode detected (scripts folder)."
fi

# 3. Create directory structure
mkdir -p "$BIN_DIR"
mkdir -p "$LUA_LOGIC_DIR"
mkdir -p "$INTERNAL_DIR"

# 4. Handle Source Code
if [ -n "$SRC_ROOT" ]; then
    echo "Using local source files from $SRC_ROOT..."
    # Sync local files to the install dir (excluding build artifacts)
    cp -r "$SRC_ROOT/lua/"* "$LUA_LOGIC_DIR/"
    cp "$SRC_ROOT/src/main.c" "$ROCK_ROOT/src_main.c" # Keep a copy for internal build
    BUILD_DIR="$SRC_ROOT"
else
    echo "Downloading Rock source from GitHub..."
    TEMP_SRC=$(mktemp -d)
    $DOWNLOAD "$REPO_URL/archive/refs/tags/$ROCK_VERSION.tar.gz" | tar -xz -C "$TEMP_SRC" --strip-components=1
    cp -r "$TEMP_SRC/lua/"* "$LUA_LOGIC_DIR/"
    BUILD_DIR="$TEMP_SRC"
fi

# 5. Lua Bootstrap (Ensures Rock has an engine to run)
LUA_INSTALL_PATH="$INTERNAL_DIR/lua-$LUA_VERSION"
MANAGED_LUA_PATH="$ROCK_ROOT/versions/lua-$LUA_VERSION"

if [ ! -f "$LUA_INSTALL_PATH/bin/lua" ]; then
    echo "Performing Lua $LUA_VERSION bootstrap..."
    TEMP_LUA=$(mktemp -d)
    $DOWNLOAD "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz" | tar -xz -C "$TEMP_LUA" --strip-components=1
    cd "$TEMP_LUA"
    
    PLAT="linux"
    case "$(uname)" in
        Darwin*) PLAT="macosx" ;;
        *) PLAT="linux" ;;
    esac
    
    make "$PLAT" CC="$CC" MYCFLAGS="-fPIC"
    make install INSTALL_TOP="$LUA_INSTALL_PATH"
    
    # Also install as a managed version for the user
    mkdir -p "$MANAGED_LUA_PATH"
    cp -r "$LUA_INSTALL_PATH/"* "$MANAGED_LUA_PATH/"
    
    cd - > /dev/null
else
    echo "Lua engine already bootstrapped at $LUA_INSTALL_PATH"
    if [ ! -d "$MANAGED_LUA_PATH" ]; then
        echo "Registering bootstrap Lua as managed version..."
        mkdir -p "$MANAGED_LUA_PATH"
        cp -r "$LUA_INSTALL_PATH/"* "$MANAGED_LUA_PATH/"
    fi
fi

# 6. Compile Rock linking with internal Lua
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
export PATH=\"$BIN_DIR:\$PATH\"
if [ -d \"\$ROCK_ROOT\" ]; then
  eval \"\$(rock-bin init --path)\"
  eval \"\$(rock-bin init -)\"
fi
# end rock configuration
"

if ! grep -q "rock configuration" "$SHELL_PROFILE" 2>/dev/null; then
    echo "$HOOK_CONTENT" >> "$SHELL_PROFILE"
    echo "Configuration added to $SHELL_PROFILE"
else
    echo "Rock configuration updated/verified in $SHELL_PROFILE"
fi

echo ""
success "Rock installed successfully in $BIN_DIR/rock-bin"
echo ""
printf "${BOLD}Next steps to finish setting up your environment:${NC}\n"
printf "  1. Restart your terminal or run: ${YELLOW}source %s${NC}\n" "$SHELL_PROFILE"
printf "  2. Use the bootstrapped Lua:     ${YELLOW}rock use %s${NC}\n" "$LUA_VERSION"
printf "  3. Update and upgrade rocks:     ${YELLOW}rock update && rock upgrade-rocks${NC}\n"
echo ""
printf "Try running: ${CYAN}rock --version${NC}\n"
