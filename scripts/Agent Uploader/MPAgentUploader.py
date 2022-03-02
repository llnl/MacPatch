#!/usr/bin/env python3

from ast import arg
import subprocess
import shutil
import os, fnmatch
import plistlib
import hashlib
import tempfile
import pathlib
import requests
import argparse
import getpass
import json
import uuid
import time
import base64
import configparser
from datetime import datetime

import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

AGENT_DICTIONARY = {}
UPDATER_DICTIONARY = {}

PLUGINS_DIRECTORY = None
MIGRATION_PLIST = None
REGISTRATION_KEY = None
PKG_TMP_DIR = None
PKG_DEST_DIR = None
AGENT_PACKAGE_PATH = None

API_USR_NAME = None
API_USR_PASS = None
API_TOKEN    = "NA"

USE_SSL = True
MP_SERVER = None
MP_PORT = 3600
URI_PREFIX = "/api/v1"
UPLOAD_PKGS = True

# Sign PKG
SIGN_PKG = True
SIGN_IDENTITY = None

# Notorize PKG
NOTORIZE = True

# the email address of your developer account
DEV_ACCOUNT = None
# the 10-digit team id
DEV_TEAM = None
# the label of the keychain item which contains an app-specific password
DEV_KEYCHAIN_LABEL = None
# the apple id app-specific password
APPLE_ID_APP_PASSWORD = None


version="1.0"
identifier="gov.llnl.mp.pkg"
productname="MacPatch"

class Notorize:

	def __init__(self, user, passwd):
		self.user = user
		self.passwd = passwd

	def notarizePackage(self, package, bundleID):
		print("Begin notorization of {}".format(package))
		_requestUUID = None
		cli_args = ['/usr/bin/xcrun', 'altool', '--notarize-app', '--primary-bundle-id', bundleID, '--username', self.user, '--password', self.passwd, '--file', package]
		res = subprocess.run(cli_args, stdout=subprocess.PIPE, text=True)
		lines = res.stdout.split('\n')
		for line in lines:
			if "RequestUUID" in line:
				_requestUUID = line.split('=')[1].strip()
				print("RequestUUID: {}".format(_requestUUID))
				break

		if _requestUUID is None:
			print("Could not upload for notarization")
			return

		print('Notorization is in progress. Please be patient as this can take some time.')
		tryAgainOnErrorResponse = True
		request_status = "in progress"
		while request_status == "in progress":
			print('Waiting 20 seconds ...')
			time.sleep(20)
			rs = self.requestStatus(_requestUUID)
			print("Status: "+rs)
			if "Error:" in rs:
				if tryAgainOnErrorResponse:
					print("Error on response, will wait and try one more time.")
					tryAgainOnErrorResponse = False
			else:
				request_status = rs

		if request_status != "success":
			print("Error could not notarize {}".format(package))
			print("{}".format(' '.join([str(elem) for elem in cli_args])))
			return

	def requestStatus(self, requestUUID):
		result = "NA"
		cli_args = ["/usr/bin/xcrun", "altool", "--notarization-info", requestUUID, '--username', self.user, '--password', self.passwd]
		res = subprocess.run(cli_args, stdout=subprocess.PIPE, text=True)
		lines = res.stdout.split('\n')
		for line in lines:
			if "Status:" in line:
				result = line.split(':')[1].strip()
				break

		return result

'''
Make Auth Request for token
'''
def makeAuthRequest(authUser, authPass):
	print("Getting API Token ...")
	global API_TOKEN
	API_TOKEN = "NA" # Reset value

	result = False
	_ssl = "http"
	if USE_SSL:
		_ssl = "https"

	_url = "{}://{}:{}{}/auth/token".format(_ssl,MP_SERVER,MP_PORT,URI_PREFIX)
	_params = {'authUser': authUser, 'authPass': authPass}

	try:
		_response = requests.post(_url, json=_params, verify=False)
		if(_response.ok):
			res = _response.json()
			_resDict = res["result"]
			if "token" in _resDict:
				API_TOKEN = _resDict['token']
				result = True

		return result

	except requests.exceptions.HTTPError as err:
		print ("Http Error:",err)
	except requests.exceptions.ConnectionError as errc:
		print ("Error Connecting:",errc)
	except requests.exceptions.Timeout as errt:
		print ("Timeout Error:",errt)
	except requests.exceptions.RequestException as err:
		print ("Ops: Something Else",err)

	return result

