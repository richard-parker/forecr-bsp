#!/bin/bash
if [ "$(whoami)" != "root" ] ; then
        echo "Please run as root"
        echo "Quitting ..."
        exit 1
fi

# Replace base DTB files
mv tegra234-p3768-0000+p3767-0000-nv.dtb Linux_for_Tegra/kernel/dtb/
mv tegra234-p3768-0000+p3767-0000-nv-super.dtb Linux_for_Tegra/kernel/dtb/
mv tegra234-p3768-0000+p3767-0001-nv.dtb Linux_for_Tegra/kernel/dtb/
mv tegra234-p3768-0000+p3767-0001-nv-super.dtb Linux_for_Tegra/kernel/dtb/
cp tegra234-p3767-camera-dsboard-ornx-imx219.dtbo Linux_for_Tegra/rootfs/boot/
cp tegra234-p3767-camera-dsboard-ornx-imx477.dtbo Linux_for_Tegra/rootfs/boot/
mv tegra234-p3767-camera-dsboard-ornx-imx219.dtbo Linux_for_Tegra/kernel/dtb/
mv tegra234-p3767-camera-dsboard-ornx-imx477.dtbo Linux_for_Tegra/kernel/dtb/

# Replace kernel Image
mv Image Linux_for_Tegra/kernel/Image
mv kernel_supplements.tbz2 Linux_for_Tegra/kernel/

# Replace pinmux files
mv tegra234-mb1-bct-pinmux-p3767-dp-a03.dtsi Linux_for_Tegra/bootloader/generic/BCT/
mv tegra234-mb1-bct-gpio-p3767-dp-a03.dtsi Linux_for_Tegra/bootloader/

# Include RTC configuartion tool
mv rtc_config_tool.sh Linux_for_Tegra/rootfs/usr/local/bin/

# Apply the system config
sed -i "s/cvb_eeprom_read_size = <0x100>;/cvb_eeprom_read_size = <0x0>;/g" Linux_for_Tegra/bootloader/generic/BCT/tegra234-mb2-bct-misc-p3767-0000.dts
sed -i "s/ODMDATA=\"gbe-uphy-config-8,hsstp-lane-map-3,hsio-uphy-config-0\";/ODMDATA=\"gbe-uphy-config-9,hsstp-lane-map-3,hsio-uphy-config-0\";/g" Linux_for_Tegra/p3767.conf.common
sed -i "s/OVERLAY_DTB_FILE+=\",tegra234-p3768-0000+p3767-0000-dynamic.dtbo\";/OVERLAY_DTB_FILE+=\",tegra234-p3768-0000+p3767-0000-dynamic.dtbo,tegra234-dcb-p3767-0000-hdmi.dtbo\";\nDCE_OVERLAY_DTB_FILE=\"tegra234-dcb-p3767-0000-hdmi.dtbo\";/g" Linux_for_Tegra/p3768-0000-p3767-0000-a0.conf

#cat Linux_for_Tegra/bootloader/generic/BCT/tegra234-mb2-bct-misc-p3767-0000.dts | grep eeprom
#cat Linux_for_Tegra/p3767.conf.common | grep ODMDATA
#cat Linux_for_Tegra/p3768-0000-p3767-0000-a0.conf | grep OVERLAY_DTB_FILE
#cat Linux_for_Tegra/jetson-orin-nano-devkit.conf | grep OVERLAY_DTB_FILE

cd Linux_for_Tegra/rootfs/
sudo tar -jxf ../kernel/kernel_supplements.tbz2 
sync
cd $OLDPWD

echo "Done."

