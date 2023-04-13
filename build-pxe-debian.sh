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
  cd $(find /usr/src -type d -name "linux-source*" | sort | sed '$!d')
  make olddefconfig
  sed -i "s/debian\/certs\/debian-uefi-certs.pem//g" .config
  patch -u .config -i /home/celes/build-pxe-resources/debian-kernel-conf.patch -f 2>&1 > /dev/null
  make deb-pkg LOCALVERSION=-custom 2>&1 > /home/celes/build-pxe-logs/kernel-${timestamp}.log
  if ! [ $? -eq 0 ]; then
    echo "Kernel build failed!"
    echo "Check /home/celes/build-pxe-logs/kernel-${timestamp}.log"
    exit 1
  else
    echo "Kernel build succeeded!"
  fi
  echo "Installing kernel"
  dpkg -i $(find /usr/src -type f -name "linux-headers-*-custom_*" | sort | sed '$!d')
  dpkg -i $(find /usr/src -type f -name "linux-image-*-custom_*" | sort | sed '$!d')
  cp arch/x86_64/boot/bzImage /home/celes/build-pxe-resources/bzImage-${timestamp}
fi
if [ "$1" == "kernel" ] || [ "$1" == "dracut" ]; then
  uname -r | grep -q "custom" > /dev/null
  if ! [ $? -eq 0 ]; then
    echo "You are not running the current kernel! you will need to reboot and rerun the script as 'sudo ./build-pxe-debian.sh dracut'"
    exit 1
  fi
  dracut -m "nfs base dracut-systemd systemd-networkd systemd-initrd" /home/celes/build-pxe-resources/initramfs-nfs-${timestamp} --kernel-image=$(find /boot -type f -name "vmlinuz-*-custom" | sort | sed '$!d') --force
  if ! [ $? -eq 0 ]; then
    echo "Building custom initramfs failed!"
    exit 1
  else
    echo "Building custom initramfs succeeded!"
  fi
fi
echo "Purging old /diskless/debian/(bin/sbin/lib/usr/home) Folders"
rm -rf /diskless/debian/{bin,sbin,lib,usr,home,var,lib64} 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
if ! [ $? -eq 0 ]; then
  echo "deleting old bin/sbin/lib directories has failed!"
  echo "Check /home/celes/build-pxe-logs/folders-${timestamp}.log"
  exit 1
else
  echo "Purged!"
fi
echo "Cloning new bin/sbin/lib/usr/home/var/lib64 folders"
mkdir -p /diskless/debian/{dev,proc,tmp,mnt,root,sys,opt}
mkdir -p /diskless/debian/mnt/.initd
chmod a+w /diskless/debian/tmp
mknod /diskless/debian/dev/console c 5 1
rsync -avz --delete /bin /diskless/debian/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /sbin /diskless/debian/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /lib /diskless/debian/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /usr /diskless/debian/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /home /diskless/debian/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /var /diskless/debian/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log
rsync -avz --delete /lib64 /diskless/debian/ 2>&1 >> /home/celes/build-pxe-logs/folders-${timestamp}.log


if ! [ $? -eq 0 ]; then
  echo "Cloning new bin/sbin/lib/usr/home folders has failed!"
  echo "Check /home/celes/build-pxe-logs/folders-${timestamp}.log"
  exit 1
else
  echo "Cloned!"
fi

echo "Copying /etc"
rm -rf /diskless/debian/etc
mkdir -p /diskless/debian/etc/conf.d/
cp -r /etc/* /diskless/debian/etc
cp /home/celes/build-pxe-resources/fstab /diskless/debian/etc/fstab
echo 'config_eth0="noop"' > /diskless/debian/etc/conf.d/net
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
rsync -avz --delete /diskless/debian/* /mnt/diskless/debian/ 2>&1 > /home/celes/build-pxe-logs/structure-${timestamp}.log
if ! [ $? -eq 0 ]; then
  echo "Copying structure failed!"
  echo "Check /home/celes/build-pxe-logs/structure-${timestamp}.log"
  exit 1
else
  echo "Copied!"
fi

echo "Copying kernel and initramfs"
rsync -avz $(ls /home/celes/build-pxe-resources/bzImage-* -1 | sed '$!d') /mnt/pxe/assets/debian/vmlinuz 2>&1 >> /home/celes/build-pxe-logs/kernelcopy-${timestamp}.log
rsync -avz $(ls /home/celes/build-pxe-resources/initramfs-nfs-* -1 | sed '$!d') /mnt/pxe/assets/debian/initramfs-nfs 2>&1 >> /home/celes/build-pxe-logs/kernelcopy-${timestamp}.log
chmod +r /mnt/pxe/assets/debian/vmlinuz
chmod +r /mnt/pxe/assets/debian/initramfs-nfs
if ! [ $? -eq 0 ]; then
  echo "Copying failed!"
  echo "Check /home/celes/build-pxe-logs/kernel-${timestamp}.log"
  exit 1
else
  echo "Copied!"
fi

echo "Pruning troublesome network services"
rm /mnt/diskless/debian/etc/systemd/system/multi-user.target.wants/{connman.service,dhcpcd.service,nordvpnd.service,ntpdate.service,systemd-networkd.service}
echo "Pruned!"

echo "Unmounting NFS shares"
umount /mnt/pxe
umount /mnt/diskless
echo "Done!"