'''
Query Web API to see if auth token is valid

- parameter token: auth token
- returns: Bool
'''
def isTokenValid(token):
	global USE_SSL,MP_SERVER,MP_PORT,URI_PREFIX
	result = False
	_ssl = "http"
	if USE_SSL:
		_ssl = "https"

	_url = "{}://{}:{}{}/token/valid/{}".format(_ssl,MP_SERVER,MP_PORT,URI_PREFIX,token)
	
	try:
		_response = requests.get(_url, verify=False)
		_response.raise_for_status()
		if(_response.ok):
			res = _response.json()
			result = bool(res["result"])
			return result

	except requests.exceptions.HTTPError as err:
		print ("Http Error:",err)
	except requests.exceptions.ConnectionError as errc:
		print ("Error Connecting:",errc)
	except requests.exceptions.Timeout as errt:
		print ("Timeout Error:",errt)
	except requests.exceptions.RequestException as err:
		print ("OOps: Something Else",err)

	return result

'''
Get Agent Configuration Data from Web API

- parameter token  auth token
- returns: Dictionary of result
'''
def getAgentConfigurationData(token):
	global USE_SSL,MP_SERVER,MP_PORT,URI_PREFIX

	result = None
	_ssl = "http"
	if USE_SSL:
		_ssl = "https"

	_url = "{}://{}:{}/api/v2/agent/config/{}".format(_ssl,MP_SERVER,MP_PORT,token)
	try:
		_response = requests.get(_url, verify=False)
		_response.raise_for_status()
		if(_response.ok):
			result = _response.json()
			return result['result']

	except requests.exceptions.HTTPError as err:
		print ("Http Error:",err)
	except requests.exceptions.ConnectionError as errc:
		print ("Error Connecting:",errc)
	except requests.exceptions.Timeout as errt:
		print ("Timeout Error:",errt)
	except requests.exceptions.RequestException as err:
		print ("OOps: Something Else",err)

	return result

'''
Get Array of PKG's from a path

- parameter path: Directory Path
- returns: Array of Strings
'''
def getPackagesFromArchiveDir(path):
	result = []
	x = fnmatch.filter(os.listdir(path), '*.pkg')
	for r in x:
		result.append(os.path.join(path,r))

	if len(result) == 0:
		return None
	else:
		return result

'''
Extract Zipped Package and Expand the Package

- parameter package: Zip Package path
- returns: Boolean if succeeds
'''
def extractAgentPKG(package, destDir=None):
	global PKG_TMP_DIR

	now = datetime.now() # current date and time
	_dts = now.strftime("%Y%m%d%H%M%S")
	if destDir is not None:
		tmpDir = os.path.join(destDir, "Completed", "MacPatch_{}".format(_dts))
	else:
		tmpDir = os.path.join('/private/var/tmp', "MacPatch_{}".format(_dts))

	PKG_TMP_DIR = tmpDir

	# Extract packages
	cli_args = ["/usr/bin/ditto", "-x", "-k", package, tmpDir]
	res = subprocess.run(cli_args)

	if res.returncode != 0:
		print("Error extracting package. The exit code was: %d" % res.returncode)
		return False

	# Expand package
	_pkgPath = pathlib.PurePath(package)
	pkgName = os.path.splitext(os.path.join(tmpDir,_pkgPath.name))[0]
	expandedPkgDir = os.path.join(tmpDir,"MacPatch")

	cli_args = ["/usr/sbin/pkgutil", "--expand", pkgName, expandedPkgDir]
	res = subprocess.run(cli_args)

	if res.returncode != 0:
		print("Error expanding package. The exit code was: %d" % res.returncode)
		return False
	else:
		if os.path.isfile(pkgName):
			os.remove(pkgName)
		else:    ## Show an error ##
			print("Error: %s file not found" % pkgName)

	return True

