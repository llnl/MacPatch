#!/opt/MacPatch/Server/env/server/bin/python

'''
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Charles Heizer <heizer1 at llnl.gov>.
 LLNL-CODE-636469 All rights reserved.

 This file is part of MacPatch, a program for installing and patching
 software.

 MacPatch is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License (as published by the Free
 Software Foundation) version 2, dated June 1991.

 MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
 License for more details.

 You should have received a copy of the GNU General Public License along
 with MacPatch; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
'''

'''
	Script: MPSyncContent
	Version: 1.5.0
'''

import datetime
import logging
import os
import argparse
import plistlib
import sys
import subprocess
import hashlib
import platform
import subprocess
import json


# Define logging for global use
logger       = logging.getLogger('MPSyncContent')

MP_HOME      = "/opt/MacPatch"
MP_SRV_BASE  = MP_HOME+"/Server"

logFile      = MP_SRV_BASE+"/logs/MPSyncContent.log"

# Rsync Path
SYNC_DIR_NAME="mpContentWeb3"
# Rsync Server
MASTER_SERVER="localhost"
# Sync Content to...
LOCAL_CONTENT=MP_HOME+"/Content/Web"


MP_SRV_CONF=MP_SRV_BASE+"/conf"
MP_SYNC_CONF=MP_SRV_BASE+"/etc/syncContent.json"

# Global OS vars
__version__ = "1.5.0"
os_type = platform.system()
system_name = platform.uname()[1]

def script_is_running():
	script_name = os.path.basename(__file__)
	cmd = "ps aux | grep -e '%s' | grep -v grep | awk '{print $2}'| awk '{print $2}'" % script_name
	l = subprocess.getstatusoutput(cmd)
	if l[1]:
		print("Error, script is already running. Now exiting script.")
		logger.error("Error, script is already running. Now exiting script.")
		sys.exit(0);

def readJSONFile(filename):
	returndata = {}

	if not os.path.exists(filename):
		print("Unable to open " + filename +". File not found.")
		sys.exit(1)

	try:
		fd = open(filename, 'r+')
		returndata = json.load(fd)
		fd.close()
	except:
		print('COULD NOT LOAD:', filename)

	return returndata

def main():
	'''Main command processing'''
	parser = argparse.ArgumentParser(description='Process some args.')
	group = parser.add_mutually_exclusive_group(required=True)
	group.add_argument('--config', help="MacPatch Sync Config file ", required=False)
	group.add_argument('--server', help="Rsync Server to Sync from.", required=False)
	parser.add_argument('--syncname', help="Rsync Group Name.", required=False)
	parser.add_argument('--contentgroup', help="Content Directory Group Name (sw, patches, Web)", required=False)
	parser.add_argument('--checksum', help='Use checksum verificartion', action='store_true')
	parser.add_argument('--dry', help="Outputs results, dry run.", action='store_true', required=False)
	parser.add_argument('--version', action='version', version='%(prog)s {version}'.format(version=__version__))
	args = parser.parse_args()

	script_is_running()

	global MASTER_SERVER
	global SYNC_DIR_NAME
	global LOCAL_CONTENT

	# Setup Logging
	try:
		hdlr = logging.FileHandler(logFile)
		formatter = logging.Formatter('%(asctime)s %(levelname)s --- %(message)s')
		hdlr.setFormatter(formatter)
		logger.addHandler(hdlr)
		logger.setLevel(logging.INFO)

	except Exception as e:
		print("%s" % e)
		sys.exit(1)

	# Set Default Values
	if args.checksum:
		useChecksum="-c"
	else:
		useChecksum=""

	# Set Default Values
	if args.dry:
		useDry="-n"
	else:
		useDry=""


	logger.info('# ------------------------------------------------------')
	logger.info('# Starting content sync  '                               )
	logger.info('# ------------------------------------------------------')

	if args.config is not None:
		_conf = readJSONFile(args.config)
		if _conf is not None:
			if 'MPServerAddress' in _conf:
				MASTER_SERVER = _conf['MPServerAddress']
            elif 'settings' in _conf:
                if 'MPServerAddress' in _conf['settings']:
                    MASTER_SERVER = _conf['settings']['MPServerAddress']
			else:
				logger.error("Error, MPServerAddress was not found in config.")
				sys.exit(1)

	elif args.server is not None:
		MASTER_SERVER = args.server


	# We dont allow localhost
	if MASTER_SERVER == "localhost":
		logger.error("Error, localhost is not supported.")
		sys.exit(1)

	if args.syncname is not None:
		SYNC_DIR_NAME = args.syncname

	if args.contentgroup is not None:
		_groups=['web','sw','patches']
		if any(args.contentgroup in s for s in _groups):
			if args.contentgroup is not 'web':
				LOCAL_CONTENT = LOCAL_CONTENT + "/" + args.contentgroup


	logger.info("Starting Content Sync")
	rStr = "-vai " + useDry + " " + useChecksum + " --delete-before --ignore-errors --exclude=.DS_Store " + MASTER_SERVER + "::" + SYNC_DIR_NAME + " " + LOCAL_CONTENT
	os.system('/usr/bin/rsync ' + rStr)
	logger.info("Content Sync Complete")

if __name__ == '__main__':

	main()
