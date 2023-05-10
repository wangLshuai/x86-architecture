#! /bin/bash
if [ "$1" = "debug" ];then
    debug="-S -s"
fi
qemu-system-i386  -hda ./image.raw $debug