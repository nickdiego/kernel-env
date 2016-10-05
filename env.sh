#!/bin/bash

basedir=$(readlink -f `dirname ${BASH_SOURCE}`)
srcdir=${basedir}/src/linux
patchdir=${basedir}/patches
builddir=${basedir}/build
bkpdir=${basedir}/bkp

sync-version() {
  local kernelurl_base='https://cdn.kernel.org/pub/linux/kernel/v4.x'
  local patchfile="${patchdir}/patch-${version}.patch"

  pushdir $srcdir
  # E.g: version=4.7.6 -> majorversion=4.7
  local majorversion=${version%.*}
  local curr_topcommit=$(git log --oneline -1 | awk '{ print $1 }')
  local expected_topcommit=$(git log v${majorversion} --oneline -1 | awk '{ print $1 }')
  if [[ $curr_topcommit != $expected_topcommit ]]; then
    # TODO reset to it automatically??
    echo "Error: First reset your git repo to 'v${majorversion}' tag"
    popdir && return 1
  fi

  if [ ! -r $patchfile ]; then
    echo "Downloading patch for version ${version}..."
    curl ${kernelurl_base}/patch-${version}.xz | xz -dc - > $patchfile
    check || return 1
  fi

  echo "Applying patch at ${patchfile}..."
  patch -p1 -i $patchfile
  check || return 1

  echo "Committing locally the changes..."
  git commit -am "Apply ${version} patch"
  check || return 1
  popdir
}

install() {
  local module=${1:-drivers/gpu/drm/i915}
  local koname=${module##*/}.ko
  local kopath="$module/$koname"
  local destdir=${module_install_dir}/kernel/$module

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
  pushdir $srcdir
  echo "Ok, Let's build module '$module'..."
  [ -d $builddir ] || mkdir -p $builddir

  echo Cleaning previos build...
  make O=${builddir} mrproper
  check || return 1

  echo -n Copying .config and Module.symvers...
  cp ${module_install_dir}/build/.config ${builddir} &&
  cp ${module_install_dir}/build/Module.symvers ${builddir}
  check || return 1

  echo "Executing 'make oldconfig'..."
  make O=${builddir} oldconfig
  check || return 1

  echo "Finally building '${module}'..."
  popdir && pushdir $builddir
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

## Getting some infos from the system

echo "==============================================="
echo 'Detecting installed version...'
pkgversion=$(pacman -Qi linux | grep "^Version" | awk '{ print $3}')
check || return 1

kernelarch_dir="${pkgversion}-ARCH"
module_install_dir="/usr/lib/modules/$kernelarch_dir"
version=${pkgversion%-*}

echo "Source dir: ${srcdir}"
echo "Build dir: ${builddir}"
echo "Installed linux package: ${pkgversion}"
echo "Linux Kernel version: ${version}"
echo "Modules install dir: ${module_install_dir}"
echo "==============================================="
