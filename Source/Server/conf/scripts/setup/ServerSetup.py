#!/opt/MacPatch/Server/env/server/bin/python3

'''
 Copyright (c) 2024, Lawrence Livermore National Security, LLC.
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
  MacPatch Version 3.8.x

  Script Version 2.4.3
'''

import os
import platform
import argparse
import pwd
import grp
import shutil
import json
import getpass
import types
from packaging.version import Version
import sys
from sys import exit
from Crypto.PublicKey import RSA
from dotenv.main import dotenv_values
from dotenv import set_key
import distro

# ----------------------------------------------------------------------------
# Script Requires ROOT
# ----------------------------------------------------------------------------
if os.geteuid() != 0:
	exit("\nYou must be an admin user to run this script.\nPlease re-run the script using sudo.\n")

# ----------------------------------------------------------------------------
# Variables
# ----------------------------------------------------------------------------
MP_BASE			= "/opt/MacPatch"
MP_SRV_BASE		= MP_BASE+"/Server"
MP_SRV_APPS		= MP_SRV_BASE+"/apps"
MP_SRV_ETC		= MP_SRV_BASE+"/etc"
MP_FLASK_FILE	= MP_SRV_BASE+"/apps/config.cfg"
MP_CONF_FILE	= MP_SRV_BASE+"/etc/siteconfig.json"
MP_SRVC_FILE	= MP_SRV_BASE+"/etc/.mpservices.json"

MP_FLASK_GLOBAL		= '.mpglobal'
MP_FLASK_CONSOLE	= '.mpconsole'
MP_FLASK_API		= '.mpapi'

MP_SRV_CONF		= MP_SRV_BASE+"/conf"
MP_SRV_CONT		= MP_BASE+"/Content/Web"
MP_INV_DIR		= MP_SRV_BASE+"/InvData"
MP_SRV_KEYS		= MP_SRV_ETC +"/keys"

os_type 		= platform.system()
system_name 	= platform.uname()[1]
distro_name		= None
distro_version	= distro.version()
gUID 			= 79
gGID 			= 70
cronList		= []


if sys.platform.startswith('linux'):
	# Normalize Distro Name
	_distName = distro.name()
	if 'redhat' in _distName.lower() or 'red hat' in _distName.lower():
		distro_name = 'redhat'
	elif 'cent' in _distName.lower():
		distro_name = 'centos'
	else:
		distro_name = _distName.lower()

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


macServices=[{'name': 'MPInventoryD', 'value': 'gov.llnl.mp.invd.plist'}, {'name': 'MPAPI', 'value': 'gov.llnl.mp.py.api.plist'},
			 {'name': 'MPConsole', 'value': 'gov.llnl.mp.py.console.plist'},{'name': 'MPNginx', 'value': 'gov.llnl.mp.nginx.plist'},
			 {'name': 'MPRsyncServer', 'value': 'gov.llnl.mp.rsync.plist'},{'name': 'MPSyncContent', 'value': 'gov.llnl.mp.sync.plist'},
			 {'name': 'MPPatchLoader', 'value': 'gov.llnl.mp.sus.sync.plist'}]

lnxServices=["MPInventoryD","MPAPI","MPConsole","MPNginx","MPRsyncServer"]
lnxCronSrvs=["MPPatchLoader","MPSyncContent"]
# For Argparse
mac_svc = ("MPApi", "MPConsole", "MPInventoryD", "MPNginx", "MPRsyncServer", "MPSyncContent", "MPPatchLoader", "All")
lnx_svc = ("MPApi", "MPConsole", "MPInventoryD", "MPNginx", "MPRsyncServer", "All")

# ----------------------------------------------------------------------------
# Read and write new flask config data from dot file
# ----------------------------------------------------------------------------
def cleanValue(value):
	if value.isdigit():
		return int(value)
	elif value.lower() in ['true', 'yes', 'on']:
		return True
	elif value.lower() in ['false', 'no', 'off']:
		return False
	elif value.lower() in ['none', '', 'empty']:
		return None
	else:
		return value

