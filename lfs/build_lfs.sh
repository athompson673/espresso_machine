#!/usr/bin/env bash

# build lfs scritp from https://github.com/marcelstoer/docker-nodemcu-build/blob/master/lfs-image
# Copyright (c) 2015 Marcel Stör (MIT): https://github.com/marcelstoer/docker-nodemcu-build/blob/master/LICENSE

set -e

firmware_base=/mnt/c/Users/aaron/nodemcu-firmware
lua_base=$PWD

filelist=$1

cd ${firmware_base}

if [ ! -x luac.cross -a !  -x luac.cross.int ]; then
  echo Error: No cross compiler found. You need to build the firmeware first.
  exit -1
fi

export BUILD_DATE
BUILD_DATE="$(date "+%Y%m%d-%H%M")"

if [ -z "${filelist}" ]; then
  echo reading lua files from "${lua_base}"
  cd "${lua_base}"
  LUA_FILES=$(find . -iname "*.lua")
else
  DIR=$(dirname ${filelist})/
  NAME=$(basename ${filelist})

  cd "${lua_base}"/${DIR}

  LUA_FILES=$(cat ${NAME})
  LUA_FILES=$(ls ${LUA_FILES})
fi
echo Adding files: ${LUA_FILES}

if [ -z "$IMAGE_NAME" ]; then
  IMAGE_NAME="${BUILD_DATE}"
fi

function make_image {
  BUILD_TYPE=$1
  COMPILER=$2
  if [ -x ${firmware_base}/${COMPILER} ]; then
    FILENAME=${DIR}LFS_${BUILD_TYPE}_"${IMAGE_NAME}".img
    echo creating "${FILENAME}"
    if [ -z "${filelist}" ]; then 
      find "${lua_base}" -iname "*.lua" -exec ${firmware_base}/${COMPILER} -f -o "${lua_base}"/"${FILENAME}" {} +
    else
      ${firmware_base}/${COMPILER} -f -o "${lua_base}"/"${FILENAME}" ${LUA_FILES}
  fi
fi
}
# make a float LFS image if available
make_image float luac.cross
# make an int LFS image if available
make_image integer luac.cross.int