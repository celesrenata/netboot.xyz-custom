#!/bin/bash
ACTUAL_USER=$(logname)
mkdir -p build-pxe-logs
mkdir -p build-pxe-resources
timestamp=$(date '+%Y%m%d-%H%M%S')
if ! [ "$(whoami)" == "root" ] && [ "$ACTUAL_USER" == "root" ]; then
  echo "please run script with sudo, only!"
  exit 1
fi
echo "Run with 'kernel' as the arg to build the kernel, it will take literal hours to run."
echo "Run with 'dracut' as the arg to build the initramfs, it will take way less time if you haven't updated your kernel."
echo "Run with 'cleanup' as the arg to clean up all old kernels made by this script. It will not delete the latest or the running kernels."
read -p "This will build the new pxe image, and will take a while, press 'enter' to continue..."
if [ "$1" == "cleanup" ]; then
  echo "cleaning up old script generated kernel directories"
  find /usr/src -type d -name "linux-source-*-custom*" | grep -v $(uname -r | awk -F "-custom-" '{ print $2 }') | grep -v $(cat /home/celes/build-pxe-resources/LATEST) | xargs -exec rm -rf {}
  exit 0
fi
if [ "$1" == "kernel" ]; then
  echo "${timestamp}" > /home/$ACTUAL_USER/build-pxe-resources/LATEST
  echo "This will take a long while..."
  echo "Building Kernel..."
  rm -rf /usr/src/*.tar.gz
  kernelver=$(find /usr/src -type f -name "linux-source*.tar.xz" | sort | sed '$!d' | sed 's/\.tar\.xz//')
  tar xavf $(find /usr/src -type f -name "linux-source*.tar.xz" | sort | sed '$!d') --directory /usr/src
  mv ${kernelver} ${kernelver}-custom-${timestamp}
  cd $(find /usr/src -type d -name "linux-source*" | sort | sed '$!d')
  make olddefconfig
  sed "s/DRACUT-TIMESTAMP/-custom-${timestamp}/g" /home/$ACTUAL_USER/build-pxe-resources/debian-kernel-conf.patch > /home/$ACTUAL_USER/build-pxe-resources/debian-kernel-conf-${timestamp}.patch
  patch -u .config -i /home/$ACTUAL_USER/build-pxe-resources/debian-kernel-conf-${timestamp}.patch -f 2>&1 > /dev/null
  make -j$(nproc) deb-pkg 2>&1 > /home/$ACTUAL_USER/build-pxe-logs/kernel-${timestamp}.log
  if ! [ $? -eq 0 ]; then
    echo "Kernel build failed!"
    echo "Check /home/$ACTUAL_USER/build-pxe-logs/kernel-${timestamp}.log"
    exit 1
  else
    echo "Kernel build succeeded!"
  fi
  echo "Installing kernel"
  dpkg -i $(find /usr/src -type f -name "linux-headers-*-custom-${timestamp}_*")
  dpkg -i $(find /usr/src -type f -name "linux-image-*-custom-${timestamp}_*")
  cp arch/x86_64/boot/bzImage /home/$ACTUAL_USER/build-pxe-resources/bzImage-${timestamp}
fi
if [ "$1" == "kernel" ] || [ "$1" == "dracut" ]; then
  if ! [ "$(cat /home/$ACTUAL_USER/build-pxe-resources/LATEST)" == "${timestamp}" ]; then
    echo "recovering latest timestamp=${timestamp}"
    timestamp=$(cat /home/$ACTUAL_USER/build-pxe-resources/LATEST)
  fi
  uname -r | grep -q "custom-${timestamp}" > /dev/null
  if ! [ $? -eq 0 ]; then
    echo "You are not running the current kernel! you will need to reboot and rerun the script as 'sudo ./build-pxe-debian.sh dracut'"
    exit 1
  fi
  dracut -m "nfs base dracut-systemd systemd-networkd systemd-initrd kernel-modules kernel-modules-extra kernel-network-modules" /home/$ACTUAL_USER/build-pxe-resources/initramfs-nfs-${timestamp} --kver=$(uname -r) --force
  if ! [ $? -eq 0 ]; then
    echo "Building custom initramfs failed!"
    exit 1
  else
    echo "Building custom initramfs succeeded!"
    chmod +rw /home/$ACTUAL_USER/build-pxe-resources/initramfs-nfs-${timestamp}
  fi
fi
echo "Purging old /diskless/debian/(bin/sbin/lib/usr/home) Folders"
rm -rf /diskless/debian/{bin,sbin,lib,usr,home,var,lib64} 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/folders-${timestamp}.log
if ! [ $? -eq 0 ]; then
  echo "deleting old bin/sbin/lib directories has failed!"
  echo "Check /home/$ACTUAL_USER/build-pxe-logs/folders-${timestamp}.log"
  exit 1
else
  echo "Purged!"
fi
echo "Cloning new bin/sbin/lib/usr/home/var/lib64 folders"
mkdir -p /diskless/debian/{dev,proc,tmp,mnt,root,sys,opt}
mkdir -p /diskless/debian/mnt/.initd
chmod a+w /diskless/debian/tmp
mknod /diskless/debian/dev/console c 5 1
rsync -avz --delete /bin /diskless/debian/ 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /sbin /diskless/debian/ 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /lib /diskless/debian/ 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /usr /diskless/debian/ 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /home /diskless/debian/ 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /var /diskless/debian/ 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /lib64 /diskless/debian/ 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/folders-${timestamp}.log


if ! [ $? -eq 0 ]; then
  echo "Cloning new bin/sbin/lib/usr/home folders has failed!"
  echo "Check /home/$ACTUAL_USER/build-pxe-logs/folders-${timestamp}.log"
  exit 1
else
  echo "Cloned!"
fi

echo "Copying /etc"
rm -rf /diskless/debian/etc
mkdir -p /diskless/debian/etc/conf.d/
cp -r /etc/* /diskless/debian/etc
echo 'config_eth0="noop"' > /diskless/debian/etc/conf.d/net
echo "Copied!"

echo "Mounting NFS shares"
mkdir -p /mnt/{diskless,pxe}
mount -t nfs 192.168.42.8:/volume2/diskless /mnt/diskless 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/mount-${timestamp}.log
if ! [ $? -eq 0 ]; then
  echo "Mounting /diskless failed!"
  echo "Check /home/$ACTUAL_USER/build-pxe-logs/mount-${timestamp}.log"
  exit 1
else
  echo "Mounted /diskless !"
fi
mount -t nfs 192.168.42.8:/volume2/pxe /mnt/pxe 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/mount-${timestamp}.log
if ! [ $? -eq 0 ]; then
  echo "Mounting /pxe failed!"
  echo "Check /home/$ACTUAL_USER/build-pxe-logs/mount-${timestamp}.log"
  exit 1
else
  echo "Mounted /pxe !"
fi

echo "Copying directory structure"
rsync -avz --delete /diskless/debian/* /mnt/diskless/debian/ 2>&1 > /home/$ACTUAL_USER/build-pxe-logs/structure-${timestamp}.log
if ! [ $? -eq 0 ]; then
  echo "Copying structure failed!"
  echo "Check /home/$ACTUAL_USER/build-pxe-logs/structure-${timestamp}.log"
  exit 1
else
  echo "Copied!"
fi

echo "Copying kernel and initramfs"
rsync -avz $(ls /home/$ACTUAL_USER/build-pxe-resources/bzImage-* -1 | sed '$!d') /mnt/pxe/assets/debian/vmlinuz 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/kernelcopy-${timestamp}.log
rsync -avz $(ls /home/$ACTUAL_USER/build-pxe-resources/initramfs-nfs-* -1 | sed '$!d') /mnt/pxe/assets/debian/initramfs-nfs 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/kernelcopy-${timestamp}.log
chmod +r /mnt/pxe/assets/debian/vmlinuz
chmod +r /mnt/pxe/assets/debian/initramfs-nfs
if ! [ $? -eq 0 ]; then
  echo "Copying failed!"
  echo "Check /home/$ACTUAL_USER/build-pxe-logs/kernel-${timestamp}.log"
  exit 1
else
  echo "Copied!"
fi

echo "Unmounting NFS shares"
umount /mnt/pxe
umount /mnt/diskless
echo "Done!"