'''
Write MP Server Env Public Key to packages

- parameter packages: Array of packages
- parameter pubKey: plublic key string
- parameter keyHash: md5 hash of the key
- returns: Boolean if succeeds
'''
def writeServerPubKeyToPackage(packages, pubKey, keyHash):

	for p in packages:
		if "Base.pkg" in p or "Client.pkg" in p:
			scripts_dir = os.path.join(p,"Scripts")
			if not os.path.exists(scripts_dir):
				os.makedirs(scripts_dir)

			_keyFile = os.path.join(p,"Scripts/ServerPub.pem")
			f = open(_keyFile, "w")
			f.write(pubKey)
			f.close()

			_keyFileHash = hashlib.md5(open(_keyFile,'rb').read()).hexdigest()
			# Check hash
			if _keyFileHash.lower() == keyHash.lower():
				return True
			else:
				print("writeServerPubKeyToPackage failed hash check.")

	return False

'''
Write plist data to Package
- parameter packages: Array of packages
- parameter plist: plist data
- returns: Boolean if succeeds
'''
def writePlistToPackage(packages, plistData):
	global MIGRATION_PLIST

	for p in packages:
		if "Base.pkg" in p or "Client.pkg" in p:
			scripts_dir = os.path.join(p,"Scripts")
			if not os.path.exists(scripts_dir):
				os.makedirs(scripts_dir)

			plistFile = os.path.join(p,"Scripts/gov.llnl.mpagent.plist")
			with open(plistFile, 'wb') as fp:
				plistlib.dump(plistData, fp)

		elif "Updater.pkg" in p:
			if MIGRATION_PLIST is not None:
				scripts_dir = os.path.join(p,"Scripts")
				if not os.path.exists(scripts_dir):
					os.makedirs(scripts_dir)

				plistFile = os.path.join(p,"Scripts/migration.plist")
				shutil.copy2(MIGRATION_PLIST, plistFile)

	return True

'''
Get Array of plugins from a path

- parameter path: Directory Path
- returns: Array of Strings
'''
def getPluginsFromDirectory(path):
	x = []
	x = fnmatch.filter(os.listdir(path), '*.bundle')
	return x

'''Write plugins to Package

- parameter packages: Array of packages
- parameter plugins: directory containing plugins

- returns: Boolean if succeeds
'''
def writePluginsToPackage(packages, plugins_dir):

	for p in packages:
		if "Base.pkg" in p or "Client.pkg" in p:
			plugin_dir = os.path.join(p,"Scripts/Plugins")
			if not os.path.exists(plugin_dir):
				os.makedirs(plugin_dir)

			plugins = getPluginsFromDirectory(plugins_dir)
			if len(plugins) >= 1:
				print("Copy plugins...")
				for plugin in plugins:
					src_plugin_path = os.path.join(PLUGINS_DIRECTORY,plugin)
					dst_plugin_path = os.path.join(plugin_dir,plugin)
					if os.path.isdir(src_plugin_path):
						print("Copy {} to {}".format(plugin,plugin_dir))
						shutil.copytree(src_plugin_path, dst_plugin_path)
					else:
						if not os.path.exists(d):
							print("Copy {} to {}".format(plugin,plugin_dir))
							shutil.copy2(src_plugin_path, dst_plugin_path)

	return True

'''
Write version info plist to package. Also populates dictionaries for
post to web api durning upload

- parameter packages: package path
- parameter version_file: version file

- returns: Boolean if succeeds
'''
def writeVersionInfoToPackage(package, version_file):
	global AGENT_DICTIONARY, UPDATER_DICTIONARY

	type = None
	base_dict = {}
	ver_dict = {}
	with open(version_file, 'rb') as fp:
		info_dict = plistlib.load(fp)

	if "Base.pkg" in package:
		if "Agent" in info_dict:
			ver_dict = info_dict['Agent']
			type = 'app'
	elif "Updater.pkg" in package:
		if "Updater" in info_dict:
			ver_dict = info_dict['Updater']
			type = 'update'
	else:
		print("Err")

	vers = None
	if "agent_version" in ver_dict:
		vers = ver_dict['agent_version'].split(".")

		base_dict["framework"] = "0"
		base_dict["build"] = ver_dict["build"]
		base_dict["major"] = vers[0]
		base_dict["minor"] = vers[1]
		base_dict["bug"] = vers[2]
		base_dict["version"] = ver_dict["version"]

		# Write Plist to package
		plistFile = os.path.join(package, "Scripts/.mpVersion.plist")
		print("Write version info to {}".format(plistFile))
		with open(plistFile, 'wb') as fp:
			plistlib.dump(base_dict, fp)

		# Set Data needed for agent upload
		base_dict["pkg_name"] = os.path.basename(os.path.normpath(package))
		base_dict["type"] = type
		base_dict["osver"] = ver_dict["osver"]
		base_dict["agent_ver"] = ver_dict["agent_version"]
		base_dict["ver"] = ver_dict["version"]

		if type == "app":
			AGENT_DICTIONARY = base_dict
		else:
			UPDATER_DICTIONARY = base_dict

	return True