class convert_to_dot_notation(dict):
	"""
	Access dictionary attributes via dot notation
	"""

	__getattr__ = dict.get
	__setattr__ = dict.__setitem__
	__delattr__ = dict.__delitem__

def readDotConfig(dot_file_name):
	dotFile = os.path.join(MP_SRV_APPS, dot_file_name)
	_dict = dict(dotenv_values(dotFile))

	for key, value in _dict.items():
		_dict[key] = cleanValue(value)
	return convert_to_dot_notation(_dict)

def writeKeyValueToDotConfig(dot_file_name, key, value):
	dotFile = os.path.join(MP_SRV_APPS, dot_file_name)
	set_key(dotenv_path=dotFile, key_to_set=key, value_to_set=value)

def saveDotConfig(dot_file_name, config):
	for key, value in config.items():
		writeKeyValueToDotConfig(dot_file_name, key, value)

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
		print(f"ERROR: {MP_SRVC_FILE} not found.")
		return _conf

	if platformType in _conf:
		if 'services' in _conf[platformType]:
			return _conf[platformType]['services']
	else:
		print(f"ERROR: {platformType} not found in services config {MP_SRVC_FILE}.")
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

def linuxServices(service, action):
	useSYSTEMD=False
	if distro_name == "ubuntu" and Version(distro_version) >= Version("15.0"):
		useSYSTEMD=True
	elif (distro_name == "redhat" or distro_name == "centos") and Version(distro_version) >= Version("8.0"):
		useSYSTEMD=True
	else:
		print(f"ERROR: Unable to {action} service(s). OS({distro_name}) is unsupported.")
		return

	# Define the list of services
	_services = list()
	if service == "All":
		_srvs = readServicesConfig(os_type)
		if _srvs and isinstance(_srvs, list):
			_services = _srvs
		else:
			_ask = input(f"No Services Are Defined. All services will be {action}. Not recommended [Y/N]:").upper() or "N"
			if _ask:
				_services = lnxServices
			else:
				print(f"It is recommended to enable the services you wish to run. The --service {service} -a {action} will be more useful.")
				return
	else:
		if service in lnxServices:
			_services.append(service)

	# Perform action for each service given
	for s in _services:
		serviceName=service+".service"
		etcServiceConf="/etc/systemd/system/"+serviceName

		if os.path.exists(etcServiceConf):
			print(f"systemctl {action} {serviceName}")
			cmd = f"/bin/systemctl {action} {serviceName}"
			os.system(cmd)
		else:
			print("ERROR: Unable to find {etcServiceConf}. Can not {action} service.")

def linuxLoadCronServices(service):
	from crontab import CronTab
	cron = CronTab()

	if service == "MPSyncContent":
		print("Loading MPSyncContent")

		cmd = MP_SRV_CONF + '/scripts/MPSyncContent.py --config ' + MP_SRV_BASE + '/etc/syncContent.json'
		job  = cron.new(command=cmd)
		job.set_comment("MPSyncContent")
		job.minute.every(30)
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

def osxServices(service, action):
	# Define the list of services
	_services = list()
	if service == "All":
		_srvs = readServicesConfig(os_type)
		if _srvs and isinstance(_srvs, list):
			_services = _srvs
		else:
			_ask = input(f"No Services Are Defined. All services will be {action}. Not recommended [Y/N]:").upper() or "N"
			if _ask:
				_services = [d['value'] for d in macServices]
			else:
				print(f"It is recommended to enable the services you wish to run. The --service {service} -a {action} will be more useful.")
				return
	else:
		for srvcDict in macServices:
			if service in srvcDict['name']:
				_services.append(srvcDict['value'])
		

	for s in _services:
		_launchdFile = "/Library/LaunchDaemons/"+s
		if os.path.exists(_launchdFile):
			print(f"Loading service {s}")
			cmd = f"/bin/launchctl load -w /Library/LaunchDaemons/{s}"
			os.system(cmd)
		else:
			print(f"ERROR: {s} has not been enabled with launchd. Service can not {action}.")
			return

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
			linkStartupScripts('MPInventoryD')
			srvsList.append('MPInventoryD')
			linkStartupScripts('MPNginx')
			srvsList.append('MPNginx')
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
			linkStartupScripts('MPNginx')
			srvsList.append('MPNginx')
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
			linkStartupScripts('MPRsyncServer')
			linkStartupScripts('MPRsyncServer@','copy')
			linkStartupScripts('MPRsyncServer','copy','socket')
			srvsList.append('MPRsyncServer')

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

	return set(srvsList)

