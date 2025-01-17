#!/bin/bash
mkdir -p build-pxe-logs
mkdir -p build-pxe-resources
timestamp=$(date '+%Y%m%d-%H%M%S')
if ! [ "$(whoami)" == "root" ]; then
  echo "please run script with sudo!"
  exit 1
fi
echo "Run with 'kernel' as the arg to build the kernel, it will take literal hours to run."
read -p "This will build the new pxe image, and will take a while, press 'enter' to continue..."

if [ "$1" == "kernel" ]; then
  echo "This will take a long while..."
  echo "Building Kernel..."
  genkernel --no-install --menuconfig all
  cp /var/tmp/genkernel/kernel-x86_64-6.1.19-gentoo-x86_64 /home/celes/build-pxe-resources/bzImage-${timestamp}
  cp /var/tmp/genkernel/initramfs-x86_64-6.1.19-gentoo-x86_64 /home/celes/build-pxe-resources/initramfs-${timestamp}
  if ! [ $? -eq 0 ]; then
    echo "Kernel build failed!"
    echo "Check /home/celes/build-pxe-logs/kernel-${timestamp}.log"
    exit 1
  else
    echo "Kernel build succeeded!"
  fi
  dracut -m "nfs network base dracut-systemd" /home/celes/build-pxe-resources/initramfs-nfs-${timestamp} --force
  if ! [ $? -eq 0 ]; then
    echo "Building custom initramfs failed!"
    exit 1
  else
    echo "Building custom initramfs succeeded!"
  fi
fi
echo "Purging old /diskless/gentoo/(bin/sbin/lib/usr/home) Folders"
rm -rf /diskless/gentoo/{bin,sbin,lib,usr,home,var,lib64} 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
if ! [ $? -eq 0 ]; then
  echo "deleting old bin/sbin/lib directories has failed!"
  echo "Check /home/celes/build-pxe-logs/folders-${timestamp}.log"
  exit 1
else
  echo "Purged!"
fi
echo "Cloning new bin/sbin/lib/usr/home/var/lib64 folders"
mkdir -p /diskless/gentoo/{dev,proc,tmp,mnt,root,sys,opt}
mkdir -p /diskless/gentoo/mnt/.initd
chmod a+w /diskless/gentoo/tmp
mknod /diskless/gentoo/dev/console c 5 1
rsync -avz --delete /bin /diskless/gentoo/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /sbin /diskless/gentoo/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /lib /diskless/gentoo/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /usr /diskless/gentoo/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /home /diskless/gentoo/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /var /diskless/gentoo/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /lib64 /diskless/gentoo/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log


if ! [ $? -eq 0 ]; then
  echo "Cloning new bin/sbin/lib/usr/home folders has failed!"
  echo "Check /home/celes/build-pxe-logs/folders-${timestamp}.log"
  exit 1
else
  echo "Cloned!"
fi

echo "Copying /etc"
rm -rf /diskless/gentoo/etc
mkdir -p /diskless/gentoo/etc/conf.d/
cp -r /etc/* /diskless/gentoo/etc
cp /home/celes/build-pxe-resources/initramfs.mounts /diskless/gentoo/etc/
cp /home/celes/build-pxe-resources/fstab-gentoo /diskless/gentoo/etc/fstab
echo 'config_eth0="noop"' > /diskless/gentoo/etc/conf.d/net
echo "Copied!"

echo "Mounting NFS shares"
mkdir -p /mnt/{diskless,pxe}
mount -t nfs 192.168.42.8:/volume2/diskless /mnt/diskless 2>&1 >> /home/celes/build-pxe-logs/mount-${timestamp}.log
if ! [ $? -eq 0 ]; then
  echo "Mounting /diskless failed!"
  echo "Check /home/celes/build-pxe-logs/mount-${timestamp}.log"
  exit 1
else
  echo "Mounted /diskless !"
fi
mount -t nfs 192.168.42.8:/volume2/pxe /mnt/pxe 2>&1 >> /home/celes/build-pxe-logs/mount-${timestamp}.log
if ! [ $? -eq 0 ]; then
  echo "Mounting /pxe failed!"
  echo "Check /home/celes/build-pxe-logs/mount-${timestamp}.log"
  exit 1
else
  echo "Mounted /pxe !"
fi

echo "Copying directory structure"
rsync -avz --delete /diskless/gentoo/* /mnt/diskless/gentoo/ 2>&1 > /home/celes/build-pxe-logs/structure-${timestamp}.log
if ! [ $? -eq 0 ]; then
  echo "Copying structure failed!"
  echo "Check /home/celes/build-pxe-logs/structure-${timestamp}.log"
  exit 1
else
  echo "Copied!"
fi

echo "Copying kernel and initramfs"
rsync -avz $(ls /home/celes/build-pxe-resources/bzImage-* -1 | sed '$!d') /mnt/pxe/assets/Gentoo/vmlinuz 2>&1 >> /home/celes/build-pxe-logs/kernelcopy-${timestamp}.log
rsync -avz $(ls /home/celes/build-pxe-resources/initramfs-nfs-* -1 | sed '$!d') /mnt/pxe/assets/Gentoo/initramfs-nfs 2>&1 >> /home/celes/build-pxe-logs/kernelcopy-${timestamp}.log
chmod +r /mnt/pxe/assets/Gentoo/vmlinuz
chmod +r /mnt/pxe/assets/Gentoo/initramfs-nfs
if ! [ $? -eq 0 ]; then
  echo "Copying failed!"
  echo "Check /home/celes/build-pxe-logs/kernel-${timestamp}.log"
  exit 1
else
  echo "Copied!"
fi

echo "Pruning troublesome network services"
rm /mnt/diskless/gentoo/etc/systemd/system/multi-user.target.wants/{connman.service,dhcpcd.service,nordvpnd.service,ntpdate.service,systemd-networkd.service}
echo "Pruned!"

echo "Unmounting NFS shares"
umount /mnt/pxe
umount /mnt/diskless
echo "Done!"


