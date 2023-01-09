#!/bin/env bash

###
# Run TDVF in qemu.
#
# usage: ./run-tdvf.sh [--build|--rebuild] [--qemu]
#
# --qemu      Run built TDVF image using Qemu instead of kAFL fuzzer
# --build     Simply execute build command again
# --rebuild   Delete Build directory and then execute build command
#
# This script expects to find the TDVF directory under ~/tdvfuzz/tdvf.
# For build/rebuild the EDK environment must be set up (i.e. source edksetup.sh).
###

LOGNAME="serial_tdvf.log"
RUNTIME="5s"

# build/rebuild TDVF image
function rebuild_tdvf()
{
  pushd $TDVF_ROOT > /dev/null
  [[ "$REBUILD" -eq 1 ]] && (echo "deleting build dir" ; rm -rf Build)
  [[ -z "$WORKSPACE" || -z "$EDK_TOOLS_PATH" || -z "$CONF_PATH" ]] && source edksetup.sh
  echo "building tdvf"
  build -n $(nproc) -p OvmfPkg/IntelTdx/IntelTdxX64.dsc -t GCC5 -a X64 -D TDX_EMULATION_ENABLE=FALSE -D DEBUG_ON_SERIAL_PORT=TRUE || exit 1
  popd > /dev/null
}

# run TDVF in fuzzer
function run_fuzzer()
{
  ### prepare TDVF binary to run in fuzzer
  echo "copying & linking TDVF image"
  PREP_IMG_SCRIPT="$BKC_ROOT/scripts/prepare-tdvf.sh"
  $PREP_IMG_SCRIPT

  ### run TDVF in fuzzer for a short time
  echo "running fuzzer for $RUNTIME"
  pushd $BKC_ROOT > /dev/null
  timeout -s SIGINT $RUNTIME ./fuzz.sh run $LINUX_GUEST -p 1 --log-hprintf --log --debug
  popd > /dev/null

  ### acquire fuzzer serial log
  echo "copying log files"
  LOG="$KAFL_WORKDIR/serial_00.log"
  [[ -f $LOG ]] || fatal "log file $LOG does not exist"
  cp $LOG "./$LOGNAME"
}

# run TDVF in qemu
#! this does not produce the same results as runinng in fuzzer (probably because of qemu arguments)
function run_qemu()
{
  TDVF_BUILD_DIR=$TDVF_ROOT/Build/IntelTdx/DEBUG_GCC5/FV
  TDVF_CODE=$TDVF_BUILD_DIR/OVMF_CODE.fd
  TDVF_VARS=$TDVF_BUILD_DIR/OVMF_VARS.fd
  MEM="1G"

  QEMU=$KAFL_ROOT/qemu/x86_64-softmmu/qemu-system-x86_64
  QEMU_FLAGS="-m $MEM -nographic \
    -enable-kvm \
    -machine kAFL64-v1 \
    -cpu kAFL64-Hypervisor-v1,+vmx \
    -drive if=pflash,format=raw,readonly,file=$TDVF_CODE \
    -drive if=pflash,format=raw,file=$TDVF_VARS \
    -serial stdio \
    -nodefaults"

  # NEW_FLAGS="-m $MEM -nographic \
  #   -enable-kvm \
  #   -machine kAFL64-v1,confidential-guest-support=tdx0 \
  #   -object tdx-guest,id=tdx0,[sept-ve-disable=off] \
  #   -drive if=pflash,format=raw,readonly,file=$TDVF_CODE \
  #   -drive if=pflash,format=raw,file=$TDVF_VARS \
  #   -serial stdio \
  #   -nodefaults"

  # use timeout to stop qemu execution immediately when reaching UEFI shell
  echo "running fuzzer for $RUNTIME"
  timeout --foreground -s SIGINT $RUNTIME $QEMU $QEMU_FLAGS | tee "$LOGNAME"
}

### argline parsing
REBUILD=0
BUILD=0
QEMU=0
if [[ "$#" -gt 0 ]]
then
  [[ "$1" = "--build" ]] && BUILD=1
  [[ "$1" = "--rebuild" ]] && REBUILD=1
  [[ $1 = "--qemu" || $2 = "--qemu" ]] && QEMU=1
fi

### verify environment
[[ -z $TDVF_ROOT ]] && fatal "Could not find TDVF_ROOT. Verify that kAFL environment is set up."
[[ -z $BKC_ROOT ]] && fatal "Could not find BKC_ROOT. Verify that kAFL environment is set up."
[[ -z $KAFL_ROOT ]] && fatal "Could not find KAFL_ROOT. Verify that kAFL environment is set up."

### rebuild TDVF if necessary
[[ "$BUILD" -eq 1 || "$REBUILD" -eq 1 ]] && rebuild_tdvf

### run TDVF either in qemu or Fuzzer
[[ $QEMU -eq 1 ]] && run_qemu || run_fuzzer