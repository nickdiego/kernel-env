#!/bin/bash

basedir=$(readlink -f `dirname ${BASH_SOURCE}`)
version='4.7.5-1-ARCH' #`uname -r`
builddir=${basedir}/build-modules
bkpdir=${basedir}/bkp

install() {
  local module=${1:-drivers/gpu/drm/i915}
  local koname=${module##*/}.ko
  local kopath="$module/$koname"
  local destdir=/usr/lib/modules/${version}/kernel/$module

  pushdir $builddir
  echo "Installing module '$module'..."
  if [[ ! -f $kopath && ! -f ${kopath}.gz ]]; then
    echo "Error: file '$kopath' not found. You built it? o.O"
    popdir && return 1
  fi

  local bkpfile="$bkpdir/${koname%.*}_$(date +'%F-%N').ko.gz"
  echo "Saving installed version in $bkpfile"
  test -d $bkpdir || mkdir -p $bkpdir
  cp $destdir/${koname}.gz $bkpfile
  check || return 1

  echo "Finally installing ${kopath}.gz"
  test -f ${kopath}.gz || gzip $kopath &&
  sudo cp -f ${kopath}.gz $destdir
  check || return 1
  popdir
}

build() {
  local module=${1:-drivers/gpu/drm/i915}

  echo "Ok, Let's build module '$module'..."

  pushdir $builddir
  echo Cleaning previos build...
  make mrproper
  check || return 1

  echo -n Copying .config and Module.symvers...
  cp /usr/lib/modules/$version/build/.config ./ &&
  cp /usr/lib/modules/$version/build/Module.symvers ./
  check || return 1

  echo "Executing 'make oldconfig'..."
  make oldconfig
  check || return 1

  echo "Finally building '${module}'..."
  make prepare && make scripts && make M=${module}
  check || return 1

  popdir
}

check() {
  if [[ $? -ne 0 ]]; then
    echo Failed. Exiting...
    popdir && return 1
  fi
}

pushdir() {
  if [[ -n $1 ]]; then
    echo "Entering in directory '$1'"
    pushd $1 >/dev/null
  else
    return 1
  fi
}

popdir() {
  popd $1 >/dev/null
  local r=$?
  [[ $r -eq 0 ]] && echo "We're back to directory '$PWD'"
  return $r
}