def linkStartupScripts(service,action='enable',altType=None):

	print("Copy Startup Script for "+service)
	useSYSTEMD=False

	if distro_name == "ubuntu" and Version(distro_version) >= Version("15.0"):
		useSYSTEMD=True
	elif (distro_name == "redhat" or distro_name == "centos") and Version(distro_version) >= Version("8.0"):
		useSYSTEMD=True
	else:
		print(f"Unable to start service ({service}) at start up. OS({distro_name}) is unsupported.")
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
			print(f"COULD NOT LOAD: {MPAdmin.config_file}")
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
# DB Config Class
# ----------------------------------------------------------------------------

class MPDatabase:

	def configDatabase(self):
		conf = readDotConfig(MP_FLASK_GLOBAL)
		system_name = platform.uname()[1]
		_new_config = {}

		os.system('clear')
		print("Configure MacPatch Database Info...")
		mp_db_hostname = input("MacPatch Database Server Hostname:  [" + str(system_name) + "]: ") or str(system_name)
		_new_config["DB_HOST"] = mp_db_hostname

		mp_db_port = input("MacPatch Database Server Port Number [3306]: ") or "3306"
		_new_config["DB_PORT"] = mp_db_port

		mp_db_name = input("MacPatch Database Name [MacPatchDB3]: ") or "MacPatchDB3"
		_new_config["DB_NAME"] = mp_db_name

		mp_db_usr = input("MacPatch Database User Name [mpdbadm]: ") or "mpdbadm"
		_new_config["DB_USER"] = mp_db_usr

		mp_db_pas = getpass.getpass('MacPatch Database User (' +mp_db_usr+ ') Password:')
		_new_config["DB_PASS"] = mp_db_pas

		save_answer = input("Would you like the save these settings [Y]?:").upper() or "Y"
		if save_answer == "Y":
			saveDotConfig(MP_FLASK_GLOBAL, _new_config)
		else:
			return self.configDatabase()

# ----------------------------------------------------------------------------
# LDAP Config Class
# ----------------------------------------------------------------------------

class MPLdap:

	def configLdap(self):
		conf = readDotConfig(MP_FLASK_GLOBAL)
		_new_config = {}

		os.system('clear')
		print("Configure MacPatch Login Source...")
		use_ldap = input("Would you like to use Active Directory/LDAP for login? [Y]:").upper() or "Y"

		if use_ldap == "Y":
			ldap_hostname = input("Active Directory/LDAP server hostname: ")
			_new_config['LDAP_SRVC_SERVER'] = ldap_hostname

			print(f"Is {ldap_hostname} a DNS round robin?")
			ldap_roundrobin = input(f"Is {ldap_hostname} a DNS round robin (Default is No)? [Y/N]: ").upper() or "N"
			if ldap_roundrobin == "Y":
				_new_config['LDAP_SRVC_MULTISERVER'] = 'yes'
			else:
				_new_config['LDAP_SRVC_MULTISERVER'] = 'no'
				
			_new_config['LDAP_SRVC_POOL_TYPE'] = 'first'

			print("Common ports for LDAP non secure is 389, secure is 636.")
			ldap_port = input("Active Directory/LDAP server port number: ")
			_new_config['LDAP_SRVC_PORT'] = ldap_port

			use_ldap_ssl = input("Active Directory/LDAP use ssl? [Y]: ").upper() or "Y"
			if use_ldap_ssl == "Y":
				_new_config['LDAP_SRVC_SSL'] = 'yes'
			else:
				_new_config['LDAP_SRVC_SSL'] = 'no'

			ldap_searchbase = input("Active Directory/LDAP Search Base: ")
			_new_config['LDAP_SRVC_SEARCHBASE'] = ldap_searchbase

			ldap_userdn = input("Active Directory/LDAP User DN: ")
			_new_config['LDAP_SRVC_USERDN'] = ldap_userdn

			ldap_userpass = input("Active Directory/LDAP User Password: ")
			_new_config['LDAP_SRVC_PASS'] = ldap_userpass

			_new_config['LDAP_SRVC_ENABLED'] = 'yes'
			

			save_answer = input("Would you like the save these settings [Y]?:").upper() or "Y"
			if save_answer == "Y":
				saveDotConfig(MP_FLASK_GLOBAL, _new_config)
			else:
				return self.configLdap()

		else:
			_new_config['LDAP_SRVC_ENABLED'] = 'no'
			saveDotConfig(MP_FLASK_GLOBAL, _new_config)

