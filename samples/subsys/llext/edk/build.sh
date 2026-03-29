#!/bin/bash

for dir in ext1 ext2 ext3 k-ext1 ; do
    pushd $dir

    if [ -d zigbuild ] ; then
        pushd zigbuild
        ./build.sh
        popd
    else
        rm -rf build
        cmake -B build
        make -C build
    fi
    popd
done
