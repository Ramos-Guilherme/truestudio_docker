#!/bin/bash

################################################################################
# Copyright (c) 2018 STMicroelectronics Software AB.
# All rights reserved. This program and the accompanying materials
# is the property of STMicroelectronics Software AB and must not be
# reproduced, disclosed to any third party, or used in any
# unauthorized manner without written consent.
################################################################################

# File modified for personal use.
# This file installs TrueSTUDIO automatically (doesn't require user intervention)
# All content that was modified is tagged as '(modified)'

set -eu

configLocation=/etc/atollic
scriptPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
family=STM32
arch=x86_64
version=9.0.1
configFile=${configLocation}/TrueSTUDIO_for_${family}_${arch}_${version}.properties
installPath=/opt/Atollic_TrueSTUDIO_for_${family}_${arch}_${version}/

function acceptLicenseAgreement() {
  #(modified) accept license agreement automatically
        local accepted=true
        local ynr
        while [ ${accepted} == false ]; do
                echo "Do you accept the Atollic End User License Agreement?"
                select ynr in "Yes" "No" "Read"; do
                        case $ynr in
                                Yes)
                                        accepted=true
                                        break
                                        ;;
                                No)
                                        echo "Aborting installation."
                                        exit -1
                                        ;;
                                Read)
                                        less ${scriptPath}/license.txt
                                        break
                                        ;;
                        esac
                done
        done
}

function locateAndUnpackInstallation() {
  #(modified) Install to default path automatically
  local acceptedTarget=true
	local ync
	while [ ${acceptedTarget} == false ]; do
		echo "Do you want to install to '${installPath}'?"
		select ync in "Yes" "No" "Change"; do
			case $ync in
				Yes)
					acceptedTarget=true
					break
					;;
				No)
					echo "Aborting installation."
					exit -1
					;;
				Change)
					read -p "Enter new location: " installPath
					break
					;;
			esac
		done
	done

	echo "Extracting to '${installPath}'..."
	mkdir -p ${installPath}
	tar xzf ${scriptPath}/install.data -C ${installPath}
}

function installDeps() {
	local needs32="$1"
	local testCmd="$2"
	local libs32Cmd="$3"
	local lowPrioDepsCmd="$4"

	# Temporarily turn off e
	set +e

	# If the program exists, run the next commands
	eval "${testCmd}" > /dev/null 2>&1
	if [ $? -ne 127 ]; then
		if [ "${needs32}" == "true" ]; then
			eval "${libs32Cmd}"
			if [ $? -ne 0 ]; then
				echo "Failed to fix automatically 32-bit libraries, please install 32-bit libraries manually." 1>&2
				echo "Do you want to continue with the installation anyway? (yes/no) "
				select yn in "Yes" "No"; do
					case $yn in
						Yes)
							break
							;;
						No)
							echo "Aborting installation."
							exit -1
							;;
					esac
				done
			fi
		fi

		eval "${lowPrioDepsCmd}"
	fi

	# Activate e again
	set -e
}

function installUdevRule() {
	local src="$1"
	local dest="/etc/udev/rules.d/$2"

	cp "${src}" "${dest}"
	chown root: "${dest}"
	chmod 644 "${dest}"
}

function ensureDependencies() {
	# detect hardware platform
	local ARCH=`uname -m`
	case "$ARCH" in
	    x86_64)
		;;
	    i?86)
		;;
	    *)
		echo "Unsupported hardware platform." 1>&2
		echo "Aborting..." 1>&2
		exit 8
		;;
	esac

	echo "Installing dependencies..." 1>&2

	# Try for three different variants
	installDeps "true" "apt-get --help" "apt-get -y install libc6-i386 libusb-0.1-4" "apt-get -y install libwebkitgtk-3.0-0 libncurses5" ||
	installDeps "true" "yum --help" "yum -y install glibc.i686 libusb" "yum -y install webkitgtk3 ncurses-compat-libs"	||
	installDeps "true" "dnf --help" "dnf -y install glibc.i686 libusb" "dnf -y install webkitgtk3 ncurses-compat-libs"

	# Check again if we have succeeded
	if [ ! -e /lib/ld-linux.so.2 ]; then
		echo "Failed to fix 32-bit libraries." 1>&2
		echo "Please install 32-bit libraries manually, then run install.sh again." 1>&2
		exit -1
	fi
}

