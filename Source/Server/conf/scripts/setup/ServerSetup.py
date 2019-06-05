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
  MacPatch Patch Loader Setup Script
  MacPatch Version 3.3.x

  Script Version 2.4.0
'''

import os
import plistlib
import platform
import argparse
import pwd
import grp
import shutil
import json
import getpass
import types
from distutils.version import LooseVersion
import configparser
import sys
from sys import exit
from Crypto.PublicKey import RSA

# ----------------------------------------------------------------------------
# Script Requires ROOT
# ----------------------------------------------------------------------------
if os.geteuid() != 0:
	exit("\nYou must be an admin user to run this script.\nPlease re-run the script using sudo.\n")

# ----------------------------------------------------------------------------
# Variables
# ----------------------------------------------------------------------------
MP_BASE	 	    = "/opt/MacPatch"
MP_SRV_BASE	    = "/opt/MacPatch/Server"
MP_SRV_ETC	    = MP_SRV_BASE+"/etc"
MP_FLASK_FILE   = MP_SRV_BASE+"/apps/config.cfg"
MP_CONF_FILE    = MP_SRV_BASE+"/etc/siteconfig.json"
MP_SRVC_FILE    = MP_SRV_BASE+"/etc/.mpservices.json"

if sys.platform.startswith('linux'):
	dist_type 	 = platform.dist()[0]
else:
	dist_type 	 = "Mac"


MP_SRV_CONF 	= MP_SRV_BASE+"/conf"
MP_SRV_CONT 	= MP_BASE+"/Content/Web"
MP_INV_DIR		= MP_SRV_BASE+"/InvData"
MP_SRV_KEYS		= MP_SRV_ETC +"/keys"

os_type 		= platform.system()
system_name 	= platform.uname()[1]
gUID 			= 79
gGID 			= 70
cronList		= []


if sys.platform.startswith('linux'):
	# OS is Linux, I need the dist type...
	try:
		pw = pwd.getpwnam('www-data')
		if pw:
			gUID = pw.pw_uid

		gw = grp.getgrnam('www-data')
		if gw:
			gGID = gw.gr_gid

	except KeyError:
		print('User www-data does not exist.')
		exit(1)

macServices=["gov.llnl.mp.invd.plist","gov.llnl.mp.py.api.plist","gov.llnl.mp.py.console.plist",
"gov.llnl.mp.sus.sync.plist","gov.llnl.mpavdl.plist","gov.llnl.mp.rsync.plist",
"gov.llnl.mp.sync.plist","gov.llnl.mp.pfctl.plist","gov.llnl.mp.fw.plist","gov.llnl.mp.nginx.plist"]

lnxServices=["MPInventoryD3","MPAPI","MPConsole","MPNginx3","MPRsyncServer3"]
lnxCronSrvs=["MPPatchLoader","MPAVLoader","MPSyncContent"]

# ----------------------------------------------------------------------------
# Read and write flask config data from file
# ----------------------------------------------------------------------------

def read_config_file(file_path):
	config = {}
	with open(file_path) as f:
		lines = (line.rstrip() for line in f)
		for l in lines:
			if l.rstrip():
				if l.startswith("#") == False:
					config[l.split('=')[0].strip()] = l.split('=')[1].strip().replace("'","")

	return config

def write_config_file(file_path, config, addNotice=True):
	f = open(file_path,'w+')
	if addNotice:
		f.write("# Put Any Global Server & App Config Settings to override any settings\n\n")
	for key, value in config.items():
		f.write('{} = \'{}\'\n'.format(key, value))

	f.close()

# ----------------------------------------------------------------------------
# Script Methods
# ----------------------------------------------------------------------------

def existsOrExit(filePath):
	if os.path.exists(filePath):
		return filePath
	else:
		print((filePath + ' does not exist. Now exiting.'))
		exit(1)

def readJSON(filename):
	returndata = {}
	try:
		fd = open(filename, 'r+')
		returndata = json.load(fd)
		fd.close()
	except:
		print('COULD NOT LOAD:', filename)

	return returndata

def writeJSON(data, filename):
	try:
		fd = open(filename, 'w')
		json.dump(data,fd, indent=4)
		fd.close()
	except:
		print('ERROR writing', filename)
		pass

def readServicesConfig(platformType):
	_conf = []
	if os.path.exists(MP_SRVC_FILE):
		_conf = readJSON(MP_SRVC_FILE)
	else:
		return _conf

	if platformType == 'Darwin':
		return _conf['Darwin']
	elif platformType == 'Linux':
		return _conf['Linux']
	else:
		return _conf

def passwordEntry():
	pass1 = ""
	pass2 = ""

	while True:
		pass1 = getpass.getpass("Password:")
		pass2 = getpass.getpass("Password (verify):")
		if pass1 == pass2:
			break
		else:
			print("Passwords did not match, please try again.")

	return pass1

def repairPermissions():
	try:
		if os_type == "Darwin":
			os.system("/usr/sbin/dseditgroup -o edit -a _appserver -t user _www")
			os.system("/usr/sbin/dseditgroup -o edit -a _www -t user _appserverusr")

		# Change Permissions for Linux & Mac
		for root, dirs, files in os.walk(MP_SRV_BASE):
			for momo in dirs:
				os.chown(os.path.join(root, momo), gUID, gGID)
			for momo in files:
				os.chown(os.path.join(root, momo), gUID, gGID)

		os.chmod("/opt/MacPatch", 0o775)
		os.chmod(MP_SRV_BASE+"/logs", 0o775)
		os.system("chmod -R 0775 "+ MP_SRV_CONT)

		if os_type == "Darwin":
			os.system("chown root:wheel "+MP_SRV_BASE+"/conf/launchd/*")
			os.system("chmod 644 "+MP_SRV_BASE+"/conf/launchd/*")
	except Exception as e:
		print(("Error: %s" % e))

def linuxLoadServices(service):

	_services = list()

	if hasattr(service, 'lower'):
		if service.lower() == "all":
			_services = lnxServices

		else:
			if service in lnxServices:
				_services.append(service)
	else:
		_services = service['services']


	# Load Init.d Services
	if _services != None:
		for srvs in _services:
			linuxLoadInitServices(srvs)

def linuxUnLoadServices(service):

	_services = list()

	if hasattr(service, 'lower'):
		if service.lower() == "all":
			_services = lnxServices

		else:
			if service in lnxServices:
				_services.append(service)
	else:
		_services = service['services']

	# Load Init.d Services
	if _services != None:
		for srvs in _services:
			linuxUnLoadInitServices(srvs)

def linuxLoadInitServices(service):

	print("Loading service "+service)

	useSYSTEMD=False
	if platform.dist()[0] == "Ubuntu" and LooseVersion(platform.dist()[1]) >= LooseVersion("15.0"):
		useSYSTEMD=True
	elif (platform.dist()[0] == "redhat" or platform.dist()[0] == "centos") and LooseVersion(platform.dist()[1]) >= LooseVersion("7.0"):
		useSYSTEMD=True
	else:
		print("Unable to start service ("+service+") at start up. OS("+platform.dist()[0]+") is unsupported.")
		return

	if useSYSTEMD == True:
		serviceName=service+".service"
		etcServiceConf="/etc/systemd/system/"+serviceName

		if os.path.exists(etcServiceConf):
			os.system("/bin/systemctl start "+serviceName)
		else:
			print("Unable to find " + etcServiceConf)
	else:
		_initFile = "/etc/init.d/"+service
		if os.path.exists(_initFile):
			os.system("/etc/init.d/"+service+" start")
		else:
			print("Unable to find " + _initFile)

def linuxUnLoadInitServices(service):
	# UnLoad Init Services
	print("UnLoading service "+service)
	useSYSTEMD=False
	if platform.dist()[0] == "Ubuntu" and LooseVersion(platform.dist()[1]) >= LooseVersion("15.0"):
		useSYSTEMD=True
	elif (platform.dist()[0] == "redhat" or platform.dist()[0] == "centos") and LooseVersion(platform.dist()[1]) >= LooseVersion("7.0"):
		useSYSTEMD=True
	else:
		print("Unable to start service ("+service+") at start up. OS("+platform.dist()[0]+") is unsupported.")
		return

	if useSYSTEMD == True:
		serviceName=service+".service"
		etcServiceConf="/etc/systemd/system/"+serviceName

		if os.path.exists(etcServiceConf):
			os.system("/bin/systemctl stop "+serviceName)
		else:
			print("Unable to find " + etcServiceConf)
	else:
		_initFile = "/etc/init.d/"+service
		if os.path.exists(_initFile):
			os.system("/etc/init.d/"+service+" stop")
		else:
			print("Unable to find " + _initFile)

def linuxLoadCronServices(service):
	from crontab import CronTab
	cron = CronTab()

	if service == "MPPatchLoader":
		print("Loading MPPatchLoader")

		cmd = MP_SRV_CONF + '/scripts/MPSUSPatchSync.py --config ' + MP_SRV_BASE + '/etc/patchloader.json'
		job  = cron.new(command=cmd)
		job.set_comment("MPPatchLoader")
		job.hour.every(8)
		job.enable()
		cron.write_to_user(user='root')

	if service == "MPSyncContent":
		print("Loading MPSyncContent")

		cmd = MP_SRV_CONF + '/scripts/MPSyncContent.py --config ' + MP_SRV_BASE + '/etc/syncContent.json'
		job  = cron.new(command=cmd)
		job.set_comment("MPSyncContent")
		job.minute.every(30)
		job.enable()
		cron.write_to_user(user='root')

	if service == "MPAVLoader":
		print("Loading MPAVLoader")

		cmd = MP_SRV_CONF + '/scripts/MPAVDefsSync.py --config ' + MP_SRV_BASE + '/etc/avconf.json'
		job  = cron.new(command=cmd)
		job.set_comment("MPAVLoader")
		job.hour.every(11)
		job.enable()
		cron.write_to_user(user='root')

def removeCronJob(comment):
	from crontab import CronTab
	cron = CronTab()

	for job in cron:
		if job.comment == comment:
			print("\nRemoving Cron Job" + comment)
			cJobRm = input('Are you sure you want to remove this cron job (Y/N)?')
			if cJobRm.lower() == "y" or cJobRm.lower() == "yes":
				cron.remove (job)

def osxLoadServices(service):
	_services = list()

	if hasattr(service, 'lower'):
		if service.lower() == "all":
			_services = macServices
		else:
			if service in macServices:
				_services.append(service)
			else:
				print(service + " was not found. Service will not load.")
	else:
		_services = service['services']


	for srvc in _services:
		# Set Permissions
		os.chown(MP_SRV_BASE+"/conf/launchd/"+srvc, 0, 0)
		os.chmod(MP_SRV_BASE+"/conf/launchd/"+srvc, 0o644)

		_launchdFile = "/Library/LaunchDaemons/"+srvc
		if os.path.exists(_launchdFile):
			print("Loading service "+srvc)
			os.system("/bin/launchctl load -w /Library/LaunchDaemons/"+srvc)
		else:
			if os.path.exists(MP_SRV_BASE+"/conf/launchd/"+srvc):
				if os.path.exists("/Library/LaunchDaemons/"+srvc):
					os.remove("/Library/LaunchDaemons/"+srvc)

				os.symlink(MP_SRV_BASE+"/conf/launchd/"+srvc,"/Library/LaunchDaemons/"+srvc)

				print("Loading service "+srvc)
				os.system("/bin/launchctl load -w /Library/LaunchDaemons/"+srvc)

			else:
				print(srvc + " was not found in MacPatch Server directory. Service will not load.")

def osxUnLoadServices(service):
	_services = list()

	if hasattr(service, 'lower'):
		if service.lower() == "all":
			_services = macServices
		else:
			if service in macServices:
				_services.append(service)
	else:
		_services = service['services']

	for srvc in _services:
		_launchdFile = "/Library/LaunchDaemons/"+srvc
		if os.path.exists(_launchdFile):
			print("UnLoading service "+srvc)
			os.system("/bin/launchctl unload -wF /Library/LaunchDaemons/"+srvc)

def setupRsyncFromMaster():
	os.system('clear')
	print("\nConfigure this server to syncronize data from the \"Master\" MacPatch server.\n")
	server_name = input("MacPatch Server \"hostname\" or \"IP Address\" TO sync data from: ")

	'''	Write the Plist With Changes '''
	theFile = MP_SRV_BASE + "/etc/syncContent.json"
	prefs = {'MPServerAddress': server_name}

	try:
		writeJSON(prefs, theFile)
	except Exception as e:
		print(("Error: %s" % e))

	''' Enable Startup Scripts '''
	if os_type == "Darwin":
		if os.path.exists(MP_SRV_BASE+"/conf/launchd/gov.llnl.mp.sync.plist"):
			if os.path.exists("/Library/LaunchDaemons/gov.llnl.mp.sync.plist"):
				os.remove("/Library/LaunchDaemons/gov.llnl.mp.sync.plist")

			os.symlink(MP_SRV_BASE+"/conf/launchd/gov.llnl.mp.sync.plist","/Library/LaunchDaemons/gov.llnl.mp.sync.plist")
			os.chown(MP_SRV_BASE+"/conf/launchd/gov.llnl.mp.sync.plist", 0, 0)
			os.chmod(MP_SRV_BASE+"/conf/launchd/gov.llnl.mp.sync.plist", 0o644)

	if os_type == "Linux":
		linuxLoadCronServices("MPSyncContent")

def setupPatchLoader():

	'''	Write the Plist With Changes '''
	prefs = dict()
	theFile = MP_SRV_BASE + "/etc/patchloader.json"
	if os.path.exists(theFile):
		prefs=readJSON(theFile)

	_srvHost = "127.0.0.1"
	_srvPort = "3600"
	_srvUSSL = "Y"

	srvHost = input('\nMaster server address [127.0.0.1]: ')
	srvHost = srvHost or _srvHost

	srvPort = input('Master server port [3600]: ')
	srvPort = srvPort or _srvPort
	srvUSSL = input('Master server, use SSL [Y]: ')
	if srvUSSL.lower() == "y" or srvUSSL.lower() == "":
		srvUSSLBOOL = True
	elif srvUSSL.lower() == "n":
		srvUSSLBOOL = False

	prefs['settings']['MPServerAddress'] = srvHost
	prefs['settings']['MPServerUseSSL'] = srvUSSLBOOL
	prefs['settings']['MPServerPort'] = str(srvPort)

	try:
		writeJSON(prefs, theFile)
	except Exception as e:
		print(("Error: %s" % e))

	''' Enable Startup Scripts '''
	if os_type == "Darwin":
		if os.path.exists(MP_SRV_BASE+"/conf/launchd/gov.llnl.mp.sus.sync.plist"):
			if os.path.exists("/Library/LaunchDaemons/gov.llnl.mp.sus.sync.plist"):
				os.remove("/Library/LaunchDaemons/gov.llnl.mp.sus.sync.plist")

			os.symlink(MP_SRV_BASE+"/conf/launchd/gov.llnl.mp.sus.sync.plist","/Library/LaunchDaemons/gov.llnl.mp.sus.sync.plist")
			os.chown(MP_SRV_BASE+"/conf/launchd/gov.llnl.mp.sus.sync.plist", 0, 0)
			os.chmod(MP_SRV_BASE+"/conf/launchd/gov.llnl.mp.sus.sync.plist", 0o644)
	else:
		linuxLoadCronServices('MPPatchLoader')

def setupServices():

	srvsList = []
	print("You will be asked which services you would like to load")
	print("on system startup.")
	print("")

	# Master or Distribution
	masterType = True
	srvType = input('Is this a Master or Distribution server [M/D]?')
	if srvType.lower() == "m" or srvType.lower() == "master":
		masterType = True
	elif srvType.lower() == "d" or srvType.lower() == "distribution":
		masterType = False

	# Web Services
	_WEBSERVICES = 'Y'
	print("")
	webService = input('Enable Web Services [%s]' % _WEBSERVICES)
	webService = webService or _WEBSERVICES
	jData = readJSON(MP_CONF_FILE)
	if webService.lower() == 'y':

		jData['settings']['services']['mpwsl'] = True
		jData['settings']['services']['mpapi'] = True

		if os_type == 'Darwin':
			if 'gov.llnl.mp.py.api.plist' not in srvsList:
				srvsList.append('gov.llnl.mp.py.api.plist')
			if 'gov.llnl.mp.invd.plist' not in srvsList:
				srvsList.append('gov.llnl.mp.invd.plist')
			if 'gov.llnl.mp.nginx.plist' not in srvsList:
				srvsList.append('gov.llnl.mp.nginx.plist')
		else:
			linkStartupScripts('MPInventoryD3')
			srvsList.append('MPInventoryD3')
			linkStartupScripts('MPNginx3')
			srvsList.append('MPNginx3')
			linkStartupScripts('MPAPI')
			srvsList.append('MPAPI')
	else:
		jData['settings']['services']['mpwsl'] = False
		jData['settings']['services']['mpapi'] = False

	writeJSON(jData,MP_CONF_FILE)

	# Web Admin Console

	_ADMINCONSOLE = 'Y' if masterType else 'N'
	print("")
	adminConsole = input('Enable Admin Console Application [%s]' % _ADMINCONSOLE)
	adminConsole = adminConsole or _ADMINCONSOLE
	jData = readJSON(MP_CONF_FILE)
	if adminConsole.lower() == 'y':

		jData['settings']['services']['console'] = True

		if os_type == 'Darwin':
			if 'gov.llnl.mp.py.console.plist' not in srvsList:
				srvsList.append('gov.llnl.mp.py.console.plist')
			if 'gov.llnl.mp.nginx.plist' not in srvsList:
				srvsList.append('gov.llnl.mp.nginx.plist')
		else:
			linkStartupScripts('MPNginx3')
			srvsList.append('MPNginx3')
			linkStartupScripts('MPConsole')
			srvsList.append('MPConsole')

	else:

		jData['settings']['services']['console'] = False

	writeJSON(jData,MP_CONF_FILE)

	# Content Sync
	_CONTENT = 'Y' if masterType else 'N'
	print("")
	print("Content sync allows distribution servers to sync from the master server.")
	cRsync = input('Start Content Sync Service (Master Only) [%s]' % _CONTENT)
	cRsync = cRsync or _CONTENT
	if cRsync.lower() == 'y':
		if os_type == 'Darwin':
			srvsList.append('gov.llnl.mp.rsync.plist')
		else:
			linkStartupScripts('MPRsyncServer3')
			linkStartupScripts('MPRsyncServer3@','copy')
			linkStartupScripts('MPRsyncServer3','copy','socket')
			srvsList.append('MPRsyncServer3')

	# Patch Loader
	_PATCHLOAD = 'Y' if masterType else 'N'
	print("")
	patchLoader = input('ASUS Patch Content Loader [%s]' % _PATCHLOAD)
	patchLoader = patchLoader or _PATCHLOAD
	if patchLoader.lower() == 'y':
		setupPatchLoader()
		if os_type == 'Darwin':
			srvsList.append('gov.llnl.mp.sus.sync.plist')

	# Sync From Master
	if masterType == False:
		_RSYNC = 'Y'
		print("")
		mpRsync = input('Sync Content from Master server (Recommended) [%s]' % _RSYNC)
		mpRsync = mpRsync or _RSYNC
		if mpRsync.lower() == 'y':
			setupRsyncFromMaster()
			if os_type == 'Darwin':
				srvsList.append('gov.llnl.mp.sync.plist')

	# Firewall Config / Port Forwarding
	#if os_type == 'Darwin':
#		_PFLOAD = 'Y'
#		print "MacPatch Tomcat Runs on several tcp ports (8080,8443,2600)"
#		print "Port forwading forwards the following ports"
#		print "80 -> 8080"
#		print "443 -> 8443"
#		pfConf = raw_input('Enable port forwading (Recommended) [%s]' % _PFLOAD)
#		pfConf = pfConf or _PFLOAD
#		if pfConf.lower() == 'y':
#			if platform.mac_ver()[0] >= "10.10.0":
#				srvsList.append('gov.llnl.mp.pfctl.plist')
#			else:
#				srvsList.append('gov.llnl.mp.fw.plist')


	return set(srvsList)

def linkStartupScripts(service,action='enable',altType=None):

	print("Copy Startup Script for "+service)
	useSYSTEMD=False

	if platform.dist()[0] == "Ubuntu" and LooseVersion(platform.dist()[1]) >= LooseVersion("15.0"):
		useSYSTEMD=True
	elif (platform.dist()[0] == "redhat" or platform.dist()[0] == "centos") and LooseVersion(platform.dist()[1]) >= LooseVersion("7.0"):
		useSYSTEMD=True
	else:
		print("Unable to start service ("+service+") at start up. OS("+platform.dist()[0]+") is unsupported.")
		return

	if useSYSTEMD == True:
		if altType == None:
			serviceName=service+".service"
		else:
			serviceName=service+"."+altType
		serviceConf=MP_SRV_BASE+"/conf/systemd/"+serviceName
		etcServiceConf="/etc/systemd/system/"+serviceName
		shutil.copy2(serviceConf, etcServiceConf)

		if action == 'enable':
			os.system("/bin/systemctl enable "+serviceName)

	else:
		_initFile = "/etc/init.d/"+service
		if os.path.exists(_initFile):
			return
		else:
			script = MP_SRV_BASE+"/conf/init.d/Ubuntu/"+service
			link = "/etc/init.d/"+service

			os.chown(script, 0, 0)
			os.chmod(script, 0o755)
			os.symlink(script,link)

		os.system("update-rc.d "+service+" defaults")

# ----------------------------------------------------------------------------
# DB Config Class
# ----------------------------------------------------------------------------

class MPDatabase:

	config_file = MP_FLASK_FILE

	def __init__(self):
		MPDatabase.config_file = MP_FLASK_FILE

	def loadConfig(self):
		config = {}
		try:
			config = read_config_file(MP_FLASK_FILE)
		except:
			print("COULD NOT LOAD " + config_file + " using empty config.")

		return config

	def configDatabase(self):
		conf = self.loadConfig()
		system_name = platform.uname()[1]

		os.system('clear')
		print("Configure MacPatch Database Info...")
		mp_db_hostname = input("MacPatch Database Server Hostname:  [" + str(system_name) + "]: ") or str(system_name)
		conf["DB_HOST"] = mp_db_hostname

		mp_db_port = input("MacPatch Database Server Port Number [3306]: ") or "3306"
		conf["DB_PORT"] = mp_db_port

		mp_db_name = input("MacPatch Database Name [MacPatchDB3]: ") or "MacPatchDB3"
		conf["DB_NAME"] = mp_db_name

		mp_db_usr = input("MacPatch Database User Name [mpdbadm]: ") or "mpdbadm"
		conf["DB_USER"] = mp_db_usr

		#print('MacPatch Database User (' +mp_db_usr+ ') Password')
		mp_db_pas = getpass.getpass('MacPatch Database User (' +mp_db_usr+ ') Password:')
		conf["DB_PASS"] = mp_db_pas

		#print('MacPatch Database Read Only User (mpdbro) Password:')
		mp_db_pas_ro = getpass.getpass('MacPatch Database Read Only User (mpdbro) Password:')
		conf["DB_USER_RO"] = 'mpdbro'
		conf["DB_PASS_RO"] = mp_db_pas_ro

		save_answer = input("Would you like the save these settings [Y]?:").upper() or "Y"
		if save_answer == "Y":
			write_config_file(MP_FLASK_FILE, conf)
		else:
			return self.configDatabase()

# ----------------------------------------------------------------------------
# LDAP Config Class
# ----------------------------------------------------------------------------

class MPLdap:

	config_file = MP_SRV_BASE+"/etc/siteconfig.json"

	def __init__(self):

		MPLdap.config_file = MP_SRV_BASE+"/etc/siteconfig.json"

	def loadConfig(self):
		config = {}
		try:
			fd = open(MPLdap.config_file, 'r+')
			config = json.load(fd)
			fd.close()
		except:
			print('COULD NOT LOAD:', filename)
			exit(1)

		return config

	def writeConfig(self, config):
		print("Writing configuration data to file ...")
		with open(MPLdap.config_file, "w") as outfile:
			json.dump(config, outfile, indent=4)

	def configLdap(self):
		conf = self.loadConfig()

		os.system('clear')
		print("Configure MacPatch Login Source...")
		use_ldap = input("Would you like to use Active Directory/LDAP for login? [Y]:").upper() or "Y"

		if use_ldap == "Y":
			ldap_hostname = input("Active Directory/LDAP server hostname: ")
			conf["settings"]["ldap"]["server"] = ldap_hostname

			print("Common ports for LDAP non secure is 389, secure is 636.")
			print("Common ports for Active Directory non secure is 3268, secure is 3269")
			ldap_port = input("Active Directory/LDAP server port number: ")
			conf["settings"]["ldap"]["port"] = ldap_port

			use_ldap_ssl = input("Active Directory/LDAP use ssl? [Y]: ").upper() or "Y"
			if use_ldap_ssl == "Y":
				print("Please note, you will need to run the addRemoteCert.py script prior to starting the MacPatch Web Admin Console.")
				ldap_ssl = "CFSSL_BASIC"
				conf["settings"]["ldap"]["secure"] = ldap_ssl
			else:
				ldap_ssl = "NONE"
				conf["settings"]["ldap"]["secure"] = ldap_ssl

			ldap_searchbase = input("Active Directory/LDAP Search Base: ")
			conf["settings"]["ldap"]["searchbase"] = ldap_searchbase

			ldap_lgnattr = input("Active Directory/LDAP Login Attribute [userPrincipalName]: ") or "userPrincipalName"
			conf["settings"]["ldap"]["loginAttr"] = ldap_lgnattr

			ldap_lgnpre = input("Active Directory/LDAP Login User Name Prefix [None]: ") or ""
			conf["settings"]["ldap"]["loginUsrPrefix"] = ldap_lgnpre

			ldap_lgnsuf = input("Active Directory/LDAP Login User Name Suffix [None]: ") or ""
			conf["settings"]["ldap"]["loginUsrSufix"] = ldap_lgnsuf
			conf["settings"]["ldap"]["enabled"] = True

			save_answer = input("Would you like the save these settings [Y]?:").upper() or "Y"
			if save_answer == "Y":
				self.writeConfig(conf)
			else:
				return self.configLdap()

		else:
			conf["settings"]["ldap"]["enabled"] = False
			self.writeConfig(conf)

# ----------------------------------------------------------------------------
# MPAdmin Config Class
# ----------------------------------------------------------------------------

class MPAdmin:

	def __init__(self):
		self.mp_adm_name = "mpadmin"
		self.mp_adm_pass = "*mpadmin*"
		MPAdmin.config_file = MP_CONF_FILE

	def loadConfig(self):
		config = {}
		try:
			fd = open(MPAdmin.config_file, 'r+')
			config = json.load(fd)
			fd.close()
		except:
			print('COULD NOT LOAD:', filename)
			exit(1)

		return config

	def writeConfig(self, config):
		print("Writing configuration data to file ...")
		with open(MPAdmin.config_file, "w") as outfile:
			json.dump(config, outfile, indent=4)

	def configAdminUser(self):
		conf = self.loadConfig()

		os.system('clear')
		print("Set Default Admin name and password...")

		set_admin_info = input("Would you like to set the admin name and password [Y]:").upper() or "Y"
		if set_admin_info == "Y":
			mp_adm_name = input("MacPatch Default Admin Account Name [mpadmin]: ") or "mpadmin"
			conf["settings"]["users"]["admin"]["name"] = mp_adm_name
			print("MacPatch MacPatch Default Admin Account Password")
			mp_adm_pass = passwordEntry()
			conf["settings"]["users"]["admin"]["pass"] = mp_adm_pass
		else:
			return

		save_answer = input("Would you like the save these settings [Y]?:").upper() or "Y"
		if save_answer == "Y":
			self.writeConfig(conf)
		else:
			return self.configAdminUser()

# ----------------------------------------------------------------------------
# MP Set Default Config Data
# ----------------------------------------------------------------------------

class MPConfigDefaults:

	ws_alt_conf = MP_SRV_BASE+"/apps/conf_wsapi.cfg"

	def __init__(self):
		MPConfigDefaults.config_file = MP_CONF_FILE
		MPConfigDefaults.ws_alt_conf = MP_SRV_BASE+"/apps/conf_wsapi.cfg"

	def loadConfig(self):
		config = {}
		try:
			fd = open(MPConfigDefaults.config_file, 'r+')
			config = json.load(fd)
			fd.close()
		except:
			print('COULD NOT LOAD:', MPConfigDefaults.config_file)
			exit(1)

		return config

	def genServerKeys(self):
		new_key = RSA.generate(4096, e=65537)
		public_key = new_key.publickey().exportKey("PEM")
		private_key = new_key.exportKey("PEM")
		return private_key, public_key

	def writeConfig(self, config):
		print("Writing configuration data to file ...")
		with open(MPConfigDefaults.config_file, "w") as outfile:
			json.dump(config, outfile, indent=4)

	def genConfigDefaults(self):
		print("Loading initial configuration data ...")
		conf = self.loadConfig()

		# Paths
		conf["settings"]["paths"]["base"] = MP_SRV_BASE
		conf["settings"]["paths"]["content"] = MP_SRV_CONT

		# Inventory
		conf["settings"]["server"]["inventory_dir"] = MP_INV_DIR

		# Server Keys
		if not os.path.exists(MP_SRV_KEYS):
			os.makedirs(MP_SRV_KEYS)

		print("Generating server keys ...")
		pub_key = MP_SRV_KEYS + "/server_pub.pem"
		pri_key = MP_SRV_KEYS + "/server_pri.pem"
		if not os.path.exists(pub_key) and not os.path.exists(pri_key):
			if conf["settings"]["server"]["autoGenServerKeys"]:
				rsaKeys = self.genServerKeys()
				with open(pri_key, 'w') as the_pri_file:
					the_pri_file.write(rsaKeys[0])
				with open(pub_key, 'w') as the_pub_file:
					the_pub_file.write(rsaKeys[1])
				conf["settings"]["server"]["priKey"] = pri_key
				conf["settings"]["server"]["pubKey"] = pub_key
		else:
			print("Server RSA Keys already exist.")

		print("Write MPConfigDefaults")
		print(conf["settings"]["server"])
		self.writeConfig(conf)

	def writeFlaskConfig(self, key, value):
		if type(value) == bool:
			keyVal = "%s=%s\n" % (key,value)
		else:
			keyVal = "%s=\"%s\"\n" % (key,value)

		f = open(self.ws_alt_conf,'a')
		if(os.path.getsize(self.ws_alt_conf) > 0):
			f.write("\n"+keyVal)
		else:
			f.write(keyVal)

		f.close()

	def configAgentRequirements(self):

		os.system('clear')
		print("Configure Agent Connection Settings...")
		print("")
		print("")
		print("Verify the client id is a valid client id before processing request.")
		verify_clientid = input("Verify Client ID on requests [Y]?:").upper() or "Y"
		print("")
		print("")
		print("Verify client signature on api requests. Client must be registered in order to work.")
		verify_signature = input("Verify request signatures [Y]?:").upper() or "Y"
		print("")
		print("")
		save_answer = input("Would you like the save these settings [Y]?:").upper() or "Y"
		if save_answer == "Y":
			if verify_clientid == "Y":
				self.writeFlaskConfig('VERIFY_CLIENTID',True)
			else:
				self.writeFlaskConfig('VERIFY_CLIENTID',False)

			if verify_signature == "Y":
				self.writeFlaskConfig('REQUIRE_SIGNATURES',True)
			else:
				self.writeFlaskConfig('REQUIRE_SIGNATURES',False)

		else:
			return self.configAgentRequirements()

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

def main():
	'''Main command processing'''

	parser = argparse.ArgumentParser(description='Process some args.')
	group = parser.add_mutually_exclusive_group(required=True)
	group.add_argument('--setup', help="Setup Services", required=False, action='store_true')
	group.add_argument('--config-mpadmin', help="Setup MPAdmin", required=False, action='store_true')
	group.add_argument('--config-database', help="Setup Database", required=False, action='store_true')
	group.add_argument('--config-ldap', help="Setup LDAP/AD", required=False, action='store_true')
	group.add_argument('--config-api', help="Setup API Requirements", required=False, action='store_true')
	group.add_argument('--load', help="Load/Start Services", required=False)
	group.add_argument('--cron', help="Load/Start Cron Services", required=False)
	group.add_argument('--unload', help='Unload/Stop Services', required=False)
	group.add_argument('--permissions', help='Reset permissions', required=False)
	args = parser.parse_args()

	if args.permissions == True:
		repairPermissions()
		return

	if args.config_mpadmin != False:
		_adm = MPAdmin()
		_adm.configAdminUser()
		sys.exit()

	if args.config_database != False:
		_db = MPDatabase()
		_db.configDatabase()
		sys.exit()

	if args.config_ldap != False:
		_ldap = MPLdap()
		_ldap.configLdap()
		sys.exit()

	if args.config_api != False:
		_api = MPConfigDefaults()
		_api.configAgentRequirements()
		sys.exit()

	if args.setup != False:
		# First Repair permissions
		repairPermissions()

		srvconf = MPConfigDefaults()
		srvconf.genConfigDefaults()

		adm = MPAdmin()
		adm.configAdminUser()

		db = MPDatabase()
		db.configDatabase()

		ldap = MPLdap()
		ldap.configLdap()

		os.system('clear')
		srvList = setupServices()

		print("Write Service List")
		if os_type == 'Darwin':
			_enabled_services = {"Darwin": {"services": list(srvList)} }
		else:
			_enabled_services = {"Linux": {"services": list(srvList)} }

		writeJSON(_enabled_services,MP_SRVC_FILE)

	_srvs = readServicesConfig(os_type)
	if args.load != None:
		if _srvs:
			if os_type == 'Linux':
				linuxLoadServices(_srvs)
			else:
				osxLoadServices(_srvs)
		else:
			if os_type == 'Linux':
				linuxLoadServices(args.load)
			else:
				osxLoadServices(args.load)

	elif args.unload != None:
		if _srvs:
			if os_type == 'Linux':
				linuxUnLoadServices(_srvs)
			else:
				osxUnLoadServices(_srvs)
		else:
			if os_type == 'Linux':
				linuxUnLoadServices(args.load)
			else:
				osxUnLoadServices(args.load)

	# CRON Tab Additions
	if args.cron != None:
		if os_type == 'Linux':
			linuxLoadCronServices(args.cron)


def usage():
	print("Setup.py --setup or --load/--unload [All - Service]\n")
	print("\t--setup\t\tSetup all services to start on boot and any configuration needed. Will load selected services.")
	print("\t--load\t\tLoads a Service or All services with the key word 'All'")
	print("\t--unload\tUn-Loads a Service or All services with the key word 'All'\n")


if __name__ == '__main__':
	main()
