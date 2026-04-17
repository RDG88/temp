#!/bin/bash

# Enhanced Build script for ansible-ee-packer with Docker Hub integration
set -e

EE_NAME="ansible-ee-packer"
VERSION="3.3.12"
DOCKER_HUB_REGISTRY="${DOCKER_HUB_REGISTRY:-docker.io/degraafit}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --push, -p     Push to Docker Hub after building"
    echo "  --fast-push    Use buildx and content-cache to accelerate pushes"
    echo "  --no-build     Skip build and only push existing tags"
    echo "  --no-plugins   Skip installing Packer plugins (smaller image)"
    echo "  --no-collections  Skip installing Ansible collections (smaller image)"
    echo "  --platform <list>  Target platform(s) for build (default: linux/amd64). Example: linux/amd64,linux/arm64"
    echo "  --no-attest    Disable provenance/SBOM attestation to speed up buildx pushes"
    echo "  --single-tag   Push only the version tag (skip 'latest') to reduce push time"
    echo "  --offline       Build in offline mode (requires pre-downloaded artifacts)"
    echo "  --help, -h     Show this help message"
    echo
    echo "Environment Variables:"
    echo "  DOCKER_HUB_REGISTRY  Docker Hub registry (default: docker.io/degraafit)"
}

# Parse arguments
PUSH_TO_DOCKERHUB=false
OFFLINE_BUILD=false
FAST_PUSH=false
NO_BUILD=false
NO_PLUGINS=false
NO_COLLECTIONS=false
PLATFORMS="${PLATFORMS:-linux/amd64}"
NO_ATTEST=false
SINGLE_TAG=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --push|-p)
            PUSH_TO_DOCKERHUB=true
            shift
            ;;
        --fast-push)
            FAST_PUSH=true
            shift
            ;;
        --no-build)
            NO_BUILD=true
            shift
            ;;
        --offline)
            OFFLINE_BUILD=true
            shift
            ;;
        --no-plugins)
            NO_PLUGINS=true
            shift
            ;;
        --no-collections)
            NO_COLLECTIONS=true
            shift
            ;;
        --platform)
            shift
            if [[ -z "$1" ]]; then
                echo "--platform requires a value (e.g., linux/amd64 or linux/amd64,linux/arm64)"; exit 1
            fi
            PLATFORMS="$1"
            shift
            ;;
        --no-attest)
            NO_ATTEST=true
            shift
            ;;
        --single-tag)
            SINGLE_TAG=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

echo -e "${GREEN}Building Execution Environment: ${EE_NAME}:${VERSION}${NC}"

# Check if container runtime is available
if command -v podman &> /dev/null; then
    RUNTIME="podman"
elif command -v docker &> /dev/null; then
    RUNTIME="docker"
else
    echo "Neither podman nor docker found!"
    exit 1
fi

# Build the EE using custom Dockerfile
if [ "$NO_BUILD" != "true" ]; then
    echo "Building with ${RUNTIME} using custom Containerfile..."
    BUILD_ARGS="--build-arg OFFLINE_BUILD=${OFFLINE_BUILD}"
    if [ "$NO_PLUGINS" == "true" ]; then
        BUILD_ARGS+=" --build-arg INSTALL_PACKER_PLUGINS=false"
    fi
    if [ "$NO_COLLECTIONS" == "true" ]; then
        BUILD_ARGS+=" --build-arg INSTALL_COLLECTIONS=false"
    fi
        # Use buildx for cross-platform; push now if requested, otherwise load locally
        if command -v docker &>/dev/null; then
                docker buildx create --use >/dev/null 2>&1 || true
                TAG_ARGS=(-t "${DOCKER_HUB_REGISTRY}/${EE_NAME}:${VERSION}")
                if [ "$SINGLE_TAG" != "true" ]; then
                    TAG_ARGS+=( -t "${DOCKER_HUB_REGISTRY}/${EE_NAME}:latest" )
                fi
                ATTEST_ARGS=()
                if [ "$NO_ATTEST" == "true" ]; then
                    ATTEST_ARGS+=( --provenance=false --sbom=false )
                fi
                if [ "$PUSH_TO_DOCKERHUB" == "true" ]; then
                        docker buildx build \
                            $BUILD_ARGS \
                            -f Containerfile \
                            --platform "$PLATFORMS" \
                            "${TAG_ARGS[@]}" \
                            "${ATTEST_ARGS[@]}" \
                            --push \
                            .
                else
                        docker buildx build \
                            $BUILD_ARGS \
                            -f Containerfile \
                            --platform "$PLATFORMS" \
                            "${TAG_ARGS[@]}" \
                            --load \
                            .
                fi
        else
                # Fallback to runtime build (native platform only)
                $RUNTIME build \
                    $BUILD_ARGS \
                    -f Containerfile \
                    -t "${DOCKER_HUB_REGISTRY}/${EE_NAME}:${VERSION}" \
                    $( [ "$SINGLE_TAG" != "true" ] && echo -t "${DOCKER_HUB_REGISTRY}/${EE_NAME}:latest" ) \
                    .
        fi

    echo -e "${GREEN}Build completed successfully!${NC}"

    # Test the image
    echo "Testing the built image..."
    $RUNTIME run --rm --platform "$(echo "$PLATFORMS" | cut -d, -f1)" --user root --entrypoint "" "${DOCKER_HUB_REGISTRY}/${EE_NAME}:${VERSION}" ansible --version
    echo -e "${GREEN}Image tested successfully!${NC}"
else
    echo -e "${YELLOW}Skipping build as requested (--no-build).${NC}"
fi

# Push to Docker Hub if requested
if [ "$PUSH_TO_DOCKERHUB" == "true" ]; then
    echo -e "${BLUE}Pushing to Docker Hub...${NC}"
    # If we already pushed during buildx build, do nothing; else push now
    if ! command -v docker &>/dev/null; then
        echo "Pushing version ${VERSION}..."
        $RUNTIME push "${DOCKER_HUB_REGISTRY}/${EE_NAME}:${VERSION}"
        echo "Pushing latest tag..."
        $RUNTIME push "${DOCKER_HUB_REGISTRY}/${EE_NAME}:latest"
    else
        echo "Images were pushed during build. Skipping separate push."
    fi
    
    echo -e "${GREEN}Successfully pushed to Docker Hub!${NC}"
    echo -e "${BLUE}Your image is now available at:${NC}"
    echo "  ${DOCKER_HUB_REGISTRY}/${EE_NAME}:${VERSION}"
    echo "  ${DOCKER_HUB_REGISTRY}/${EE_NAME}:latest"
else
    echo
    echo -e "${BLUE}To push to Docker Hub, run:${NC}"
    echo "  ./build.sh --push"
fi

echo
echo -e "${BLUE}To use in AAP/Tower:${NC}"
echo "  Image: ${DOCKER_HUB_REGISTRY}/${EE_NAME}:${VERSION}"
