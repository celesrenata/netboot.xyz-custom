#!/bin/sh

mount | grep -e '^sysroot' > /dev/null
if [ $? -eq 0 ]; then
   exit 0
fi

NFS_DATA=$(cat /proc/cmdline | awk -F "root=" '{ print $2 }' | awk -F "nfs4:" '{ print $2 }' | sed 's/,/:/1')
NFS_MOUNT=$(echo ${NFS_DATA} | awk -F ":" '{ print $1 ":" $2 }')
NFS_OPTIONS=$(echo ${NFS_DATA} | awk -F ":" '{ print $NF }')
mount -t nfs4 ${NFS_MOUNT} -o ${NFS_OPTIONS} /sysroot
if [ $? -ne 0 ]; then
   exit 1
fi
