#!/bin/bash
if [ "$(whoami)" != "root" ] ; then
	echo "Please run as root"
	echo "Quitting ..."
	exit 1
fi

# List all RTC time
#for RTC in $(ls /dev/rtc*); do echo "display $RTC time"; hwclock -r -f $RTC; done

function read_rtc_and_sys_time {
	echo "RTC Time: $(hwclock -r -f /dev/rtc)" && echo "System Time: $(date '+%Y-%m-%d %T')"
}

function sys_to_rtc {
	#hwclock --set --date='2025-01-01 00:02:00' -f /dev/rtc
	#hwclock --set --date "$(date '+%Y-%m-%d %T')" -f /dev/rtc
	hwclock -w -f /dev/rtc && echo "RTC updated from system time"
}

function rtc_to_sys {
	hwclock -s -f /dev/rtc && echo "System time updated from RTC"
}

function enable_rtc {
	# If the external rtc will be using, add its udev rule
	if [ $1 = "external" ]; then
		if [ -e /dev/rtc2 ]; then
			echo 'SUBSYSTEM=="rtc", KERNEL=="rtc2", SYMLINK="rtc", MODE="0666"' > 99-rtc2.rules
			mv 99-rtc2.rules /etc/udev/rules.d/
			udevadm control --reload-rules && udevadm trigger
		else
			echo "Unable to find external RTC (/dev/rtc2)"
			exit 1
		fi
	fi
	sleep 1

	# Check the RTC time is available
	if [[ $(hwclock -r -f /dev/rtc) ]]; then
		read_rtc_and_sys_time
	else
		echo "Unable to read RTC time. Trying to set the system time to it ($(date '+%Y-%m-%d %T'))"
		sys_to_rtc
		sleep 1

		if [[ $(hwclock -r -f /dev/rtc) ]]; then
			read_rtc_and_sys_time
		else
			echo "Unable to set system time. Check the RTC battery"
			exit 1
		fi
	fi

	# Disable NTP & update system time
	timedatectl set-ntp false && echo "Network time synchronization disabled"
	rtc_to_sys

	# If the external rtc will be using, add its "hwclock --hctosys" command
	if [ $1 = "external" ]; then
		if [ $(cat /etc/systemd/nv.sh | grep "hwclock -s -f /dev/rtc" | wc -l) -ne 0 ]; then
			echo "hwclock command already included in /etc/systemd/nv.sh"
		else
			cp -p /etc/systemd/nv.sh /etc/systemd/nv.sh.bak
			echo "hwclock -s -f /dev/rtc" >> /etc/systemd/nv.sh
			echo "hwclock command included in /etc/systemd/nv.sh"
		fi
	fi
}

function disable_rtc {
	# If the external rtc is using, remove its udev rule & hwclock command
	if [ -e /etc/udev/rules.d/99-rtc2.rules ]; then
		rm /etc/udev/rules.d/99-rtc2.rules
		udevadm control --reload-rules && udevadm trigger

		# Remove hwclock command in nv.sh file
		if [ -e /etc/systemd/nv.sh.bak ]; then
			if [ -e /etc/systemd/nv.sh ]; then
				mv /etc/systemd/nv.sh.bak /etc/systemd/nv.sh
				echo "hwclock command removed in /etc/systemd/nv.sh"
			else
				echo "Unable to find /etc/systemd/nv.sh"
				exit 1
			fi
		else
			echo "Unable to find /etc/systemd/nv.sh.bak"
			exit 1
		fi
	fi

	# Enable NTP
	timedatectl set-ntp true && echo "Network time synchronization enabled"
}

CONTINUE_FLAG=true
while $CONTINUE_FLAG; do
	CHOICE=0

	if [ $# -eq 1 ]; then
		CHOICE=$1
		CONTINUE_FLAG=false
	else
		echo ""
		echo "1) Enable Internal RTC"
		echo "2) Enable External RTC"
		echo "3) Disable RTC"
		echo "r) Read RTC & system time"
		echo "w) Write system time to RTC"
		echo "u) Update system time from RTC"
		echo "q) Quit"
		read -p "Type the selection [1/.../q]: " CHOICE
	fi

	case $CHOICE in
		1 ) 
			enable_rtc internal
			;;
		2 )
			enable_rtc external
			;;
		3 )
			disable_rtc
			;;
		[Rr]* )
			read_rtc_and_sys_time
			;;
		[Ww]* )
			sys_to_rtc
			;;
		[Uu]* )
			rtc_to_sys
			;;
		[Qq]* )
			echo "Quitting ..."
			CONTINUE_FLAG=false
			;;
		* )
			echo "Wrong choice"
			;;
	esac

done

echo "Done."

