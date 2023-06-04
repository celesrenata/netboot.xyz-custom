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
echo "Run with 'etc-update' as the arg to quickly flash update your etc settings if they're broken."
echo "Run with 'cleanup' as the arg to clean up all old kernels made by this script. It will not delete the latest or the running kernels."
echo "Run with 'update' as the arg to update the kernel and initramfs after you successfully ran apt-get update && apt-get upgrade."
read -p "This will build the new pxe image, and will take a while, press 'enter' to continue..."
if [ "$1" == "cleanup" ]; then
  echo "cleaning up old script generated kernel directories"
  find /usr/src -type d -name "linux-source-*-custom*" | grep -v $(uname -r | awk -F "-custom-" '{ print $2 }') | grep -v $(cat /home/celes/build-pxe-resources/LATEST) | xargs -exec rm -rf {}
  exit 0
fi
if [ "$1" == "kernel" ] || [ "$1" == "update" ]; then
  echo "${timestamp}" > /home/$ACTUAL_USER/build-pxe-resources/LATEST
  echo "This will take a long while..."
  echo "Building Kernel..."
  apt-get install build-essential fakeroot module-assistant -y
  kernelverfull=$(apt-get install linux-source -y 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\-[0-9]+' | head -n 1)
  kernelversemi=$(echo ${kernelverfull} | awk -F '-' '{ print $1 }')
  rm -rf /usr/src/*.tar.gz
  kernelver=$(find /usr/src -type f -name "linux-source*.tar.xz" | sort | sed '$!d' | sed 's/\.tar\.xz//')
  tar xavf $(find /usr/src -type f -name "linux-source*.tar.xz" | sort | sed '$!d') --directory /usr/src
  rm -rf "${kernelver}-custom-${timestamp}"
  mv "${kernelver}" "/usr/src/${kernelversemi}-custom-${timestamp}"
  cd $(find /usr/src -type d -name "*${timestamp}*")
  make olddefconfig
  sed -i "s/CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-custom-${timestamp}\"/" .config
  sed -i "s/CONFIG_BUILD_SALT=.*/CONFIG_BUILD_SALT=\"-custom-${timestamp}\"/" .config
  patch -u .config -i /home/$ACTUAL_USER/build-pxe-resources/debian-kernel-conf.patch -f 2>&1 > /dev/null
  make -j$(nproc) deb-pkg 2>&1 > /home/$ACTUAL_USER/build-pxe-logs/kernel-${timestamp}.log
  if ! [ $? -eq 0 ]; then
    echo "Kernel build failed!"
    echo "Check /home/$ACTUAL_USER/build-pxe-logs/kernel-${timestamp}.log"
    exit 1
  else
    echo "Kernel build succeeded!"
  fi
  echo "Installing kernel"
  dpkg -i $(find /usr/src -type f -name "linux-headers-*-custom-*" | grep ${timestamp})
  dpkg -i $(find /usr/src -type f -name "linux-image-*-custom-*" | grep ${timestamp})
  cp arch/x86_64/boot/bzImage /home/$ACTUAL_USER/build-pxe-resources/bzImage-${timestamp}
fi
if [ "$1" == "kernel" ] || [ "$1" == "dracut" ] || [ "$1" == "update" ]; then
  modprobe squashfs
  if ! [ "$(cat /home/$ACTUAL_USER/build-pxe-resources/LATEST)" == "${timestamp}" ]; then
    timestamp=$(cat /home/$ACTUAL_USER/build-pxe-resources/LATEST)
    echo "recovering latest timestamp=${timestamp}"
  fi
  uname -r | grep -q ${timestamp} > /dev/null
  dracut --kver "${kernelversemi}-custom-${timestamp}" -m "nfs base dracut-systemd systemd-networkd systemd-initrd kernel-modules kernel-modules-extra kernel-network-modules" /home/$ACTUAL_USER/build-pxe-resources/initramfs-nfs-${timestamp} --force
  if ! [ $? -eq 0 ]; then
    echo "Building custom initramfs failed!"
    exit 1
  else
    echo "Building custom initramfs succeeded!"
    chmod +rw /home/$ACTUAL_USER/build-pxe-resources/initramfs-nfs-${timestamp}
  fi
fi
if ! [ "$1" == "etc-update" ] && ! [ "$1" == "update" ]; then
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
fi

if ! [ $? -eq 0 ] && ! [ "$1" == "update" ]; then
  echo "Cloning new bin/sbin/lib/usr/home folders has failed!"
  echo "Check /home/$ACTUAL_USER/build-pxe-logs/folders-${timestamp}.log"
  exit 1
else
  echo "Cloned!"
fi

if ! [ "$1" == "update" ]; then
  echo "Fixing annoying services"
  systemctl disable ModemManager
  systemctl add-wants multi-user.target rpcbind.service
  systemctl enable getty@tty1.service
  systemctl enable getty@tty2.service

  echo "Copying /etc"
  rm -rf /diskless/debian/etc
  mkdir -p /diskless/debian/etc/conf.d/
  cp -r /etc/* /diskless/debian/etc
  echo 'config_eth0="noop"' > /diskless/debian/etc/conf.d/net
  cp /home/$ACTUAL_USER/build-pxe-resources/fstab-debian /diskless/debian/etc/
  echo "Copied!"
fi

echo "Mounting NFS shares"
mkdir -p /mnt/{diskless,pxe}
if ! [ "$1" == "update" ]; then
  mount -t nfs 192.168.42.8:/volume2/diskless /mnt/diskless 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/mount-${timestamp}.log
  if ! [ $? -eq 0 ]; then
    echo "Mounting /mnt/diskless failed!"
    echo "Check /home/$ACTUAL_USER/build-pxe-logs/mount-${timestamp}.log"
    exit 1
  else
    echo "Mounted /mnt/diskless !"
  fi
fi

mount -t nfs 192.168.42.8:/volume2/pxe /mnt/pxe 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/mount-${timestamp}.log
if ! [ $? -eq 0 ]; then
  echo "Mounting /mnt/pxe failed!"
  echo "Check /home/$ACTUAL_USER/build-pxe-logs/mount-${timestamp}.log"
  exit 1
else
  echo "Mounted /mnt/pxe !"
fi

if ! [ "$1" == "etc-update" ] && ! [ "$1" == "update" ]; then
  echo "Copying directory structure"
  rsync -avz --delete /diskless/debian/* /mnt/diskless/debian/ 2>&1 > /home/$ACTUAL_USER/build-pxe-logs/structure-${timestamp}.log
  if ! [ $? -eq 0 ]; then
    echo "Copying structure failed!"
    echo "Check /home/$ACTUAL_USER/build-pxe-logs/structure-${timestamp}.log"
    exit 1
  else
    echo "Copied!"
  fi
fi

if ! [ "$1" == "etc-update" ]; then
  echo "Copying kernel and initramfs"
  rsync -avz $(ls /home/$ACTUAL_USER/build-pxe-resources/bzImage-* -1 | grep "${timestamp}") /mnt/pxe/assets/debian/vmlinuz 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/kernelcopy-${timestamp}.log
  rsync -avz $(ls /home/$ACTUAL_USER/build-pxe-resources/initramfs-nfs-* -1 | grep "${timestamp}") /mnt/pxe/assets/debian/initramfs-nfs 2>&1 >> /home/$ACTUAL_USER/build-pxe-logs/kernelcopy-${timestamp}.log
  chmod +r /mnt/pxe/assets/debian/vmlinuz
  chmod +r /mnt/pxe/assets/debian/initramfs-nfs
  if ! [ $? -eq 0 ]; then
    echo "Copying failed!"
    echo "Check /home/$ACTUAL_USER/build-pxe-logs/kernel-${timestamp}.log"
    exit 1
  else
    echo "Copied!"
  fi
fi

if [ "$1" == "etc-update" ]; then
  echo "Copying over JUST /etc"
  rsync -avz --delete /diskless/debian/etc/* /mnt/diskless/debian/etc/
fi

echo "Fixing NFSRoot permissions"
chmod +x /mnt/diskless
echo "If you cannot see your screen and cannot login as anything other than root, please run chmod +x / from the instance when it is running from root"

echo "Unmounting NFS shares"
umount /mnt/pxe
if ! [ "$1" == "update" ]; then
  umount /mnt/diskless
fi
echo "Done!"