'''
Write registration key to file in package

- parameter packages: package array
- parameter regKey: registration key string
- returns: Boolean if succeeds
'''
def writeRegKeyToPackage(packages, regKey):
	if len(packages) <= 0:
		return False

	if regKey is None:
		return False

	for p in packages:
		if "Base.pkg" in p or "Client.pkg" in p:
			scriptsDir = os.path.join(p, "Scripts")
			regFile = os.path.join(p, "Scripts", ".mpreg.key")
			if os.path.exists(scriptsDir):
				f = open(regFile, "a")
				f.write(regKey)
				f.close()

				return True

	return False

'''
Flatten Package

 - parameter package: path of package to flatten
 - parameter flatten_package: the resulting flattened package
 - returns: Bool
'''
def flattenPackage(pkgPath, flattenPkgPath):
	cli_args = ["/usr/sbin/pkgutil", "--flatten", pkgPath, flattenPkgPath]
	res = subprocess.run(cli_args)

	if res.returncode == 0:
		return True
	else:
		print("The exit code was: %d" % res.returncode)
		return False

'''
Code Sign Package

 - parameter package: path of package to sign
 - returns: Bool
'''
def signPackage(pkgPath, signingIdentity):
	print("Signing {}".format(pkgPath))
	signed_pkg_name = pkgPath.replace("toSign_", "")
	cli_args = ["/usr/bin/productsign", "--sign", signingIdentity, pkgPath, signed_pkg_name]
	res = subprocess.run(cli_args,stdout=subprocess.DEVNULL)

	if res.returncode == 0:
		return True
	else:
		print("{} was not signed.".format(signed_pkg_name))
		print("The exit code was: %d" % res.returncode)
		return False

'''
Flatten Packages for distribution, if signing is turned on
packages will be signed as well.

- parameter packages: array of package paths
- returns: Array of flatten packages
'''
def flattenPackages(packages, working_dir):
	global SIGN_PKG
	_flat_packages = []

	for p in packages:
		pkg_name = None
		flatten_pkg_path = None

		# Assign the name
		if SIGN_PKG:
			pkg_name = "toSign_{}".format(pathlib.PurePath(p).name)
		else:
			pkg_name = pathlib.PurePath(p).name

		# Create path for flat pkg
		if pathlib.Path(p).suffix == ".pkg":
			flatten_pkg_path = os.path.join(working_dir, pkg_name)
		else:
			flatten_pkg_path = os.path.join(working_dir, pkg_name + ".pkg")

		# Flatten Package
		if not flattenPackage(p, flatten_pkg_path):
			print("Error flattening package {}".format(p))

		if SIGN_PKG:
			signPackage(flatten_pkg_path, SIGN_IDENTITY)

		_flat_packages.append(flatten_pkg_path)

	return _flat_packages

'''
Compress Package

 - parameter packages: array of packages
 - returns: Bool
 '''
def compressPackage(pkgPath):
	print("Compressing {}".format(pkgPath))
	compressed_pkg = "{}.zip".format(pkgPath)
	cli_args = ["/usr/bin/ditto", "-c", "-k", pkgPath, compressed_pkg]
	res = subprocess.run(cli_args)
	if res.returncode == 0:
		return True
	else:
		return False

