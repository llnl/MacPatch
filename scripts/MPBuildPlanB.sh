#!/bin/bash
#
# -------------------------------------------------------------
# Script: MPBuildPlanB.sh
# Version: 1.0
#
# Description: Script to build MacPatch PlanB pkg
#
# History:
#	1.0		Initial Script		
#
# -------------------------------------------------------------

SCRIPT_PARENT=$(dirname $(dirname $0))
SRCROOT="$SCRIPT_PARENT/Source"
PKGROOT="$SCRIPT_PARENT/Packages"
BUILDROOT=`mktemp -d /tmp/mpPlanB_XXXXXX` || exit 1
PKGVER="1.0.0"

PKGSIGNIDENTITY="*"
CODESIGNIDENTITY="*"
MIN_OS="10.10"

BUILDPLIST="/Library/Preferences/mp.build.client31.plist"
if [ -f "$BUILDPLIST" ]; then
	CODESIGNIDENTITYALT=`defaults read ${BUILDPLIST} name`
	PKGSIGNIDENTITYALT=`defaults read ${BUILDPLIST} pkgname`
fi

if [ -d "$BUILDROOT" ]; then
	rm -rf ${BUILDROOT}
else
	mkdir -p ${BUILDROOT}
fi

#statements
echo
echo "A valid code siginging identidy is required."
read -p "Would you like to code sign all binaries (Y/N)? [N]: " SIGNCODE
SIGNCODE=${SIGNCODE:-N}

if [ "$SIGNCODE" == "n" ] || [ "$SIGNCODE" == "N" ] || [ "$SIGNCODE" == "y" ] || [ "$SIGNCODE" == "Y" ]; then

	if [ "$SIGNCODE" == "y" ] || [ "$SIGNCODE" == "Y" ] ; then
		# Compile the agent components
		read -p "Please enter your code sigining identity [$CODESIGNIDENTITYALT]: " CODESIGNIDENTITY
		CODESIGNIDENTITY=${CODESIGNIDENTITY:-$CODESIGNIDENTITYALT}
		if [ "$CODESIGNIDENTITY" != "$CODESIGNIDENTITYALT" ]; then
			defaults write ${BUILDPLIST} name "${CODESIGNIDENTITY}"
		fi

		xcodebuild clean build -configuration Release -project ${SRCROOT}/Client/planb/planb.xcodeproj -target planb SYMROOT=${BUILDROOT} CODE_SIGN_IDENTITY="${CODESIGNIDENTITY}"
	else
		# Compile the agent components
		xcodebuild clean build -configuration Release -project ${SRCROOT}/Client/planb/planb.xcodeproj -target planb SYMROOT=${BUILDROOT}
	fi
else
	echo "Invalid entry, now exiting."
	exit 1
fi

# Remove the build and symbol files
find ${BUILDROOT} -name "*.build" -print | xargs -I{} rm -rf {}
find ${BUILDROOT} -name "*.dSYM" -print | xargs -I{} rm -rf {}

cp -R ${PKGROOT}/mpPlanB ${BUILDROOT}
cp ${BUILDROOT}/Release/planb ${BUILDROOT}/mpPlanB/Files/usr/local/sbin/
cp ${SRCROOT}/Client/planb/mpPlanB ${BUILDROOT}/mpPlanB/Files/usr/local/bin/
cp ${SRCROOT}/Client/planb/gov.llnl.mp.planb.plist ${BUILDROOT}/mpPlanB/Files/Library/LaunchDaemons/

# Find and remove .mpRM files, these are here as place holders so that GIT will keep the
# directory structure
find ${BUILDROOT} -name ".mpRM" -print | xargs -I{} rm -rf {}

# Remove the compiled Release directory now that all of the files have been copied
rm -r ${BUILDROOT}/Release

mkdir ${BUILDROOT}/Packages

echo
echo
read -p "Would you like to set the server address for PlanB, default is localhost. (Y/N)? [Y]: " MPPLANB_SRV
MPPLANB_SRV=${MPPLANB_SRV:-Y}
if [ "$MPPLANB_SRV" == "y" ] || [ "$MPPLANB_SRV" == "Y" ] ; then
	echo
	read -p "Server address: " MPPLANB_SRV_ADDR
	MPPLANB_SRV_ADDR=${MPPLANB_SRV_ADDR:-localhost}
	sed -i '' "s/MPSERVER=\"localhost\"/MPSERVER=\"${MPPLANB_SRV_ADDR}\"/g" "${BUILDROOT}/mpPlanB/Files/usr/local/bin/mpPlanB"
fi

echo
echo
read -p "Would you like to sign the package (Y/N)? [N]: " SIGNPKG
SIGNPKG=${SIGNPKG:-N}

if [ "$SIGNPKG" == "n" ] || [ "$SIGNPKG" == "N" ] || [ "$SIGNPKG" == "y" ] || [ "$SIGNPKG" == "Y" ]; then

	if [ "$SIGNPKG" == "y" ] || [ "$SIGNPKG" == "Y" ] ; then
		# Compile the agent components
		read -p "Please enter your installer sigining identity [$PKGSIGNIDENTITYALT]: " PKGSIGNIDENTITY
		PKGIGNIDENTITY=${PKGSIGNIDENTITY:-$PKGSIGNIDENTITYALT}
		if [ "$PKGSIGNIDENTITY" != "$PKGSIGNIDENTITYALT" ]; then
			defaults write ${BUILDPLIST} pkgname "${PKGSIGNIDENTITY}"
		fi
		pkgbuild --root ${BUILDROOT}/mpPlanB/Files \
		--identifier gov.llnl.mp.planb \
		--install-location / \
		--scripts ${BUILDROOT}/mpPlanB/Scripts \
		--version $PKGVER \
		--sign "${PKGSIGNIDENTITY}" \
		${BUILDROOT}/Packages/mpPlanB.pkg

	else
		pkgbuild --root ${BUILDROOT}/mpPlanB/Files \
		--identifier gov.llnl.mp.planb \
		--install-location / \
		--scripts ${BUILDROOT}/mpPlanB/Scripts \
		--version $PKGVER \
		${BUILDROOT}/Packages/mpPlanB.pkg
	fi
else
	echo "Invalid entry, now exiting."
	exit 1
fi

echo
echo "New Client is located in $BUILDROOT"
open ${BUILDROOT}