function registerInstallation() {
	mkdir -p ${configLocation}

	cat <<EOF > ${configFile}
# TrueSTUDIO for ${family} properties for version ${version}
path=${installPath}
family=${family}
arch=${arch}
version=${version}
EOF
}

function installSeggerJLink() {
	echo "Installing SEGGER J-Link"

	echo "Do you want to install the SEGGER J-Link udev rules to /etc/udev/rules.d/?"
	local yn
	select yn in "Yes" "No"; do
		case $yn in
			Yes)
				installUdevRule "${installPath}/Servers/J-Link_gdbserver/99-jlink.rules" 99-jlink.rules
				break
				;;
			No)
				echo "Skipping udev rules, you might need root permissions to debug with J-Link."
				break
				;;
		esac
	done
}

function installSTLink() {
	echo "Installing ST-Link"

	echo "Do you want to install the ST-Link udev rules to /etc/udev/rules.d/?"
	local yn
	select yn in "Yes" "No"; do
		case $yn in
			Yes)
				installUdevRule "${installPath}/Servers/ST-LINK_gdbserver/49-stlinkv2.rules" 49-stlinkv2.rules
				installUdevRule "${installPath}/Servers/ST-LINK_gdbserver/49-stlinkv2-1.rules" 49-stlinkv2-1.rules
				break
				;;
			No)
				echo "Skipping udev rules, you might need root permissions to debug with ST-Link."
				break
				;;
		esac
	done
}

function createDesktopShortcut() {
	local shortcutLocation="/usr/share/applications"
	local ideShortcut="${shortcutLocation}/TrueSTUDIO-for-${family}-${arch}-${version}.desktop"
	if [ -d "${shortcutLocation}" ]; then
		cat <<EOF > ${ideShortcut}
[Desktop Entry]
Name=Atollic TrueSTUDIO for ${family} ${version}
Comment=Atollic TrueSTUDIO for ${family} ${version}
GenericName=TrueSTUDIO
Exec=${installPath}/ide/TrueSTUDIO %F
Icon=${installPath}/ide/TrueSTUDIO.ico
Path=${installPath}/ide/
Terminal=false
StartupNotify=true
Type=Application
Categories=Development
EOF

	else
		echo "Warning, no desktop shortcut created. Please create one manually to '${installPath}/ide/TrueSTUDIO'."
	fi
}

function askCleanTemporaryFiles() {
	echo "Do you want to remove the temporary installation files from '${scriptPath}'?"
	local yn
	select yn in "Yes" "No"; do
		case $yn in
			Yes)
				rm -v ${scriptPath}/license.txt
				rm -v ${scriptPath}/install.data
				rm -v ${scriptPath}/install.sh
				rmdir -v ${scriptPath}
				break
				;;
			No)
				echo "Skipped removing temporary installation files."
				break
				;;
		esac
	done
}

# We need root unfortunately.
if [ "$(id -u)" != "0" ]; then
	echo "Installing TrueSTUDIO needs root permissions to complete all installation steps." 1>&2
	exit 1
fi

echo "Installing Atollic TrueSTUDIO for ${family} ${arch} ${version}..."

# Check for already existing installation
if [ -e ${configFile} ]; then
	echo "TrueSTUDIO for ${family} ${arch} ${version} is already installed. Please uninstall first."
	exit -1
fi

# License agreement
acceptLicenseAgreement

# Check and try to fix dependencies
ensureDependencies

# Select destination and unpack installation
locateAndUnpackInstallation

# Install GDB Servers
#(modified) Install stlinkv2
installUdevRule "${installPath}/Servers/ST-LINK_gdbserver/49-stlinkv2.rules" 49-stlinkv2.rules
installUdevRule "${installPath}/Servers/ST-LINK_gdbserver/49-stlinkv2-1.rules" 49-stlinkv2-1.rules
#installSTLink
#installSeggerJLink

# Write down installation information
registerInstallation

# Create desktop shortcut
createDesktopShortcut

# Ask for clean
#(modified) Remove installation files automatically
rm -v ${scriptPath}/license.txt
rm -v ${scriptPath}/install.data
rm -v ${scriptPath}/install.sh
rmdir -v ${scriptPath}
#askCleanTemporaryFiles

echo
echo "Installation of Atollic TrueSTUDIO for ${family} ${arch} ${version} has completed successfully."
