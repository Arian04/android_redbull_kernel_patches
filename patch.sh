#!/usr/bin/env zsh

# NOTES:
# - I'm `croot`ing at the top of every function just to be certain i'm where I expect to be

# Utility logging methods
_log() {
    local log_level=${1:?}
    local log_message=${2:?}
    echo "${log_level}: $log_message"
}
error() {
    _log "ERROR" "$@"
}
warn() {
    _log "WARN" "$@"
}
info() {
    _log "INFO" "$@"
}
debug() {
    _log "DEBUG" "$@"
}

build_boot_image() {
    croot

    mka bootimage

    info "built file should be at: ${OUT:?}/boot.img"

    return 0
}

# TODO: make idempotent
patch() {
    croot
    cd kernel/${DEVICE_VENDOR}/${DEVICE_KERNEL_NAME} || return 1

    KERNELSU_GIT_URL="https://github.com/tiann/KernelSU"
    KERNELSU_GIT_DIR=KernelSU
    KERNELSU_DRIVER_DIR=kernelsu

    # this is just so the build tools ignore the fact that the git tree is dirty
    # and don't append "-dirty" to the kernel name
    touch .scmversion

    git clone $KERNELSU_GIT_URL $KERNELSU_GIT_DIR

    # Apply my patches
    git apply "$SCRIPT_DIR/kernelsu-redbull.patch"

    return 0
}

sync_latest_files() {
    croot

    # Get latest files
    repo sync
    breakfast ${DEVICE_CODENAME}

    # If `breakfast` fails, extract proprietary blobs
    if [ $? != 0 ]; then
        info "Breakfast command failed, attempting to extract proprietary blobs in case those were missing"

        VENDOR_BLOB_DIR="device/$DEVICE_VENDOR/$DEVICE_CODENAME"
        cd $VENDOR_BLOB_DIR || {
            error "Failed to cd to device propriety blob directory: $VENDOR_BLOB_DIR"
            return 1
        }

        # TODO: MAKE SURE that you have an ADB connection to a rooted pixel 5 rn

        ./extract-files.sh

        croot
        breakfast redfin || {
            error "Breakfast failed even after extracting proprietary blobs :("
            return 3
        }
    fi

    return 0
}

setup_env() {
    cd ${LINEAGE_CODE_DIR} || {
        error "Failed to cd lineageos repo directory: $LINEAGE_CODE_DIR"
        return 1
    }

    source build/envsetup.sh

    return 0
}

preemptive_error_checking() {
    # ensure `kernelsu-redbull.patch` exists

    # exit early if we find some missing directories to avoid doing tons of work only to fail later
    #

    # Ensure we're in a nix shell
    [[ "$IN_NIX_SHELL" == "pure" ]] || {
        error "Script must be run inside pure nix-shell"
        return 2
    }

    return 0
}

main() {
    DEVICE_KERNEL_NAME=redbull
    DEVICE_CODENAME=redfin
    DEVICE_VENDOR=google
    LINEAGE_CODE_DIR=./lineage
    SCRIPT_DIR=$(readlink -f .)

    debug "preemptive_error_checking"
    preemptive_error_checking || exit

    debug "setup_env"
    setup_env

    debug "sync_latest_files"
    sync_latest_files

    debug "patch"
    patch

    debug "build_boot_image"
    build_boot_image
}

main "$@"
