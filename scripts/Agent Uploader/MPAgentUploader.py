#!/usr/bin/env python3

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

# -----------------------------------------------------------------------
# Platform / Xcode check — must run on macOS with Xcode installed
# -----------------------------------------------------------------------
import sys
import platform

def _check_platform():
    if platform.system() != "Darwin":
        sys.exit("Error: This script must be run on macOS.")

    result = subprocess.run(
        ["xcode-select", "-p"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    if result.returncode != 0:
        sys.exit("Error: Xcode Command Line Tools are not installed. Run: xcode-select --install")

    xcode_path = result.stdout.decode().strip()
    if not os.path.isdir(xcode_path):
        sys.exit(f"Error: Xcode tools path not found: {xcode_path}")

_check_platform()
# -----------------------------------------------------------------------

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
VERIFY_SSL = True
MP_SERVER = None
MP_PORT = 3600
URI_PREFIX = "/api/v1"
UPLOAD_PKGS = True

# Sign PKG
SIGN_PKG = True
SIGN_IDENTITY = None

# Notorize PKG
NOTORIZE = True
# Notarization tool: "altool" (legacy, Xcode < 15) or "notarytool" (Xcode 15+)
NOTARIZE_TOOL = "notarytool"

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


def _build_url(path, prefix=None):
	"""
	Build a full API URL from a path fragment.

	Uses the global USE_SSL, MP_SERVER, MP_PORT, and URI_PREFIX values.
	Pass a custom prefix to override URI_PREFIX for a specific call.

	:param path: URL path fragment, e.g. '/auth/token'
	:param prefix: optional prefix override (default: URI_PREFIX)
	:returns: fully-qualified URL string
	"""
	scheme = "https" if USE_SSL else "http"
	base_prefix = prefix if prefix is not None else URI_PREFIX
	return "{}://{}:{}{}{}".format(scheme, MP_SERVER, MP_PORT, base_prefix, path)

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


class NotarizeTool:

	def __init__(self, user, passwd, team_id):
		"""
		Notarize packages using xcrun notarytool (Xcode 15+).

		:param user: Apple ID / developer account email
		:param passwd: app-specific password for the Apple ID
		:param team_id: 10-digit Apple Developer Team ID
		"""
		self.user = user
		self.passwd = passwd
		self.team_id = team_id

	def notarizePackage(self, package, bundleID):
		"""
		Submit a package for notarization and wait for the result.

		notarytool handles polling internally via --wait, so no manual
		polling loop is needed. On failure the submission log is fetched
		and printed to aid diagnosis.

		:param package: path to the .pkg file to notarize
		:param bundleID: bundle identifier string
		"""
		print("Begin notarization of {} (notarytool)".format(package))
		cli_args = [
			'/usr/bin/xcrun', 'notarytool', 'submit', package,
			'--apple-id', self.user,
			'--password', self.passwd,
			'--team-id', self.team_id,
			'--wait'
		]
		res = subprocess.run(cli_args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
		print(res.stdout)

		if res.returncode != 0:
			print("Error: notarytool submission failed for {}".format(package))
			print(res.stderr)
			self._fetchLog(package)
			return False

		if "status: Accepted" not in res.stdout:
			print("Error: notarization was not accepted for {}".format(package))
			self._fetchLog(package)
			return False

		print("Notarization accepted for {}".format(package))
		return True

	def _fetchLog(self, package):
		"""Fetch and print the notarization log for a failed submission."""
		# Extract the submission ID from a prior notarytool history call
		log_args = [
			'/usr/bin/xcrun', 'notarytool', 'history',
			'--apple-id', self.user,
			'--password', self.passwd,
			'--team-id', self.team_id,
			'--output-format', 'json'
		]
		res = subprocess.run(log_args, stdout=subprocess.PIPE, text=True)
		try:
			history = json.loads(res.stdout)
			submission_id = history['history'][0]['id']
			fetch_args = [
				'/usr/bin/xcrun', 'notarytool', 'log', submission_id,
				'--apple-id', self.user,
				'--password', self.passwd,
				'--team-id', self.team_id,
			]
			log_res = subprocess.run(fetch_args, stdout=subprocess.PIPE, text=True)
			print("Notarization log:\n" + log_res.stdout)
		except (json.JSONDecodeError, KeyError, IndexError):
			print("Could not retrieve notarization log.")

def makeAuthRequest(authUser, authPass):
	"""Make Auth Request for token."""
	print("Getting API Token ...")
	global API_TOKEN
	API_TOKEN = "NA" # Reset value

	result = False
	_url = _build_url("/auth/token")
	_params = {'authUser': authUser, 'authPass': authPass}

	try:
		_response = requests.post(_url, json=_params, verify=VERIFY_SSL)
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

def isTokenValid(token):
	"""
	Query Web API to see if auth token is valid.

	:param token: auth token
	:returns: Bool
	"""
	result = False
	_url = _build_url("/token/valid/{}".format(token))
	
	try:
		_response = requests.get(_url, verify=VERIFY_SSL)
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

def getAgentConfigurationData(token):
	"""
	Get Agent Configuration Data from Web API.

	:param token: auth token
	:returns: Dictionary of result
	"""
	result = None
	_url = _build_url("/agent/config/{}".format(token), prefix="/api/v2")
	try:
		_response = requests.get(_url, verify=VERIFY_SSL)
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

def getPackagesFromArchiveDir(path):
	"""
	Get Array of PKG's from a path.

	:param path: Directory Path
	:returns: Array of Strings
	"""
	result = []
	x = fnmatch.filter(os.listdir(path), '*.pkg')
	for r in x:
		result.append(os.path.join(path,r))

	if len(result) == 0:
		return None
	else:
		return result

def extractAgentPKG(package, destDir=None):
	"""
	Extract Zipped Package and Expand the Package.

	:param package: Zip Package path
	:returns: Boolean if succeeds
	"""
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

def writeServerPubKeyToPackage(packages, pubKey, keyHash):
	"""
	Write MP Server Env Public Key to packages.

	:param packages: Array of packages
	:param pubKey: public key string
	:param keyHash: md5 hash of the key
	:returns: Boolean if succeeds
	"""

	for p in packages:
		if "Base.pkg" in p or "Client.pkg" in p:
			scripts_dir = os.path.join(p,"Scripts")
			if not os.path.exists(scripts_dir):
				os.makedirs(scripts_dir)

			_keyFile = os.path.join(p,"Scripts/ServerPub.pem")
			with open(_keyFile, "w") as f:
				f.write(pubKey)

			_keyFileHash = hashlib.md5(open(_keyFile,'rb').read()).hexdigest()
			# Check hash
			if _keyFileHash.lower() == keyHash.lower():
				return True
			else:
				print("writeServerPubKeyToPackage failed hash check.")

	return False

def writePlistToPackage(packages, plistData):
	"""
	Write plist data to Package.

	:param packages: Array of packages
	:param plistData: plist data
	:returns: Boolean if succeeds
	"""
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

def getPluginsFromDirectory(path):
	"""
	Get Array of plugins from a path.

	:param path: Directory Path
	:returns: Array of Strings
	"""
	x = []
	x = fnmatch.filter(os.listdir(path), '*.bundle')
	return x

def writePluginsToPackage(packages, plugins_dir):
	"""
	Write plugins to Package.

	:param packages: Array of packages
	:param plugins_dir: directory containing plugins
	:returns: Boolean if succeeds
	"""

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
						if not os.path.exists(dst_plugin_path):
							print("Copy {} to {}".format(plugin,plugin_dir))
							shutil.copy2(src_plugin_path, dst_plugin_path)

	return True

def writeVersionInfoToPackage(package, version_file):
	"""
	Write version info plist to package. Also populates dictionaries for
	post to web API during upload.

	:param package: package path
	:param version_file: version file
	:returns: Boolean if succeeds
	"""
	global AGENT_DICTIONARY, UPDATER_DICTIONARY

	pkg_type = None
	base_dict = {}
	ver_dict = {}
	with open(version_file, 'rb') as fp:
		info_dict = plistlib.load(fp)

	if "Base.pkg" in package:
		if "Agent" in info_dict:
			ver_dict = info_dict['Agent']
			pkg_type = 'app'
	elif "Updater.pkg" in package:
		if "Updater" in info_dict:
			ver_dict = info_dict['Updater']
			pkg_type = 'update'
	else:
		print("Error: unrecognized package type for: {}".format(package))

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
		base_dict["type"] = pkg_type
		base_dict["osver"] = ver_dict["osver"]
		base_dict["agent_ver"] = ver_dict["agent_version"]
		base_dict["ver"] = ver_dict["version"]

		if pkg_type == "app":
			AGENT_DICTIONARY = base_dict
		else:
			UPDATER_DICTIONARY = base_dict

	return True

def writeRegKeyToPackage(packages, regKey):
	"""
	Write registration key to file in package.

	:param packages: package array
	:param regKey: registration key string
	:returns: Boolean if succeeds
	"""
	if len(packages) <= 0:
		return False

	if regKey is None:
		return False

	for p in packages:
		if "Base.pkg" in p or "Client.pkg" in p:
			scriptsDir = os.path.join(p, "Scripts")
			regFile = os.path.join(p, "Scripts", ".mpreg.key")
			if os.path.exists(scriptsDir):
				with open(regFile, "w") as f:
					f.write(regKey)

				return True

	return False

def flattenPackage(pkgPath, flattenPkgPath):
	"""
	Flatten Package.

	:param pkgPath: path of package to flatten
	:param flattenPkgPath: the resulting flattened package
	:returns: Bool
	"""
	cli_args = ["/usr/sbin/pkgutil", "--flatten", pkgPath, flattenPkgPath]
	res = subprocess.run(cli_args)

	if res.returncode == 0:
		return True
	else:
		print("The exit code was: %d" % res.returncode)
		return False

def signPackage(pkgPath, signingIdentity):
	"""
	Code Sign Package.

	:param pkgPath: path of package to sign
	:param signingIdentity: signing identity string
	:returns: Bool
	"""
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

def flattenPackages(packages, working_dir):
	"""
	Flatten Packages for distribution. If signing is enabled,
	packages will be signed as well.

	:param packages: array of package paths
	:param working_dir: working directory for output
	:returns: Array of flattened packages
	"""
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

def compressPackage(pkgPath):
	"""
	Compress Package.

	:param pkgPath: path of package to compress
	:returns: Bool
	"""
	print("Compressing {}".format(pkgPath))
	compressed_pkg = "{}.zip".format(pkgPath)
	cli_args = ["/usr/bin/ditto", "-c", "-k", pkgPath, compressed_pkg]
	res = subprocess.run(cli_args)
	if res.returncode == 0:
		return True
	else:
		return False

def changeBackgroundImageToDoneImage(path):
	"""
	Replace the installer background image with the 'done' variant.

	:param path: base dir for Background images
	:returns: Boolean if succeeds
	"""
	image = os.path.join(path, "Resources/Background.png")
	image_done = os.path.join(path, "Resources/Background_done.png")
	if os.path.exists(image) and os.path.exists(image_done):
		os.remove(image)
		shutil.copy2(image_done, image)

	return True

def _authenticate():
	"""
	Prompt for credentials if needed and obtain an API auth token.

	:returns: True on success, False on failure
	"""
	global API_USR_NAME, API_USR_PASS

	if API_USR_NAME is None:
		API_USR_NAME = input("API User Name: ")
	if API_USR_PASS is None:
		API_USR_PASS = getpass.getpass('Password:')

	if not makeAuthRequest(API_USR_NAME, API_USR_PASS):
		print("Error: failed to get auth token. Please verify user and password.")
		return False

	if API_TOKEN == "NA":
		print("Error: auth token is NA.")
		return False

	return True


def _downloadAgentConfig():
	"""
	Download agent configuration from the server and parse it.

	:returns: tuple of (agent_config dict, pubKey str, pubKeyHash str),
	          or (None, None, None) on failure
	"""
	print("Download agent configuration")
	agent_config_res = getAgentConfigurationData(API_TOKEN)
	if not agent_config_res:
		print("Error getting agent configuration, is None")
		return None, None, None

	if "plist" not in agent_config_res:
		print("Error: agent configuration is missing plist key.")
		return None, None, None

	if "pubKey" not in agent_config_res:
		print("Error: agent configuration is missing pubKey.")
		return None, None, None

	if "pubKeyHash" not in agent_config_res:
		print("Error: agent configuration is missing pubKeyHash.")
		return None, None, None

	# Write plist XML to a temp file and load it back as a dict
	_tmp_datafile = '/tmp/agentConfig.plist'
	if os.path.exists(_tmp_datafile):
		os.remove(_tmp_datafile)
	with open(_tmp_datafile, "w") as f:
		f.write(agent_config_res['plist'])
	with open(_tmp_datafile, 'rb') as fp:
		_dict = plistlib.load(fp)

	return _dict['default'], agent_config_res['pubKey'], agent_config_res['pubKeyHash']


def _preparePackages(agent_config, pubKey, pubKeyHash):
	"""
	Extract, configure, flatten, notarize, and compress the agent packages.

	:param agent_config: agent configuration dict
	:param pubKey: server public key string
	:param pubKeyHash: md5 hash of the public key
	:returns: list of finished .zip package paths, or None on failure
	"""
	global PKG_TMP_DIR

	# Extract and expand
	print("Unzip and extract package")
	if not os.path.exists(AGENT_PACKAGE_PATH):
		print("Error: agent package path is not defined or not found.")
		return None

	print("PKG_DEST_DIR: " + PKG_DEST_DIR)
	if not extractAgentPKG(AGENT_PACKAGE_PATH, PKG_DEST_DIR):
		return None

	if PKG_TMP_DIR is None:
		print("Error: package tmp dir is not defined.")
		return None

	base_dir = os.path.join(PKG_TMP_DIR, "MacPatch")
	print("Working dir (base_dir) is {}".format(base_dir))

	packages = getPackagesFromArchiveDir(base_dir)
	if packages is None:
		print("Error: no packages to process.")
		return None

	# Write config data into packages
	print("Write config data to packages.")
	if not writeServerPubKeyToPackage(packages, pubKey, pubKeyHash):
		print("Error writing server public key data")
		return None

	if not writePlistToPackage(packages, agent_config):
		print("Error writing agent config data")
		return None

	if PLUGINS_DIRECTORY is not None:
		if not writePluginsToPackage(packages, PLUGINS_DIRECTORY):
			print("Error copying plugins to packages.")

	ver_info_file = os.path.join(base_dir, "Resources/mpInfo.plist")
	if os.path.exists(ver_info_file):
		for p in packages:
			if not writeVersionInfoToPackage(p, ver_info_file):
				print("Error writing version info to packages.")

	if REGISTRATION_KEY is not None:
		if not writeRegKeyToPackage(packages, REGISTRATION_KEY):
			print("Error writing registration key to packages.")

	if not changeBackgroundImageToDoneImage(base_dir):
		print("Error changing pkg background image.")

	# Flatten (and optionally sign)
	packages.append(base_dir)
	flatten_packages = flattenPackages(packages, PKG_TMP_DIR)

	# Notarize and compress
	if NOTORIZE:
		if NOTARIZE_TOOL == "notarytool":
			n = NotarizeTool(DEV_ACCOUNT, APPLE_ID_APP_PASSWORD, DEV_TEAM)
		else:
			n = Notorize(DEV_ACCOUNT, APPLE_ID_APP_PASSWORD)
	else:
		n = None

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
				n.notarizePackage(f, "gov.llnl.mp.base.pkg")
			elif "Updater.pkg" in f:
				n.notarizePackage(f, "gov.llnl.mp.updater.pkg")
			elif "MacPatch.pkg" in f:
				n.notarizePackage(f, "gov.llnl.mp.pkg")

		if not compressPackage(f):
			print("Error compressing {}".format(f))
		else:
			_finished_packages.append(f + '.zip')
			if removePKG:
				os.remove(removePKGPath)

	return _finished_packages


def _uploadPackages(finished_packages):
	"""
	Save upload manifest to disk and optionally post packages to the server.

	:param finished_packages: list of .zip package paths to upload
	"""
	formData = {"app": AGENT_DICTIONARY, "update": UPDATER_DICTIONARY, "plugins": [], "profiles": []}

	uploadData = {'pkgs': finished_packages, 'data': formData, 'token': API_TOKEN, 'pkgDir': PKG_TMP_DIR}
	uploadDataFile = os.path.join(PKG_TMP_DIR, 'uploadData.json')
	with open(uploadDataFile, 'w') as outfile:
		json.dump(uploadData, outfile)

	if UPLOAD_PKGS:
		uploadPackagesToServer(finished_packages, formData)
	else:
		print("Upload packages is disabled.")


def processAgentPackage():
	"""
	Orchestrate the full agent package build and upload pipeline:
	authenticate, download config, prepare packages, and upload.
	"""
	print("Begin Processing Agent Packages")

	if not _authenticate():
		return

	agent_config, pubKey, pubKeyHash = _downloadAgentConfig()
	if agent_config is None:
		return

	finished_packages = _preparePackages(agent_config, pubKey, pubKeyHash)
	if finished_packages is None:
		return

	_uploadPackages(finished_packages)

	subprocess.run(['/usr/bin/open', PKG_TMP_DIR])


def uploadPackagesToServer(packages, formData):
	global API_USR_NAME, API_USR_PASS, API_TOKEN

	result = False
	aid = str(uuid.uuid4())
	_url = _build_url("/agent/upload/{}/{}".format(aid, API_TOKEN), prefix="/api/v3")

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
		print("Uploading packages to MacPatch server ...")
		_response = requests.post(_url, files = _files, verify=VERIFY_SSL)

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
	global MP_SERVER, MP_PORT, REGISTRATION_KEY, MIGRATION_PLIST, UPLOAD_PKGS, VERIFY_SSL, NOTARIZE_TOOL
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

	parser.add_argument('--notarize-tool', dest='notarizeTool', choices=['altool', 'notarytool'], default=None,
					help='Notarization tool to use: altool (legacy, Xcode <15) or notarytool (Xcode 15+, default).')

	parser.add_argument('--no-verify-ssl', dest='noVerifySSL', action='store_true', default=False, help='Disable SSL certificate verification (use for self-signed certs).')

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

	if args.noVerifySSL:
		VERIFY_SSL = False

	if args.notarizeTool is not None:
		NOTARIZE_TOOL = args.notarizeTool

	if not args.notorize:
		NOTORIZE = False
	elif args.notorize and not NOTORIZE:
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