# ----------------------------------------------------------------------------
# MP Set Default Config Data
# ----------------------------------------------------------------------------

class MPConfigDefaults:

	def __init__(self):
		MPConfigDefaults.config_file = MP_CONF_FILE

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
				with open(pri_key, 'wb') as the_pri_file:
					the_pri_file.write(rsaKeys[0])
				with open(pub_key, 'wb') as the_pub_file:
					the_pub_file.write(rsaKeys[1])
				conf["settings"]["server"]["priKey"] = pri_key
				conf["settings"]["server"]["pubKey"] = pub_key
		else:
			print("Server RSA Keys already exist.")

		print("Write MPConfigDefaults")
		print(conf["settings"]["server"])
		self.writeConfig(conf)

	def configAgentRequirements(self):
		_new_conf = {}
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
				_new_conf['VERIFY_CLIENTID'] = 'yes'
			else:
				_new_conf['VERIFY_CLIENTID'] = 'no'

			if verify_signature == "Y":
				_new_conf['REQUIRE_SIGNATURES'] = 'yes'
			else:
				_new_conf['REQUIRE_SIGNATURES'] = 'no'

			saveDotConfig(MP_FLASK_API,_new_conf)
		else:
			return self.configAgentRequirements()

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

def main():
	'''Main command processing'''
	parser = argparse.ArgumentParser(description='MacPatch Server Setup')
	setup_group = parser.add_argument_group('First time setup of all components')
	setup_group.add_argument("--setup", help="Setup All Components", required=False, action='store_true')

	config_group = parser.add_argument_group('Component Configuration')
	config_group.add_argument("--config", dest="configArg", choices=("admin", "database", "ldap", "api"), help="admin/database/ldap/api the confiduration to be edited.", required=False)

	services_group = parser.add_argument_group('Services')
	if os_type == 'Darwin':
		services_group.add_argument('--service', choices=mac_svc, help="Defines service name and -a arg is required for the action.")
	else:
		services_group.add_argument('--service', choices=lnx_svc, help="Defines service name and -a arg is required for the action.")
		
	services_group.add_argument('-a', '--action', required='--service' in sys.argv, choices=("start", "stop")) #only required if --service is given

	services_group.add_argument("--cron", dest="cronArg", choices=("start", "stop"), help="start/stop all MacPatch cron jobs", required=False)
	services_group.add_argument('--enable-services', help='Select from list of MacPatch server services to enable.', action='store_true')
	services_group.add_argument('--disable-services', help='Select from list of MacPatch server services to disable.', action='store_true')

	other_group = parser.add_argument_group('Other Actions')
	other_group.add_argument('--permissions', help='Reset permissions', required=False, action='store_true')
	args = parser.parse_args()

	if args.permissions == True:
		repairPermissions()
		return
	
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

	if args.configArg is not None:
		if args.configArg == 'admin':
			_adm = MPAdmin()
			_adm.configAdminUser()
			sys.exit()
		elif args.configArg == 'database':
			_db = MPDatabase()
			_db.configDatabase()
			sys.exit()
		elif args.configArg == 'ldap':
			_ldap = MPLdap()
			_ldap.configLdap()
			sys.exit()
		elif args.configArg == 'api':
			_api = MPConfigDefaults()
			_api.configAgentRequirements()
			sys.exit()
		
	if args.service is not None:
		if os_type == 'Linux':
			linuxServices(args.service,args.action)
		elif os_type == 'Darwin':
			osxServices(args.service,args.action)

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
