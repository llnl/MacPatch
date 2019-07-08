#!/bin/bash

if [[ "$1" = "-v" ]]; then
  echo "$(basename "$0"), version: 9999"
  
fi

cd "$(mktemp -d)" || exit 1

last3Days=`date -v -3d +"%m%d%Y"`
infolog="system-info.log"
tmpzip="/tmp/log-capture.zip"
rm -rf $tmpzip

logfiles="/private/var/log/install.log*
/private/var/log/system.log*
/Library/MacPatch/Client/Logs/*
/Library/MacPatch/Updater/Logs/*
/Users/*/Library/Logs/MP*.log*"

SAVEIFS=$IFS
IFS=$'\n'
for f in $logfiles; do
	zip -u -rt $last3Days "$tmpzip" "$f"
done
IFS=$SAVEIFS

files="/Library/Logs/DiagnosticReports/*.crash
/Users/*/Library/Logs/DiagnosticReports/*.crash
/Library/MacPatch/Client/lib/*.plist
/Library/Application Support/MacPatch/*.plist"

SAVEIFS=$IFS
IFS=$'\n'
for f in $files; do
	zip -u "$tmpzip" "$f"
done
IFS=$SAVEIFS

# MP Client ID
echo "=== MacPatch Client ID" >> "$infolog"
eval ioreg -rd1 -c IOPlatformExpertDevice | awk '/IOPlatformUUID/ { split($0, line, "\""); printf("%s\n", line[4]); }' >> "$infolog"
echo "" >> "$infolog"

# Collect output of various commands
commands="sw_vers
/Library/MacPatch/Client/MPAgent -v
/Library/MacPatch/Client/MPAgentExec -v
/Library/MacPatch/Client/MPWorker -v
who -aH
ls -la /Users/
fdesetup status
df -H
ls -la /Library/LaunchDaemons/
ls -la /Library/LaunchAgents/"

SAVEIFS=$IFS
IFS=$'\n'
for cmd in $commands; do
  echo "=== Output of '$cmd'" >> "$infolog"
  eval $cmd >> "$infolog"
  echo "=== End of '$cmd'" >> "$infolog"
  echo "" >> "$infolog"
done
IFS=$SAVEIFS
zip -uj "$tmpzip" "$infolog"

UDIRS=/Users/*
for USERDIR in $UDIRS; 
do 
	if [ -d "${USERDIR}/Library/LaunchAgents" ]; then 
		echo "=== Output of ls -la $USERDIR/Library/LaunchAgents" >> "$infolog"
		ls -la $USERDIR/Library/LaunchAgents/ >> "$infolog"
		echo "=== End of ls -la $USERDIR/Library/LaunchAgents" >> "$infolog"
  		echo "" >> "$infolog"
	fi 
done


commands="ps aux"
SAVEIFS=$IFS
IFS=$'\n'
for cmd in $commands; do
  echo "=== Output of '$cmd'" >> "$infolog"
  eval $cmd >> "$infolog"
  echo "=== End of '$cmd'" >> "$infolog"
  echo "" >> "$infolog"
done
IFS=$SAVEIFS
zip -uj "$tmpzip" "$infolog"

# Collect system profiler info
/usr/sbin/system_profiler -detailLevel basic -xml > sys_profile.spx
zip -uj "$tmpzip" sys_profile.spx