'''
Change the background image
post to web api durning upload

- parameter path: base dir for Background images
- returns: Boolean if succeeds
'''
def changeBackgroundImageToDoneImage(path):
	image = os.path.join(path, "Resources/Background.png")
	image_done = os.path.join(path, "Resources/Background_done.png")
	if os.path.exists(image) and os.path.exists(image_done):
		os.remove(image)
		shutil.copy2(image_done, image)

	return True

'''
Process the agent package from the MPClientBuild script

'''
def processAgentPackage():
	global API_USR_NAME, API_USR_PASS, API_TOKEN, AGENT_PACKAGE_PATH, PKG_TMP_DIR, PKG_DEST_DIR
	global DEV_ACCOUNT, APPLE_ID_APP_PASSWORD, NOTORIZE
	global AGENT_DICTIONARY, UPDATER_DICTIONARY, PLUGINS_DIRECTORY

	if API_USR_NAME is None:
		print("processAgentPackage")
		API_USR_NAME = input("API User Name: ")
	if API_USR_PASS is None:
		API_USR_PASS = getpass.getpass('Password:')

	print("Begin Processing Agent Packages")
	agent_config = None
	pubKey = None
	pubKeyHash = None
	formData = {"app": {}, "update": {}, "plugins": [], "profiles": [] }

	# --------------------------------------
	# Get Auth Token
	tokenResult = makeAuthRequest(API_USR_NAME, API_USR_PASS)
	if tokenResult == False:
		print("Error, failed to get auth token. Please verify user and password.")
		return

	# --------------------------------------
	# Download Agent Configuration Data
	agentConfig = None

	if API_TOKEN != "NA":
		print("Download agent configuration")
		agent_config_res = getAgentConfigurationData(API_TOKEN)
		if not agent_config_res:
			print("Error getting agent configuration, is None")
			return
		else:
			if "plist" in agent_config_res:
				_tmp_datafile = '/tmp/agentConfig.plist'
				if os.path.exists(_tmp_datafile):
					os.remove(_tmp_datafile) # Delete, dont want to append to file

				_agent_config_xml = agent_config_res['plist']
				f = open(_tmp_datafile, "x")
				f.write(_agent_config_xml)
				f.close()

				_dict = {}
				with open('/tmp/agentConfig.plist', 'rb') as fp:
					_dict = plistlib.load(fp)

				agent_config = _dict['default']

			else:
				print("Error agent configuration is missing plist key.")
				return

			if "pubKey" in agent_config_res:
				pubKey = agent_config_res['pubKey']
			else:
				print("Error agent configuration is missing pubkey.")
				return

			if "pubKeyHash" in agent_config_res:
				pubKeyHash = agent_config_res['pubKeyHash']
			else:
				print("Error agent configuration is missing pubKeyHash.")
				return

	else:
		print("Error, auth token is NA.")
		return

	# --------------------------------------
	# Unzip and extract packages
	print("Unzip and extract package")
	if os.path.exists(AGENT_PACKAGE_PATH) == False:
		print("Error agent package path is not defined or not found.")
		return
	
	print("PKG_DEST_DIR: "+ PKG_DEST_DIR)
	exRes = extractAgentPKG(AGENT_PACKAGE_PATH, PKG_DEST_DIR)
	if exRes == False:
		return

	# --------------------------------------
	# Write config data to packages
	print("Write config data to packages.")
	if PKG_TMP_DIR is None:
		print("Error package tmp dir is not defined.")
		return
	base_dir = os.path.join(PKG_TMP_DIR,"MacPatch")
	print("Working dir (base_dir) is {}".format(base_dir))

	packages = getPackagesFromArchiveDir(base_dir)
	if packages is None:
		print("Error no packages to process.")
		return

	# Write Server Public Key
	if not writeServerPubKeyToPackage(packages,pubKey,pubKeyHash):
		print("Error writing server public key data")
		return

	# Write config plist to packages
	if not writePlistToPackage(packages, agent_config):
		print("Error writing agent config data")
		return

	# Copy plugins to packages
	if PLUGINS_DIRECTORY is not None:
		if not writePluginsToPackage(packages, PLUGINS_DIRECTORY):
			print("Error copying plugins to packages.")

	#  Write Version info to packages
	ver_info_file = os.path.join(base_dir,"Resources/mpInfo.plist")
	if os.path.exists(ver_info_file):
		for p in packages:
			if not writeVersionInfoToPackage(p,ver_info_file):
				print("Error writing version info to packages.")

	# Write registration key to packages
	if REGISTRATION_KEY is not None:
		if not writeRegKeyToPackage(packages, REGISTRATION_KEY):
			print("Error writing registration key to packages.")

	# Apply Background image done
	if not changeBackgroundImageToDoneImage(base_dir):
		print("Error changing pkg backgground image.")

	# --------------------------------------
	# Flatten packages
	flatten_packages = []
	packages.append(base_dir)
	flatten_packages = flattenPackages(packages,PKG_TMP_DIR)

	n = None
	if NOTORIZE:
		n = Notorize(DEV_ACCOUNT, APPLE_ID_APP_PASSWORD)

	# --------------------------------------
	# Compress packages
	_finished_packages = []
	for f in flatten_packages:
		removePKG = False
		removePKGPath = f
		if "toSign_" in f:
			f = f.replace('toSign_', '')
			removePKG = True

		if NOTORIZE:
			print("Notarize ...")
			if "Base.pkg" in f:
				n.notarizePackage(f,"gov.llnl.mp.base.pkg")
			elif "Updater.pkg" in f:
				n.notarizePackage(f,"gov.llnl.mp.updater.pkg")
			elif "MacPatch.pkg" in f:
				n.notarizePackage(f,"gov.llnl.mp.pkg")

		if not compressPackage(f):
			print("Error compressing {}".format(f))
		else:
			_finished_packages.append(f+'.zip')
			if removePKG:
				os.remove(removePKGPath)

	# --------------------------------------
	# Post packages
	formData['app'] = AGENT_DICTIONARY
	formData['update'] = UPDATER_DICTIONARY

	# Data for uploading confirmed packages
	uploadData = {'pkgs':_finished_packages,'data':formData, 'token':API_TOKEN, 'pkgDir':PKG_TMP_DIR}
	uploadDataFile = os.path.join(PKG_TMP_DIR,'uploadData.json')
	with open(uploadDataFile, 'w') as outfile:
		json.dump(uploadData, outfile)

	if UPLOAD_PKGS:
		uploadPackagesToServer(_finished_packages, formData )
	else:
		print("Upload packages is disabled.")

	subprocess.run(['/usr/bin/open', PKG_TMP_DIR])


