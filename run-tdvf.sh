#!/bin/env bash

###
# Run TDVF in qemu.
#
# usage: ./run-tdvf.sh [--build|--rebuild]
#
# --build simply runs build command again
# --rebuild deletes Build directory and then runs build command again
#
# This script expects to find the TDVF directory under ~/tdvfuzz/tdvf.
# For build/rebuild the EDK environment must be set up (i.e. source edksetup.sh).
###

### argline parsing
REBUILD=0
BUILD=0
if [[ "$#" -gt 0 ]]
then
  [[ "$1" = "--build" ]] && BUILD=1
  [[ "$1" = "--rebuild" ]] && REBUILD=1
fi

### verify environment
[[ -z $TDVF_ROOT ]] && fatal "Could not find TDVF_ROOT. Verify that kAFL environment is set up."
[[ -z $BKC_ROOT ]] && fatal "Could not find BKC_ROOT. Verify that kAFL environment is set up."


### rebuild TDVF

if [[ "$BUILD" -eq 1 || "$REBUILD" -eq 1 ]]
then
  pushd $TDVF_ROOT > /dev/null
  [[ "$REBUILD" -eq 1 ]] && (echo "deleting build dir" ; rm -rf Build)
  [[ -z "$WORKSPACE" || -z "$EDK_TOOLS_PATH" || -z "$CONF_PATH" ]] && source edksetup.sh
  echo "building tdvf"
  build -n $(nproc) -p OvmfPkg/IntelTdx/IntelTdxX64.dsc -t GCC5 -a X64 -D TDX_EMULATION_ENABLE=FALSE -D DEBUG_ON_SERIAL_PORT=TRUE || exit 1
  popd > /dev/null
fi


### prepare TDVF binary to run in fuzzer
echo "copying & linking TDVF image"
PREP_IMG_SCRIPT="$BKC_ROOT/scripts/prepare-tdvf.sh"
$PREP_IMG_SCRIPT


### run TDVF in fuzzer for a short time
echo "running fuzzer for 5s"
pushd $BKC_ROOT > /dev/null
timeout -s SIGINT 5s ./fuzz.sh run $LINUX_GUEST -p 1 --log-hprintf --log --debug
popd > /dev/null


### acquire fuzzer serial log
echo "copying log files"
LOG="$KAFL_WORKDIR/serial_00.log"
[[ -f $LOG ]] || fatal "log file $LOG does not exist"
cp $LOG ./



#! this does not produce the same results as runinng in fuzzer (probably because of qemu arguments) -> omit qemu run for now
### run TDVF in qemu
# TDVF_BUILD_DIR=$TDVF_ROOT/Build/IntelTdx/DEBUG_GCC5/FV
# TDVF_CODE=$TDVF_BUILD_DIR/OVMF_CODE.fd
# TDVF_VARS=$TDVF_BUILD_DIR/OVMF_VARS.fd
# MEM="1G"
# LOG="debug.log"

# QEMU=~/tdvfuzz/kafl/qemu/x86_64-softmmu/qemu-system-x86_64
# QEMU_FLAGS="-m $MEM -nographic \
# 	-enable-kvm \
# 	-machine kAFL64-v1 \
# 	-cpu kAFL64-Hypervisor-v1,+vmx \
# 	-drive if=pflash,format=raw,readonly,file=$TDVF_CODE \
# 	-drive if=pflash,format=raw,file=$TDVF_VARS \
#   -serial stdio \
# 	-nodefaults"

# NEW_FLAGS="-m $MEM -nographic \
# 	-enable-kvm \
#   -machine kAFL64-v1,confidential-guest-support=tdx0 \
#   -object tdx-guest,id=tdx0,[sept-ve-disable=off] \
# 	-drive if=pflash,format=raw,readonly,file=$TDVF_CODE \
# 	-drive if=pflash,format=raw,file=$TDVF_VARS \
#   -serial stdio \
# 	-nodefaults"

# # use timeout to stop qemu execution immediately when reaching UEFI shell
# timeout --foreground -s SIGINT 5s $QEMU $QEMU_FLAGS | tee "$LOG"