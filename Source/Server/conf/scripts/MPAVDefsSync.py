#!/opt/MacPatch/Server/venv/bin/python

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
Script : MPAVDefsSync
Version : 1.0.2
Description: This script will download the last 3 Symantec AV Defs
files via ftp from Symantec. It will also delete older AV Defs zip
files.

Note:
This script requires the "requests" python module. This is not
part of the base python deployment. To install it simply run

$ easy_install requests

For more info: http://docs.python-requests.org/en/latest/user/install/

'''

try:
	import logging
	import plistlib
	import argparse
	import sys
	import ftplib
	import os
	import re
	import json
	import glob
	import requests
except ImportError, e:
	print "%s" % e
	sys.exit(1)

parser = argparse.ArgumentParser()
parser.add_argument('-v', '--version', action='version', version='1.0.0')
parser.add_argument('-p', '--plist', required=True, help='AV Defs downloader config plist')
parser.add_argument('-r', '--remove', help='Removes outdated AV defs files', action="store_true")
args = parser.parse_args()

# Setup Logging
try:
	logger = logging.getLogger('MPAVDefsSync')
	hdlr = logging.FileHandler('/opt/MacPatch/Server/logs/MPAVDefsSync.log')
	formatter = logging.Formatter('%(asctime)s %(levelname)s --- %(message)s')
	hdlr.setFormatter(formatter)
	logger.addHandler(hdlr)
	logger.setLevel(logging.INFO)
except Exception, e:
	print "%s" % e
	sys.exit(1)

# Make sure the plist path is valid
if not os.path.exists(args.plist):
		print "Unable to open " + args.plist +". File not found."
		logger.info("Unable to open " + args.plist +". File not found.")
		sys.exit(1)


# Read First Line to check and see if binary and convert
infile = open(args.plist, 'r')
if not '<?xml' in infile.readline():
	os.system('/usr/bin/plutil -convert xml1 ' + args.plist)

# Read the config plist
avConf = plistlib.readPlist(args.plist)

if avConf.has_key("MPServerAddress"):
	MPServerName = avConf["MPServerAddress"]
else:
	MPServerName = "localhost"

if avConf.has_key("MPServerPort"):
	MPServerPort = avConf["MPServerPort"]
else:
	MPServerPort = "3601"

if avConf.has_key("MPServerSSL"):
	MPServerSSL = avConf["MPServerSSL"]
else:
	MPServerSSL = "0"

if avConf.has_key("avDownloadToFilePaths"):
	avDefsLoc = avConf["avDownloadToFilePath"]
else:
	avDefsLoc = "/opt/MacPatch/Content/Web/sav"

# ------------------------------
# Global Variables
# ------------------------------

print "Not Supported with MacPatch 3.x"
sys.exit(1)

avFileMapping = '/mp-content/sav'
avDefsPostAPI = '/Service/MPServerService.cfc?method=PostSavAvDefs'

# ------------------------------
# Classes
# ------------------------------

# AntiVirus Def class

class avDef:

	def __init__(self, type, file, current):
		self.type = type
		self.current = current
		self.file = avFileMapping + '/' + file
		self.date = self.setDate()

	def setDate(self):
		m = re.findall('_([0-9]+)', self.file, re.DOTALL)
		return m[0]

	def returnAsDictionary(self):
		a = {'date':self.date,'type':self.type,'current':self.current,'file':self.file}
		return a

# ------------------------------
# Main Methods
# ------------------------------

def createDefsLoc():
	# Create the Download/Content Defs Dir
	if not os.path.exists(avDefsLoc):
		os.makedirs(avDefsLoc)

def downloadSymantecDefs(server='ftp.symantec.com', user='anonymous', password='anonymous', fromDir='/public/english_us_canada/antivirus_definitions/norton_antivirus_mac'):

	ftp = ftplib.FTP(server, user, password)
	ftp.cwd(fromDir)
	files = ftp.nlst()

	if len(files) >= 1:
		createDefsLoc()

	ppcArray = []
	x86Array = []

	# Sort and Download av files
	for file in files:
		try:
			if not "NavM" in file:
				continue

			fileFullPath = avDefsLoc + '/' + file

			if "NavM9" in file:
				ppcArray.append(file)
			else:
				x86Array.append(file)

			if not os.path.exists(fileFullPath):
				if os.access(avDefsLoc, os.W_OK):
					logger.info("Begin Downloading " + file)
					lf = open(fileFullPath, "wb")
					ftp.retrbinary("RETR " + file , lf.write, 8*1024)
					lf.close()
				else:
					logger.error("Unable to write to directory " + avDefsLoc +" to download def files.")
					return
			else:
				logger.info(fileFullPath + " already exists.")
		except Exception, e:
			logger.error("%s" % e)
			return

	ftp.close()

	# Create Defs Dictionary and return it
	ppcArray.sort(reverse=True)
	x86Array.sort(reverse=True)
	defsData = {'ppc':ppcArray,'x86':x86Array}
	return defsData

def removeAllOutDatedFiles(nFiles):

	# Merge the Arrays
	newFiles = nFiles['ppc'] + nFiles['x86']

	# List all Currently downloaded files
	currentFiles = glob.glob('/opt/MacPatch/Content/Web/sav/*.zip')

	# Loop through files and if they are not in the new list
	# then remove it.
	for file in currentFiles:
		if not file in nFiles:
			if args.remove:
				logger.info("Removing old file " + file)
				try:
					os.remove(file)
				except Exception, e:
					logger.error("%s" % e)
					return

def postAVDataToWebService(arch, avData):

	httpPrefix = "http"
	if MPServerSSL == 1:
		httpPrefix = "https"
	_url = httpPrefix + "://" + MPServerName + ":" + MPServerPort + avDefsPostAPI
	payload = {'arch': arch , 'data': json.dumps(avData)}
	request = requests.post(_url, data=payload, verify=False)
	logger.info(request.text)

# Architecture Defs Arrays
ppc = []
x86 = []
logger.info("-----------------------------------------")
logger.info("Begin AV Defs Sync                       ")
logger.info("-----------------------------------------")

avData = downloadSymantecDefs()
if not avData:
	logger.error("Method returned error, exiting script.")
	sys.exit(1)

removeAllOutDatedFiles(avData)

# Format AV data to post to web service
# for both PPC and X86
if 'ppc' in avData:
	i = 0
	for file in avData['ppc']:
		if i == 0:
			a = avDef('ppc',file,'YES')
		elif i >= 3:
			continue
		else:
			a = avDef('ppc',file,'NO')
		ppc.append(a.__dict__)
		i += 1

if 'x86' in avData:
	i = 0
	for file in avData['x86']:
		if i == 0:
			a = avDef('x86',file,'YES')
		elif i >= 3:
			continue
		else:
			a = avDef('x86',file,'NO')
		x86.append(a.__dict__)
		i += 1

# Post AV Defs Data to web service & database
logger.info("Posting ppc results to web service.")
postAVDataToWebService('ppc', ppc)
logger.info("Posting x86 results to web service.")
postAVDataToWebService('x86', x86)