def uploadPackagesToServer(packages, formData):
	global API_USR_NAME, API_USR_PASS, API_TOKEN

	result = False
	_ssl = "http"
	if USE_SSL:
		_ssl = "https"

	aid = str(uuid.uuid4())
	_url = "{}://{}:{}/api/v3/agent/upload/{}/{}".format(_ssl,MP_SERVER,MP_PORT,aid,API_TOKEN)

	pkgs = []
	fileData = {}
	print("Processing packages for uploading to MacPatch server")
	for p in packages:
		if "Base.pkg" in p:
			baseFile = open(p, 'rb')
			fileData['fBase'] = ('Base.pkg.zip', baseFile, 'application/octet-stream')
		elif "Updater.pkg" in p:
			updateFile = open(p, 'rb')
			fileData['fUpdate'] = ('Updater.pkg.zip', updateFile, 'application/octet-stream')
		elif "MacPatch.pkg" in p:
			agentFile = open(p, 'rb')
			fileData['fComplete'] = ('MacPatch.pkg.zip', agentFile, 'application/octet-stream')

	_files = {'fBase': fileData['fBase'], 'fUpdate': fileData['fUpdate'], 'fComplete': fileData['fComplete'], 'jData': ('', json.dumps(formData), 'application/json') }

	try:
		_jData = json.dumps(formData)
		_jDataB64 = base64.b64encode(_jData.encode("ascii"))
		headers = {"Content-type": "multipart/form-data", "Accept": "application/json"}
		print("Uploading packages to MacPatch server ...")
		_response = requests.post(_url, files = _files, verify=False)

		print(_response.text)

		if(_response.ok):
			print(_response.json())
			res = _response.json()
			_resDict = res["result"]
			print(_resDict)
			if "token" in _resDict:
				API_TOKEN = _resDict['token']
				result = True

		return result

	except requests.exceptions.HTTPError as err:
		print ("Http Error:",err)
	except requests.exceptions.ConnectionError as errc:
		print ("Error Connecting:",errc)
	except requests.exceptions.Timeout as errt:
		print ("Timeout Error:",errt)
	except requests.exceptions.RequestException as err:
		print ("Ops: Something Else",err)

	return result

