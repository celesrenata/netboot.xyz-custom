## netboot.xyz-custom

Please visit my other repository https://github.com/celesrenata/pfsense-ultimate-config for information on how to setup the DHCP options for NFS
Run the build script in the following order for debian
```sudo ./build-pxe-debian.sh kernel```
```Reboot```
```sudo ./build-pxe-debian.sh dracut```
It also has tasks for uploading just /etc
    * ```sudo ./build-pxe-debian.sh etc-update```
Or just cloning over all new files in case you struggle with updates or break it
    * ```sudo ./build-pxe-debian.sh```
