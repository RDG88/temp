#!/bin/bash

# Export ansible-ee-packer image without registry prefix
# This script creates portable tar.gz files for distribution

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

VERSION="3.3.12"
SOURCE_IMAGE="degraafit/ansible-ee-packer:${VERSION}"
TARGET_NAME="ansible-ee-packer"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp}"  # Change this to a location with more space

echo -e "${GREEN}Exporting Docker image without registry prefix${NC}"
echo -e "${BLUE}Source: ${SOURCE_IMAGE}${NC}"
echo -e "${BLUE}Target: ${TARGET_NAME}:${VERSION} and ${TARGET_NAME}:latest${NC}"

# Check if source image exists
if ! docker image inspect "$SOURCE_IMAGE" >/dev/null 2>&1; then
    echo -e "${RED}Error: Source image $SOURCE_IMAGE not found${NC}"
    exit 1
fi

# Check available space
echo -e "${BLUE}Checking disk space...${NC}"
AVAILABLE_KB=$(df "$OUTPUT_DIR" | tail -1 | awk '{print $4}')
AVAILABLE_MB=$((AVAILABLE_KB / 1024))
REQUIRED_MB=300  # Estimated compressed size

echo "Available space: ${AVAILABLE_MB}MB"
echo "Required space: ~${REQUIRED_MB}MB"

if [ $AVAILABLE_MB -lt $REQUIRED_MB ]; then
    echo -e "${RED}Warning: Low disk space in $OUTPUT_DIR${NC}"
    echo -e "${YELLOW}Consider setting OUTPUT_DIR to a location with more space:${NC}"
    echo "  export OUTPUT_DIR=/path/to/larger/disk"
    echo "  ./export-image.sh"
    echo
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create tags without registry prefix
echo -e "${BLUE}Creating clean tags...${NC}"
docker tag "$SOURCE_IMAGE" "${TARGET_NAME}:${VERSION}"
docker tag "$SOURCE_IMAGE" "${TARGET_NAME}:latest"

# Export to tar.gz
OUTPUT_FILE="${OUTPUT_DIR}/${TARGET_NAME}-${VERSION}.tar.gz"
echo -e "${BLUE}Exporting to: ${OUTPUT_FILE}${NC}"

docker save "${TARGET_NAME}:${VERSION}" "${TARGET_NAME}:latest" | gzip > "$OUTPUT_FILE"

# Show results
echo -e "${GREEN}Export completed successfully!${NC}"
echo -e "${BLUE}File: ${OUTPUT_FILE}${NC}"
ls -lh "$OUTPUT_FILE"

echo
echo -e "${GREEN}Usage on target system:${NC}"
echo "  # Load the image:"
echo "  gunzip -c ${TARGET_NAME}-${VERSION}.tar.gz | docker load"
echo
echo "  # The image will be available as:"
echo "  #   ${TARGET_NAME}:${VERSION}"
echo "  #   ${TARGET_NAME}:latest"
echo
echo -e "${GREEN}Registry import:${NC}"
echo "  # Tag for your registry:"
echo "  docker tag ${TARGET_NAME}:${VERSION} your-registry.com/${TARGET_NAME}:${VERSION}"
echo "  docker push your-registry.com/${TARGET_NAME}:${VERSION}"

# Clean up temporary tags (optional)
echo -n "Remove temporary tags? (y/N): "
read REPLY
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker rmi "${TARGET_NAME}:${VERSION}" "${TARGET_NAME}:latest" 2>/dev/null || true
    echo "Temporary tags removed"
fi