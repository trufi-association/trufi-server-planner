#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          Trufi Server Planner Setup                         ║"
    echo "║          Trufi Association                                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_usage() {
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 --gtfs <path> [--web <path>]"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  --gtfs <path>      Path to GTFS file (.zip)"
    echo "  --web <path>       Path to Flutter web build directory (optional)"
    echo "  --help             Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 --gtfs ../input/cochabamba.gtfs.zip"
    echo "  $0 --gtfs ../input/cochabamba.gtfs.zip --web ../trufi-app/build/web"
}

check_file_exists() {
    if [ ! -e "$1" ]; then
        echo -e "${RED}Error: File or directory not found: $1${NC}"
        exit 1
    fi
}

# Default values
GTFS_PATH=""
WEB_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --gtfs)
            GTFS_PATH="$2"
            shift 2
            ;;
        --web)
            WEB_PATH="$2"
            shift 2
            ;;
        --help|-h)
            print_header
            print_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            print_usage
            exit 1
            ;;
    esac
done

print_header

# Validate required arguments
if [ -z "$GTFS_PATH" ]; then
    echo -e "${RED}Error: --gtfs is required${NC}"
    echo ""
    print_usage
    exit 1
fi

# Validate files exist
check_file_exists "$GTFS_PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}Configuration:${NC}"
echo "  GTFS: $GTFS_PATH"
if [ -n "$WEB_PATH" ]; then
    echo "  Web:  $WEB_PATH"
fi
echo ""

# Copy GTFS data
if [ -f "$SCRIPT_DIR/gtfs_data.zip" ]; then
    echo -e "${YELLOW}Warning: gtfs_data.zip already exists.${NC}"
    read -p "Do you want to replace it? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Skipping GTFS copy.${NC}"
    else
        echo -e "${BLUE}Copying GTFS data...${NC}"
        cp "$GTFS_PATH" "$SCRIPT_DIR/gtfs_data.zip"
    fi
else
    echo -e "${BLUE}Copying GTFS data...${NC}"
    cp "$GTFS_PATH" "$SCRIPT_DIR/gtfs_data.zip"
fi

# Setup web directory
if [ -n "$WEB_PATH" ]; then
    check_file_exists "$WEB_PATH"
    echo -e "${BLUE}Copying Flutter web build...${NC}"
    rm -rf "$SCRIPT_DIR/web"
    cp -r "$WEB_PATH" "$SCRIPT_DIR/web"
elif [ ! -d "$SCRIPT_DIR/web" ]; then
    echo -e "${BLUE}Creating placeholder web directory...${NC}"
    mkdir -p "$SCRIPT_DIR/web"
    cat > "$SCRIPT_DIR/web/index.html" << 'HTMLEOF'
<html><head><title>Trufi</title></head><body>Trufi App</body></html>
HTMLEOF
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Setup complete!                                             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Start with Docker:"
echo -e "     ${BLUE}docker-compose up --build${NC}"
echo ""
echo "  2. Or run locally:"
echo -e "     ${BLUE}dart run bin/server.dart${NC}"
echo ""
echo "  3. Access the API at:"
echo -e "     ${BLUE}http://localhost:8080/api/docs${NC}"