def uploadTestedPackagesToServer(dataFile):
	global API_TOKEN, PKG_TMP_DIR

	uploadData = None
	with open(dataFile) as f:
  		uploadData = json.load(f)

	API_TOKEN = uploadData['token']
	PKG_TMP_DIR = uploadData['pkgDir']
	uploadPackagesToServer(uploadData['pkgs'], uploadData['data'] )


def main():
	global PKG_DEST_DIR
	global API_USR_NAME, API_USR_PASS, AGENT_PACKAGE_PATH, NOTORIZE, PLUGINS_DIRECTORY
	global MP_SERVER, MP_PORT, REGISTRATION_KEY, MIGRATION_PLIST, UPLOAD_PKGS
	os.system('clear')
	print("")
	print("******* MacPatch Agent Uploader *******")
	print("")

	parser = argparse.ArgumentParser(description='Process some integers.')
	# Prompt for user and pass
	parser.add_argument('-u', dest='promptCreds', action='store_true', default=False, help='Prompt for API user and password')

	parser.add_argument('-p', dest='agentPKGZip', help='Path for agent package (e.g. MacPatch.pkg.zip) to be processed.')
	parser.add_argument('-i', dest='signIdentity', help='Signing identity')
	parser.add_argument('--plugins', dest='agentPlugins', help='Path for agent plugins folder.')

	parser.add_argument('-r', dest='agentRegkey', help='Agent Registration Key')

	parser.add_argument('--host', dest='apiServer', help='MacPatch Master/Primary Server')
	parser.add_argument('--port', dest='apiServerPort', help='MacPatch Master/Primary Server API Port')

	parser.add_argument('-m', dest='migrationPlist', help='MacPatch Server Migration plist file')

	parser.add_argument('-d', dest='noUpload', action='store_true', default=False, help='Do not upload completed package to server.')
	parser.add_argument('-n', dest='notorize', action='store_false', default=True, help='Do not notorize packages.')

	parser.add_argument('-c', dest='configFile', help='External Config File for agent upload')

	parser.add_argument('-j', dest='jUploadData', help='Upload Data file. Upload tested packages.')

	parser.add_argument('--destDir', dest='pkgDestDir', help='The base path to the processed pkg.')

	args = parser.parse_args()

	# First Process Config File, then allow other CLI args to override
	if args.configFile is not None:
		config = configparser.ConfigParser()
		config.read(args.configFile)
		for key in config['DEFAULT']:
			globals()[key.upper()]=config['DEFAULT'][key]

		#print(globals())

	if args.promptCreds:
		API_USR_NAME = input("API User Name: ")
		API_USR_PASS = getpass.getpass('Password:')

	if args.agentPKGZip is not None:
		AGENT_PACKAGE_PATH = args.agentPKGZip

	if args.agentPlugins is not None:
		PLUGINS_DIRECTORY = args.agentPlugins

	if args.agentRegkey is not None:
		REGISTRATION_KEY = args.agentRegkey

	if args.apiServer is not None:
		MP_SERVER = args.apiServer

	if args.apiServerPort is not None:
		MP_PORT = args.apiServerPort

	if args.migrationPlist is not None:
		MIGRATION_PLIST = args.migrationPlist

	if args.noUpload:
		UPLOAD_PKGS = False

	if args.notorize == False:
		NOTORIZE = False
	elif args.notorize == True and NOTORIZE == False:
		NOTORIZE = False

	if args.pkgDestDir is not None:
		PKG_DEST_DIR = args.pkgDestDir
		print("Set pkgDestDir:"+PKG_DEST_DIR)

	if args.jUploadData is not None:
		uploadTestedPackagesToServer(args.jUploadData)
	else:
		processAgentPackage()


if __name__ == "__main__":
	main()
