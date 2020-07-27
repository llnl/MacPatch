#!/bin/bash

# -------------------------------------------------------------
# This script will collect all logs and diagnositcs to help
# troubleshoot any MacPatch issue. 
#
# Version: 1.1
#
# History:
# 1.0   Initial Script, support <= MP 3.3.x
# 1.1   Added Full Paths
# -------------------------------------------------------------


CLIENTID=`ioreg -rd1 -c IOPlatformExpertDevice | awk '/IOPlatformUUID/ { split($0, line, "\""); printf("%s\n", line[4]); }'`

mpPlist="/Library/Application Support/MacPatch/gov.llnl.mp.plist"
mpHost="localhost"
mpPort="3600"
useHTTPS=1
hName=`hostname`

if [[ "$1" = "-v" ]]; then
  /bin/echo "$(basename "$0"), version: 9999"  
fi

cd "$(mktemp -d)" || exit 1

last3Days=`/bin/date -v -3d +"%m%d%Y"`
infolog="system-info.log"
tmpzip="/tmp/log-capture.zip"
/bin/rm -rf $tmpzip

logfiles="/private/var/log/install.log*
/private/var/log/system.log*
/Library/MacPatch/Client/Logs/*
/Library/MacPatch/Updater/Logs/*
/Users/*/Library/Logs/MP*.log*
/Users/*/Library/Logs/MacPatch.log*
/Library/Logs/MPAgent.log*
/Library/Logs/gov.llnl.mp.helper.log*
/Library/Logs/mp_planb*"

SAVEIFS=$IFS
IFS=$'\n'
for f in $logfiles; do
	/usr/bin/zip -u -rt $last3Days "$tmpzip" "$f"
done
IFS=$SAVEIFS

files="/Library/Logs/DiagnosticReports/*.crash
/Users/*/Library/Logs/DiagnosticReports/*.crash
/Library/MacPatch/Client/lib/*.plist
/Library/Application Support/MacPatch/*.plist"

SAVEIFS=$IFS
IFS=$'\n'
for f in $files; do
	/usr/bin/zip -u "$tmpzip" "$f"
done
IFS=$SAVEIFS

# MP Client ID
/bin/echo "=== MacPatch Client ID" >> "$infolog"
/bin/echo "$CLIENTID" >> "$infolog"
/bin/echo "" >> "$infolog"

# Collect output of various commands
commands="/usr/bin/sw_vers
/usr/sbin/system_profiler SPHardwareDataType
/Library/MacPatch/Client/MPAgent -v
/Library/PrivilegedHelperTools/gov.llnl.mp.helper -v
/usr/bin/who -aH
/bin/ls -la /Users/
/usr/bin/fdesetup status
/bin/df -H
/bin/ls -la /Library/LaunchDaemons/
/bin/ls -la /Library/LaunchAgents/"

SAVEIFS=$IFS
IFS=$'\n'
for cmd in $commands; do
  /bin/echo "=== Output of '$cmd'" >> "$infolog"
  eval $cmd >> "$infolog"
  /bin/echo "=== End of '$cmd'" >> "$infolog"
  /bin/echo "" >> "$infolog"
done
IFS=$SAVEIFS
/usr/bin/zip -uj "$tmpzip" "$infolog"

UDIRS=/Users/*
for USERDIR in $UDIRS; 
do 
	if [ -d "${USERDIR}/Library/LaunchAgents" ]; then 
		/bin/echo "=== Output of /bin/ls -la $USERDIR/Library/LaunchAgents" >> "$infolog"
		/bin/ls -la $USERDIR/Library/LaunchAgents/ >> "$infolog"
		/bin/echo "=== End of /bin/ls -la $USERDIR/Library/LaunchAgents" >> "$infolog"
  		/bin/echo "" >> "$infolog"
	fi 
done


commands="ps aux"
SAVEIFS=$IFS
IFS=$'\n'
for cmd in $commands; do
  /bin/echo "=== Output of '$cmd'" >> "$infolog"
  eval $cmd >> "$infolog"
  /bin/echo "=== End of '$cmd'" >> "$infolog"
  /bin/echo "" >> "$infolog"
done
IFS=$SAVEIFS
/usr/bin/zip -uj "$tmpzip" "$infolog"

# Collect system profiler info
/usr/sbin/system_profiler -detailLevel basic -xml > sys_profile.spx
/usr/bin/zip -uj "$tmpzip" sys_profile.spx

function makeURL {
    srvCon="http"
    if [ $useHTTPS -eq 1 ]; then
        srvCon="https"
    fi

    urlPst="$srvCon://$mpHost:$mpPort"
    /bin/echo $urlPst
}


if [ -f "$mpPlist" ]; then
    servers=`/usr/libexec/PlistBuddy -c "Print settings:servers:data" "$mpPlist" | grep "Dict"|wc -l`
    servers=`/bin/expr $servers - 1`

    for i in $(seq 0 $servers)
    do
        dict=`/usr/libexec/PlistBuddy -c "Print settings:servers:data:${i}" "$mpPlist"`
        srvType=`/usr/libexec/PlistBuddy -c "Print settings:servers:data:${i}:serverType" "$mpPlist"`
        if [ $srvType -eq 0 ]; then
            mpHost=`/usr/libexec/PlistBuddy -c "Print settings:servers:data:${i}:host" "$mpPlist"`
            mpPort=`/usr/libexec/PlistBuddy -c "Print settings:servers:data:${i}:port" "$mpPlist"`
            useHTTPS=`/usr/libexec/PlistBuddy -c "Print settings:servers:data:${i}:useHTTPS" "$mpPlist"`
            break
        fi
    done

    MASTERSERVER=$(makeURL)
    post=`/usr/bin/curl -F "file=@/tmp/log-capture.zip" -X POST ${MASTERSERVER}/api/v1/support/data/$CLIENTID/$hName`
fi



