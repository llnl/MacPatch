#!/bin/bash
#
# -------------------------------------------------------------
# Script: MPBuildClient.sh
# Version: 1.4
#
# Description:
# This is a very simple script to demonstrate how to automate
# the build process of the MacPatch Agent.
#
# History:
#	1.1		Added Code Signbing Support
#   1.2		Added ability to save CODESIGNIDENTITY
#   1.4		Script No Longer is static location
#
# -------------------------------------------------------------

SCRIPT_PARENT=$(dirname $(dirname $0))
SRCROOT="$SCRIPT_PARENT/Source"
PKGROOT="$SCRIPT_PARENT/Packages"
BUILDROOT="/private/tmp/MP/Client"
BASEPKGVER="3.0.1.0"
UPDTPKGVER="3.0.1.0"
PKG_STATE=""
CODESIGNIDENTITY="*"
MIN_OS="10.8"
BUILDPLIST="/Library/Preferences/mp.build.client.plist"
if [ -f "$BUILDPLIST" ]; then
	CODESIGNIDENTITYALT=`defaults read ${BUILDPLIST} name`
fi

if [ -d "$BUILDROOT" ]; then
	rm -rf ${BUILDROOT}
else
	mkdir -p ${BUILDROOT}	
fi	

# Set Client Version
AGENT_VERS="1.0.0"
if [ -f "$BUILDPLIST" ]; then
	AGENT_VERS=`defaults read ${BUILDPLIST} client_version`
	if (($? > 0)); then
		AGENT_VERS="1.0.0"
	fi
fi
echo
echo " - Set overall MacPatch Client version ( e.g. 2.9.0 ) "
read -p "Set MacPatch Client version [$AGENT_VERS]: " AGENT_VER
AGENT_VER=${AGENT_VER:-$AGENT_VERS}

# Set Client Build Number
AGENT_BUILDS="1"
if [ -f "$BUILDPLIST" ]; then
	AGENT_BUILDS=`defaults read ${BUILDPLIST} client_build`
	if (($? > 0)); then
		AGENT_BUILDS=1
	fi
fi
echo
echo " - Set overall MacPatch Client build number "
echo " use \"i\" to increment or type in a number "
read -p "Set MacPatch Client build number (current $AGENT_BUILDS),  [i]: " AGENT_BUILD
AGENT_BUILD=${AGENT_BUILD:-$AGENT_BUILDS}

BUILD_NO=0
if [ "$AGENT_BUILD" == "i" ] || [ "$AGENT_BUILD" == "I" ]; then
	let "BUILD_NO=AGENT_BUILDS+1"
else
	BUILD_NO=$AGENT_BUILD
fi

re='^[0-9]+$'
if ! [[ $BUILD_NO =~ $re ]] ; then
   echo "Error: Build number is not a number" >&2; exit 1
fi

# Set Min OS Version
MIN_OS_VAR=$MIN_OS
if [ -f "$BUILDPLIST" ]; then
	MIN_OS_VAR=`defaults read ${BUILDPLIST} min_os`
	if (($? > 0)); then
		MIN_OS_VAR=$MIN_OS
	fi
fi
echo
echo " - Set overall MacPatch Client minimum os version "
read -p "Set MacPatch Client minimum os version [$MIN_OS_VAR]: " MIN_OS_VARS
MIN_OS=${MIN_OS_VARS:-$MIN_OS_VAR}

# MacPatch Client Release Level
echo
read -p "Please choose the desired state (R[elease]/B[eta]/A[lpha])? [R]: " PKGSTATE
PKGSTATE=${PKGSTATE:-R}
if [ "$PKGSTATE" == "b" ] || [ "$PKGSTATE" == "B" ]; then
	PKG_STATE="- (Beta)"
elif [ "$PKGSTATE" == "a" ] || [ "$PKGSTATE" == "A" ]; then
	PKG_STATE="- (Alpha)"
else
	echo "Setting Package desired state to \"Release\""
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
		
		#if [ "${CODESIGNIDENTITY}" == "*" ]; then
		#	read -p "Please enter you code sigining identity: " CODESIGNIDENTITY
		#fi
		xcodebuild clean build -configuration Release -project ${SRCROOT}/MacPatch/MacPatch.xcodeproj -target AGENT_BUILD SYMROOT=${BUILDROOT} CODE_SIGN_IDENTITY="${CODESIGNIDENTITY}"
	else
		# Compile the agent components
		xcodebuild clean build -configuration Release -project ${SRCROOT}/MacPatch/MacPatch.xcodeproj -target AGENT_BUILD SYMROOT=${BUILDROOT}
	fi
