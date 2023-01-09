#!/bin/bash

# A script for building EPICS container images
#
# Note that this is implemented in bash to make it portable between
# CI frameworks. This approach uses the minimum of GitHub Actions
# and also works locally for testing outside of CI.
#
# PREREQUISITES: the caller should be authenticated to the
# container registry with the appropriate permissions to push
#
# INPUTS:
#   PUSH: if true, push the container image to the registry
#   TAG: the tag to use for the container image
#   REPOSITORY: the container registry to push to
#

set -e

# Provide some defaults for the controlling Environment Variables.
PUSH=${PUSH:-false}
TAG=${TAG:-latest}
if [[ -z ${REPOSITORY} ]] ; then
    # For local builds, infer the registry from git remote (assumes ghcr)
    REPOSITORY=$(git remote -v | sed  "s/.*@github.com:\(.*\)\.git.*/ghcr.io\/\1/" | tail -1)
    echo "inferred registry ${REPOSITORY}"
fi

# support docker or podman (requires softlink docker->podman)
if docker -v | grep podman ; then
    # podman command line parameters
    cachefrom="--cache-from=${REPOSITORY}"
    cacheto="--cache-to=${REPOSITORY}"
else
    # setup a buildx driver for multi-arch / remote cached builds
    docker buildx create --driver docker-container --use
    docker buildx version
    # docker command line parameters
    cachefrom="--cache-from=type=registry,ref=${REPOSITORY}:buildcache --build-arg BUILDKIT_INLINE_CACHE=1"
    cacheto="--cache-to=type=registry,ref=${REPOSITORY}:buildcache,mode=max --build-arg BUILDKIT_INLINE_CACHE=1"
fi

do_build() {
    ARCHITECTURE=$1
    TARGET=$2
    shift 2

    image_name=${REPOSITORY}-${ARCHITECTURE}-${TARGET}:${TAG}
    args="
        --build-arg TARGET_ARCHITECTURE=${ARCHITECTURE}
        --target ${TARGET}
        -t ${image_name}
    "

    if [[ ${PUSH} == "true" ]] ; then
        args="--push "${args}
    fi

    echo "CONTAINER BUILD FOR ${image_name} with ARCHITECTURE=${ARCHITECTURE} ..."

    (
        set -x
        docker buildx build ${args} ${*} .
    )
}

# EDIT BELOW FOR YOUR BUILD MATRIX REQUIREMENTS
#
# All builds should use cachefrom and the last should use cacheto
# The last build should execute all stages for the cache to be fully useful.
#
# intermediate builds should use cachefrom but will also see the local cache
#
# If None of the builds use all stages in the Dockerfile then consider adding
# cache-to to more than one build. But note there is a tradeoff in performance
# as every layer will get uploaded to the cache even if it just came out of the
# cache.

do_build linux developer ${cachefrom}
do_build linux runtime ${cachefrom}
do_build rtems developer ${cachefrom}
do_build rtems runtime ${cachefrom} ${cacheto}

