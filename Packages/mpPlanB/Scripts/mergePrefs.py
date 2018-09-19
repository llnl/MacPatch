#!/usr/bin/python

# mergePrefs.py
# Jorge Escobar
# 1/30/2013
#
# Updated 4/13/17
# Added filteredKeys list for managing the perm file

# Usage:
#	mergePrefs -b -i /path/to/infile.plist -t /path/to/target.plist
#	-b, --backup
#		backup target plist before changing
#	-i, --infile
#		plist used to merge with target plist
#	-t, --target
#		plist that is the target of the infile

import os
import sys
import getopt
import plistlib
import xml.parsers.expat as expat
import datetime
import re


### Variables ###
LOCAL_PERM_PLIST_PATH = "/Library/Preferences/gov.llnl.mpagent.perm.plist"
FILTERED_PERM_KEYS = ['AllowClient', 'AllowServer', 'Domain', 'PatchGroup', 'Reboot', 'SWDistGroup', 'Description', 'PatchState']

### Functions ###
def usage():
	print "Usage: mergePrefs -b -i /path/to/infile.plist -t /path/to/target.plist"
	print "       -b, --backup     backup target plist before changing"
	print "       -i, --infile     plist used to merge with target plist"
	print "       -t, --target     plist that is the target of the infile"


def safeReadPlist(plistPath):
# This function returns an empty dict if it fails to read the plist
	convertedPlistPath = "/tmp/tmp.plist"
	myPlist = dict()

	# Check if plist exists
	if not os.path.isfile(plistPath):
		print "%s does not exist." % plistPath
		return myPlist

	# Try reading the plist as-is
	try:
		myPlist = plistlib.Plist.fromFile(plistPath)
	# If there was an ExpatError the plist is probably binary, lets convert it to xml
	except (expat.ExpatError):
		# Convert plist to xml format
		os.system("/usr/bin/plutil -convert xml1 %s -o %s" % (plistPath, convertedPlistPath))

		# Try reading it now
		try:
			myPlist = plistlib.Plist.fromFile(convertedPlistPath)
		# If there was an error this time, idk ... this plist has issues
		except (ImportError):
			print "Sorry there was an error with %s" % plistPath
			sys.exit(1)
	except (ImportError):
		print "Sorry there was an error with %s" % plistPath
		sys.exit(1)
	except:
		print 'Unexpected error:', sys.exc_info()[0]
		sys.exit(1)
	return myPlist

### Main ###

backup = False

try:
	opts, args = getopt.getopt(sys.argv[1:], "bt:i:", ["backup", "target=", "infile="])
except getopt.GetoptError:
	usage()
	sys.exit(2)
for opt, arg in opts:
	if opt in ("-t", "--target"):
		targetPlist = safeReadPlist(arg)    # if file doesn't exist an empty dict is created
		targetPlistPath = arg
	if opt in ("-i", "--infile"):
		inPlist = safeReadPlist(arg)
	if opt in ("-b", "--backup"):
		backup = True

# Create a new plist
newPlist = dict()

# Merge default settings from inPlist into newPlist
newPlist.update(inPlist.default)

# Merge current settings from targetPlist into newPlist
newPlist.update(targetPlist)

# Merge enforced settings from inPlist into newPlist
newPlist.update(inPlist.enforced)

# Merge local "perm" settings into newPlist, if the perm file exists
if os.path.isfile(LOCAL_PERM_PLIST_PATH):
	permPlist = safeReadPlist(LOCAL_PERM_PLIST_PATH)
	
	# This is for migrations, populate the keys that can be perm data
	# if filteredKeys list is empty all perm data will get merged.
	if len(FILTERED_PERM_KEYS) >= 1:
		permPlistFiltered = dict()
		for fKey in FILTERED_PERM_KEYS:
			if fKey in permPlist:
				permPlistFiltered[fKey] = permPlist[fKey]

		permPlist = permPlistFiltered

	newPlist.update(permPlist)

# Backup target plist if requrested
if backup is True:
	if os.path.isfile(targetPlistPath):
		now = str(datetime.datetime.now())
		timestamp = re.sub('[^\w]', '', now)    # removes non alphas
		os.rename(targetPlistPath, "%s.%s" % (targetPlistPath, timestamp))

# Write out new plist
plistlib.writePlist(newPlist, targetPlistPath)