else
	echo "Invalid entry, now exiting."
	exit 1
fi

# Remove the build and symbol files
find ${BUILDROOT} -name "*.build" -print | xargs -I{} rm -rf {}
find ${BUILDROOT} -name "*.dSYM" -print | xargs -I{} rm -rf {}

# Remove the static library and header files
rm ${BUILDROOT}/Release/libMacPatch.a
rm ${BUILDROOT}/Release/libcrypto.a
rm ${BUILDROOT}/Release/libssl.a
rm -r ${BUILDROOT}/Release/usr

cp -R ${PKGROOT}/Base ${BUILDROOT}
cp -R ${PKGROOT}/Updater ${BUILDROOT}
cp -R ${PKGROOT}/Combined ${BUILDROOT}

mv ${BUILDROOT}/Release/ccusr ${BUILDROOT}/Base/Scripts/ccusr
mv ${BUILDROOT}/Release/MPPrefMigrate ${BUILDROOT}/Base/Scripts/MPPrefMigrate
mv ${BUILDROOT}/Release/MPAgentUp2Date ${BUILDROOT}/Updater/Files/Library/MacPatch/Updater/
mv ${BUILDROOT}/Release/MPLoginAgent.app ${BUILDROOT}/Base/Files/Library/PrivilegedHelperTools/
cp -R ${BUILDROOT}/Release/* ${BUILDROOT}/Base/Files/Library/MacPatch/Client/

# Get Versions
agent_ver=`${BUILDROOT}/Base/Files/Library/MacPatch/Client/MPAgent -v`
update_ver=`${BUILDROOT}/Updater/Files/Library/MacPatch/Updater/MPAgentUp2Date -v`

# Agent
# @AGENTVER@
sed -i '' "s/@AGENTVER@/$agent_ver/g" "${BUILDROOT}/Combined/Resources/mpInfo.ini"
sed -i '' "s/@AGENTVER@/$agent_ver/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @APPVER@
sed -i '' "s/@APPVER@/$AGENT_VER/g" "${BUILDROOT}/Combined/Resources/mpInfo.ini"
sed -i '' "s/@APPVER@/$AGENT_VER/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @AMINOS@
sed -i '' "s/@AMINOS@/$MIN_OS/g" "${BUILDROOT}/Combined/Resources/mpInfo.ini"
sed -i '' "s/@AMINOS@/$MIN_OS/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @ABUILD@
sed -i '' "s/@ABUILD@/$BUILD_NO/g" "${BUILDROOT}/Combined/Resources/mpInfo.ini"
sed -i '' "s/@ABUILD@/$BUILD_NO/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"

# Updater
# @UPDATEVER@
sed -i '' "s/@UPDATEVER@/$update_ver/g" "${BUILDROOT}/Combined/Resources/mpInfo.ini"
sed -i '' "s/@UPDATEVER@/$update_ver/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @APPVER@
sed -i '' "s/@APPVER@/$AGENT_VER/g" "${BUILDROOT}/Combined/Resources/mpInfo.ini"
sed -i '' "s/@APPVER@/$AGENT_VER/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @UMINOS@
sed -i '' "s/@UMINOS@/$MIN_OS/g" "${BUILDROOT}/Combined/Resources/mpInfo.ini"
sed -i '' "s/@UMINOS@/$MIN_OS/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"
# @UBUILD@
sed -i '' "s/@UBUILD@/$BUILD_NO/g" "${BUILDROOT}/Combined/Resources/mpInfo.ini"
sed -i '' "s/@UBUILD@/$BUILD_NO/g" "${BUILDROOT}/Combined/Resources/mpInfo.plist"


# Find and remove .mpRM files, these are here as place holders so that GIT will keep the
# directory structure
find ${BUILDROOT} -name ".mpRM" -print | xargs -I{} rm -rf {}

# Remove the compiled Release directory now that all of the files have been copied
rm -r ${BUILDROOT}/Release

mkdir ${BUILDROOT}/Combined/Packages

# Add Config Profiles
echo
read -p "Would you like to add config profiles to install? [Y/N])? [N]: " CPROFILE
CPROFILE=${CPROFILE:-N}
if [ "$CPROFILE" == "y" ] || [ "$CPROFILE" == "Y" ]; then
	echo
	read -p "Please specify directory to profiles to be installed: " CPROFILEDIR
	echo "DIR: $CPROFILEDIR"
	if [ -d "$CPROFILEDIR" ]; then 
		mkdir -p ${BUILDROOT}/Base/Scripts/profiles
		cp "$CPROFILEDIR"/*.mobileconfig ${BUILDROOT}/Base/Scripts/profiles
		open ${BUILDROOT}
	fi
fi

# Create the Base Agent pkg
pkgbuild --root ${BUILDROOT}/Base/Files/Library \
--component-plist ${BUILDROOT}/Base/Components.plist \
--identifier gov.llnl.mp.agent.base \
--install-location /Library \
--scripts ${BUILDROOT}/Base/Scripts \
--version $BASEPKGVER \
${BUILDROOT}/Combined/Packages/Base.pkg

# Create the Updater pkg
pkgbuild --root ${BUILDROOT}/Updater/Files/Library \
--identifier gov.llnl.mp.agent.updater \
--install-location /Library \
--scripts ${BUILDROOT}/Updater/Scripts \
--version $UPDTPKGVER \
${BUILDROOT}/Combined/Packages/Updater.pkg


BUILD_NO_STR=`date +%Y%m%d-%H%M%S`
sed -i '' "s/\[BUILD_NO\]/$BUILD_NO_STR/g" "${BUILDROOT}/Combined/Resources/Welcome.rtf"
sed -i '' "s/\[STATE\]/$PKG_STATE/g" "${BUILDROOT}/Combined/Resources/Welcome.rtf"

BUILD_FILE="${BUILDROOT}/Combined/MP-$BASEPKGVER-$BUILD_NO_STR$PKG_STATE"
echo "MP-$BASEPKGVER-$BUILD_NO_STR$PKG_STATE" > "${BUILD_FILE}"

#mkdir -p ${BUILDROOT}/Combined/PKGPlugins
#open ${BUILDROOT}/Combined/PKGPlugins
#sleep 20

# Create the almost final package
# --plugins ${BUILDROOT}/Combined/PKGPlugins \
productbuild --distribution ${BUILDROOT}/Combined/Distribution \
--resources ${BUILDROOT}/Combined/Resources \
--package-path ${BUILDROOT}/Combined/Packages \
${BUILDROOT}/Combined/MPClientInstall.pkg

# Expand the newly created package so we can add the nessasary files
pkgutil --expand ${BUILDROOT}/Combined/MPClientInstall.pkg ${BUILDROOT}/Combined/.MPClientInstall

# Backup Original Package
mv ${BUILDROOT}/Combined/MPClientInstall.pkg ${BUILDROOT}/Combined/.MPClientInstall.pkg

# Copy MacPatch Package Info file for the web service
cp ${BUILDROOT}/Combined/Resources/mpInfo.ini ${BUILDROOT}/Combined/.MPClientInstall/Resources/mpInfo.ini
cp ${BUILDROOT}/Combined/Resources/mpInfo.plist ${BUILDROOT}/Combined/.MPClientInstall/Resources/mpInfo.plist
cp ${BUILDROOT}/Combined/Resources/Background_done.png ${BUILDROOT}/Combined/.MPClientInstall/Resources/Background_done.png

# Re-compress expanded package
pkgutil --flatten ${BUILDROOT}/Combined/.MPClientInstall ${BUILDROOT}/Combined/MPClientInstall.pkg

# Clean Up 
rm -rf ${BUILDROOT}/Combined/.MPClientInstall
#rm -rf ${BUILDROOT}/Combined/.MPClientInstall.pkg

# Compress for upload
ditto -c -k ${BUILDROOT}/Combined/MPClientInstall.pkg ${BUILDROOT}/Combined/MPClientInstall.pkg.zip

# Write Version info to plist
defaults write ${BUILDPLIST} client_version "$AGENT_VER"
defaults write ${BUILDPLIST} client_build "$BUILD_NO"
defaults write ${BUILDPLIST} min_os "$MIN_OS"

echo
read -p "Would you like to copy the installer to repo location for a pull request? (Y/N)? [N]: " COPYINSTALLPKG
COPYINSTALLPKG=${COPYINSTALLPKG:-N}

if [ "$COPYINSTALLPKG" == "y" ] || [ "$COPYINSTALLPKG" == "Y" ]; then
	rm -rf "${SRCROOT}/Agent"
	mkdir "${SRCROOT}/Agent"
	cp "${BUILDROOT}/Combined/MPClientInstall.pkg.zip" "${SRCROOT}/Agent/"
	cp "$BUILD_FILE" "${SRCROOT}/Agent/InstallerBuildInfo.txt"
fi

echo 
echo "New Client is located in $BUILDROOT"
open ${BUILDROOT}