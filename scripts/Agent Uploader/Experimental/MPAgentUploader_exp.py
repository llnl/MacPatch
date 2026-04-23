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
import dataclasses
from dataclasses import dataclass, field
from typing import Optional
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

version     = "1.0"
identifier  = "gov.llnl.mp.pkg"
productname = "MacPatch"


# -----------------------------------------------------------------------
# Configuration dataclass
# -----------------------------------------------------------------------

@dataclass
class Config:
	"""
	All runtime configuration for MPAgentUploader.

	Populated in order: defaults -> config file -> CLI args.
	Only fields defined here can be set from a config file, which
	prevents arbitrary globals from being injected.
	"""

	# Server
	mp_server:  Optional[str] = None
	mp_port:    int           = 3600
	use_ssl:    bool          = True
	verify_ssl: bool          = True
	uri_prefix: str           = "/api/v1"

	# Auth (supplied interactively or via CLI — not stored in config files)
	api_usr_name: Optional[str] = None
	api_usr_pass: Optional[str] = None
	api_token:    str           = "NA"

	# Package paths
	agent_package_path: Optional[str] = None
	pkg_dest_dir:       Optional[str] = None
	pkg_tmp_dir:        Optional[str] = None

	# Package options
	upload_pkgs:       bool           = True
	plugins_directory: Optional[str] = None
	registration_key:  Optional[str] = None
	migration_plist:   Optional[str] = None

	# Signing
	sign_pkg:      bool           = True
	sign_identity: Optional[str] = None

	# Notarization
	notorize:              bool           = True
	notarize_tool:         str            = "notarytool"  # "altool" or "notarytool"
	dev_account:           Optional[str] = None
	dev_team:              Optional[str] = None
	dev_keychain_label:    Optional[str] = None
	apple_id_app_password: Optional[str] = None

	# Runtime state — populated during processing, never from a config file
	agent_dictionary:   dict = field(default_factory=dict)
	updater_dictionary: dict = field(default_factory=dict)

	# Fields that must not be set from a config file
	_RUNTIME_ONLY = frozenset({
		'api_usr_name', 'api_usr_pass', 'api_token',
		'pkg_tmp_dir', 'agent_dictionary', 'updater_dictionary'
	})

	@classmethod
	def from_file(cls, path: str) -> "Config":
		"""
		Load configuration from an INI-format file.

		Only known field names are accepted; unrecognised keys produce a
		warning and are ignored. Runtime-only fields (credentials, state)
		cannot be set via file.

		:param path: path to the INI config file
		:returns: Config instance
		"""
		config = configparser.ConfigParser()
		config.read(path)

		known_fields = {f.name: f for f in dataclasses.fields(cls)}
		kwargs = {}

		for key, value in config['DEFAULT'].items():
			if key not in known_fields:
				print("Warning: ignoring unrecognized config key '{}'".format(key))
				continue
			if key in cls._RUNTIME_ONLY:
				print("Warning: config key '{}' cannot be set from a file — ignoring.".format(key))
				continue

			f = known_fields[key]
			type_hint = str(f.type)
			if 'bool' in type_hint:
				kwargs[key] = value.strip().lower() in ('true', '1', 'yes')
			elif 'int' in type_hint:
				try:
					kwargs[key] = int(value)
				except ValueError:
					print("Warning: config key '{}' expected an integer, got '{}' — ignoring.".format(key, value))
			else:
				stripped = value.strip()
				kwargs[key] = stripped if stripped else None

		return cls(**kwargs)

	def apply_args(self, args: argparse.Namespace) -> None:
		"""
		Overlay parsed CLI arguments on top of the current config.
		Only non-None / explicitly set values from args are applied,
		so config-file values are not silently clobbered.

		:param args: parsed argparse.Namespace
		"""
		if args.promptCreds:
			self.api_usr_name = input("API User Name: ")
			self.api_usr_pass = getpass.getpass('Password:')

		if args.agentPKGZip is not None:
			self.agent_package_path = args.agentPKGZip
		if args.agentPlugins is not None:
			self.plugins_directory = args.agentPlugins
		if args.agentRegkey is not None:
			self.registration_key = args.agentRegkey
		if args.apiServer is not None:
			self.mp_server = args.apiServer
		if args.apiServerPort is not None:
			self.mp_port = int(args.apiServerPort)
		if args.migrationPlist is not None:
			self.migration_plist = args.migrationPlist
		if args.signIdentity is not None:
			self.sign_identity = args.signIdentity
		if args.pkgDestDir is not None:
			self.pkg_dest_dir = args.pkgDestDir
			print("Set pkgDestDir: " + self.pkg_dest_dir)
		if args.noUpload:
			self.upload_pkgs = False
		if args.noVerifySSL:
			self.verify_ssl = False
		if args.notarizeTool is not None:
			self.notarize_tool = args.notarizeTool
		if not args.notorize:
			self.notorize = False


# -----------------------------------------------------------------------
# Notarization classes
# -----------------------------------------------------------------------

class Notorize:
	"""Legacy notarization via xcrun altool (Xcode < 15)."""

	def __init__(self, user, passwd):
		self.user   = user
		self.passwd = passwd

	def notarizePackage(self, package, bundleID):
		"""
		Submit a package for notarization and poll until complete.

		:param package: path to the .pkg file to notarize
		:param bundleID: bundle identifier string
		"""
		print("Begin notorization of {}".format(package))
		_requestUUID = None
		cli_args = [
			'/usr/bin/xcrun', 'altool', '--notarize-app',
			'--primary-bundle-id', bundleID,
			'--username', self.user,
			'--password', self.passwd,
			'--file', package
		]
		res = subprocess.run(cli_args, stdout=subprocess.PIPE, text=True)
		for line in res.stdout.split('\n'):
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
			print("Status: " + rs)
			if "Error:" in rs:
				if tryAgainOnErrorResponse:
					print("Error on response, will wait and try one more time.")
					tryAgainOnErrorResponse = False
			else:
				request_status = rs

		if request_status != "success":
			print("Error could not notarize {}".format(package))
			print("{}".format(' '.join([str(elem) for elem in cli_args])))

	def requestStatus(self, requestUUID):
		"""
		Poll altool for the current notarization status.

		:param requestUUID: UUID returned by the initial submission
		:returns: status string
		"""
		result   = "NA"
		cli_args = [
			"/usr/bin/xcrun", "altool", "--notarization-info", requestUUID,
			'--username', self.user,
			'--password', self.passwd
		]
		res = subprocess.run(cli_args, stdout=subprocess.PIPE, text=True)
		for line in res.stdout.split('\n'):
			if "Status:" in line:
				result = line.split(':')[1].strip()
				break
		return result


class NotarizeTool:
	"""Modern notarization via xcrun notarytool (Xcode 15+)."""

	def __init__(self, user, passwd, team_id):
		"""
		:param user: Apple ID / developer account email
		:param passwd: app-specific password for the Apple ID
		:param team_id: 10-digit Apple Developer Team ID
		"""
		self.user    = user
		self.passwd  = passwd
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
			self._fetchLog()
			return False

		if "status: Accepted" not in res.stdout:
			print("Error: notarization was not accepted for {}".format(package))
			self._fetchLog()
			return False

		print("Notarization accepted for {}".format(package))
		return True

	def _fetchLog(self):
		"""Fetch and print the notarization log for the most recent submission."""
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


# -----------------------------------------------------------------------
# API helpers
# -----------------------------------------------------------------------

def _build_url(cfg: Config, path: str, prefix: Optional[str] = None) -> str:
	"""
	Build a full API URL from a path fragment.

	:param cfg: Config instance
	:param path: URL path fragment, e.g. '/auth/token'
	:param prefix: optional prefix override (default: cfg.uri_prefix)
	:returns: fully-qualified URL string
	"""
	scheme      = "https" if cfg.use_ssl else "http"
	base_prefix = prefix if prefix is not None else cfg.uri_prefix
	return "{}://{}:{}{}{}".format(scheme, cfg.mp_server, cfg.mp_port, base_prefix, path)


def makeAuthRequest(cfg: Config) -> bool:
	"""
	Request an API auth token and store it in cfg.api_token.

	:param cfg: Config instance
	:returns: True on success, False on failure
	"""
	print("Getting API Token ...")
	cfg.api_token = "NA"
	_url    = _build_url(cfg, "/auth/token")
	_params = {'authUser': cfg.api_usr_name, 'authPass': cfg.api_usr_pass}

	try:
		_response = requests.post(_url, json=_params, verify=cfg.verify_ssl)
		if _response.ok:
			res     = _response.json()
			_resDict = res["result"]
			if "token" in _resDict:
				cfg.api_token = _resDict['token']
				return True
		return False

	except requests.exceptions.HTTPError as err:
		print("Http Error:", err)
	except requests.exceptions.ConnectionError as errc:
		print("Error Connecting:", errc)
	except requests.exceptions.Timeout as errt:
		print("Timeout Error:", errt)
	except requests.exceptions.RequestException as err:
		print("Request Error:", err)

	return False


def isTokenValid(cfg: Config, token: str) -> bool:
	"""
	Query Web API to see if an auth token is valid.

	:param cfg: Config instance
	:param token: auth token
	:returns: Bool
	"""
	_url = _build_url(cfg, "/token/valid/{}".format(token))

	try:
		_response = requests.get(_url, verify=cfg.verify_ssl)
		_response.raise_for_status()
		if _response.ok:
			return bool(_response.json()["result"])

	except requests.exceptions.HTTPError as err:
		print("Http Error:", err)
	except requests.exceptions.ConnectionError as errc:
		print("Error Connecting:", errc)
	except requests.exceptions.Timeout as errt:
		print("Timeout Error:", errt)
	except requests.exceptions.RequestException as err:
		print("Request Error:", err)

	return False


def getAgentConfigurationData(cfg: Config) -> Optional[dict]:
	"""
	Get Agent Configuration Data from Web API.

	:param cfg: Config instance
	:returns: Dictionary of result, or None on failure
	"""
	_url = _build_url(cfg, "/agent/config/{}".format(cfg.api_token), prefix="/api/v2")

	try:
		_response = requests.get(_url, verify=cfg.verify_ssl)
		_response.raise_for_status()
		if _response.ok:
			return _response.json()['result']

	except requests.exceptions.HTTPError as err:
		print("Http Error:", err)
	except requests.exceptions.ConnectionError as errc:
		print("Error Connecting:", errc)
	except requests.exceptions.Timeout as errt:
		print("Timeout Error:", errt)
	except requests.exceptions.RequestException as err:
		print("Request Error:", err)

	return None


# -----------------------------------------------------------------------
# Package helpers
# -----------------------------------------------------------------------

def getPackagesFromArchiveDir(path: str) -> Optional[list]:
	"""
	Get Array of PKG's from a path.

	:param path: Directory Path
	:returns: Array of Strings, or None if no packages found
	"""
	result = [os.path.join(path, r) for r in fnmatch.filter(os.listdir(path), '*.pkg')]
	return result if result else None


def extractAgentPKG(cfg: Config, package: str) -> bool:
	"""
	Extract Zipped Package and Expand the Package.

	Sets cfg.pkg_tmp_dir to the created temp directory.

	:param cfg: Config instance
	:param package: Zip Package path
	:returns: Boolean if succeeds
	"""
	_dts   = datetime.now().strftime("%Y%m%d%H%M%S")
	tmpDir = (
		os.path.join(cfg.pkg_dest_dir, "Completed", "MacPatch_{}".format(_dts))
		if cfg.pkg_dest_dir else
		os.path.join('/private/var/tmp', "MacPatch_{}".format(_dts))
	)
	cfg.pkg_tmp_dir = tmpDir

	res = subprocess.run(["/usr/bin/ditto", "-x", "-k", package, tmpDir])
	if res.returncode != 0:
		print("Error extracting package. The exit code was: %d" % res.returncode)
		return False

	_pkgPath       = pathlib.PurePath(package)
	pkgName        = os.path.splitext(os.path.join(tmpDir, _pkgPath.name))[0]
	expandedPkgDir = os.path.join(tmpDir, "MacPatch")

	res = subprocess.run(["/usr/sbin/pkgutil", "--expand", pkgName, expandedPkgDir])
	if res.returncode != 0:
		print("Error expanding package. The exit code was: %d" % res.returncode)
		return False

	if os.path.isfile(pkgName):
		os.remove(pkgName)
	else:
		print("Error: %s file not found" % pkgName)

	return True


def writeServerPubKeyToPackage(packages: list, pubKey: str, keyHash: str) -> bool:
	"""
	Write MP Server Env Public Key to packages.

	:param packages: Array of packages
	:param pubKey: public key string
	:param keyHash: md5 hash of the key
	:returns: Boolean if succeeds
	"""
	for p in packages:
		if "Base.pkg" in p or "Client.pkg" in p:
			scripts_dir = os.path.join(p, "Scripts")
			if not os.path.exists(scripts_dir):
				os.makedirs(scripts_dir)

			_keyFile = os.path.join(p, "Scripts/ServerPub.pem")
			with open(_keyFile, "w") as f:
				f.write(pubKey)

			_keyFileHash = hashlib.md5(open(_keyFile, 'rb').read()).hexdigest()
			if _keyFileHash.lower() == keyHash.lower():
				return True
			else:
				print("writeServerPubKeyToPackage failed hash check.")

	return False


def writePlistToPackage(cfg: Config, packages: list, plistData: dict) -> bool:
	"""
	Write plist data to Package.

	:param cfg: Config instance
	:param packages: Array of packages
	:param plistData: plist data
	:returns: Boolean if succeeds
	"""
	for p in packages:
		if "Base.pkg" in p or "Client.pkg" in p:
			scripts_dir = os.path.join(p, "Scripts")
			if not os.path.exists(scripts_dir):
				os.makedirs(scripts_dir)
			with open(os.path.join(p, "Scripts/gov.llnl.mpagent.plist"), 'wb') as fp:
				plistlib.dump(plistData, fp)

		elif "Updater.pkg" in p:
			if cfg.migration_plist is not None:
				scripts_dir = os.path.join(p, "Scripts")
				if not os.path.exists(scripts_dir):
					os.makedirs(scripts_dir)
				shutil.copy2(cfg.migration_plist, os.path.join(p, "Scripts/migration.plist"))

	return True


def getPluginsFromDirectory(path: str) -> list:
	"""
	Get Array of plugins from a path.

	:param path: Directory Path
	:returns: Array of Strings
	"""
	return fnmatch.filter(os.listdir(path), '*.bundle')


def writePluginsToPackage(cfg: Config, packages: list, plugins_dir: str) -> bool:
	"""
	Write plugins to Package.

	:param cfg: Config instance
	:param packages: Array of packages
	:param plugins_dir: directory containing plugins
	:returns: Boolean if succeeds
	"""
	for p in packages:
		if "Base.pkg" in p or "Client.pkg" in p:
			plugin_dir = os.path.join(p, "Scripts/Plugins")
			if not os.path.exists(plugin_dir):
				os.makedirs(plugin_dir)

			for plugin in getPluginsFromDirectory(plugins_dir):
				src = os.path.join(cfg.plugins_directory, plugin)
				dst = os.path.join(plugin_dir, plugin)
				if os.path.isdir(src):
					print("Copy {} to {}".format(plugin, plugin_dir))
					shutil.copytree(src, dst)
				elif not os.path.exists(dst):
					print("Copy {} to {}".format(plugin, plugin_dir))
					shutil.copy2(src, dst)

	return True


def writeVersionInfoToPackage(cfg: Config, package: str, version_file: str) -> bool:
	"""
	Write version info plist to package. Also populates cfg dictionaries for
	post to web API during upload.

	:param cfg: Config instance
	:param package: package path
	:param version_file: version file
	:returns: Boolean if succeeds
	"""
	with open(version_file, 'rb') as fp:
		info_dict = plistlib.load(fp)

	pkg_type = None
	ver_dict = {}

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

	if "agent_version" in ver_dict:
		vers = ver_dict['agent_version'].split(".")
		base_dict = {
			"framework": "0",
			"build":     ver_dict["build"],
			"major":     vers[0],
			"minor":     vers[1],
			"bug":       vers[2],
			"version":   ver_dict["version"],
		}

		plistFile = os.path.join(package, "Scripts/.mpVersion.plist")
		print("Write version info to {}".format(plistFile))
		with open(plistFile, 'wb') as fp:
			plistlib.dump(base_dict, fp)

		base_dict.update({
			"pkg_name":  os.path.basename(os.path.normpath(package)),
			"type":      pkg_type,
			"osver":     ver_dict["osver"],
			"agent_ver": ver_dict["agent_version"],
			"ver":       ver_dict["version"],
		})

		if pkg_type == "app":
			cfg.agent_dictionary = base_dict
		else:
			cfg.updater_dictionary = base_dict

	return True


def writeRegKeyToPackage(packages: list, regKey: str) -> bool:
	"""
	Write registration key to file in package.

	:param packages: package array
	:param regKey: registration key string
	:returns: Boolean if succeeds
	"""
	if not packages or regKey is None:
		return False

	for p in packages:
		if "Base.pkg" in p or "Client.pkg" in p:
			scriptsDir = os.path.join(p, "Scripts")
			if os.path.exists(scriptsDir):
				with open(os.path.join(p, "Scripts", ".mpreg.key"), "w") as f:
					f.write(regKey)
				return True

	return False


def flattenPackage(pkgPath: str, flattenPkgPath: str) -> bool:
	"""
	Flatten Package.

	:param pkgPath: path of package to flatten
	:param flattenPkgPath: the resulting flattened package
	:returns: Bool
	"""
	res = subprocess.run(["/usr/sbin/pkgutil", "--flatten", pkgPath, flattenPkgPath])
	if res.returncode == 0:
		return True
	print("The exit code was: %d" % res.returncode)
	return False


def signPackage(pkgPath: str, signingIdentity: str) -> bool:
	"""
	Code Sign Package.

	:param pkgPath: path of package to sign
	:param signingIdentity: signing identity string
	:returns: Bool
	"""
	print("Signing {}".format(pkgPath))
	signed_pkg_name = pkgPath.replace("toSign_", "")
	res = subprocess.run(
		["/usr/bin/productsign", "--sign", signingIdentity, pkgPath, signed_pkg_name],
		stdout=subprocess.DEVNULL
	)
	if res.returncode == 0:
		return True
	print("{} was not signed. Exit code: %d".format(signed_pkg_name) % res.returncode)
	return False


def flattenPackages(cfg: Config, packages: list, working_dir: str) -> list:
	"""
	Flatten Packages for distribution. If signing is enabled,
	packages will be signed as well.

	:param cfg: Config instance
	:param packages: array of package paths
	:param working_dir: working directory for output
	:returns: Array of flattened packages
	"""
	_flat_packages = []

	for p in packages:
		pkg_name = (
			"toSign_{}".format(pathlib.PurePath(p).name)
			if cfg.sign_pkg else
			str(pathlib.PurePath(p).name)
		)
		flatten_pkg_path = os.path.join(
			working_dir,
			pkg_name if pathlib.Path(p).suffix == ".pkg" else pkg_name + ".pkg"
		)

		if not flattenPackage(p, flatten_pkg_path):
			print("Error flattening package {}".format(p))

		if cfg.sign_pkg:
			signPackage(flatten_pkg_path, cfg.sign_identity)

		_flat_packages.append(flatten_pkg_path)

	return _flat_packages


def compressPackage(pkgPath: str) -> bool:
	"""
	Compress Package.

	:param pkgPath: path of package to compress
	:returns: Bool
	"""
	print("Compressing {}".format(pkgPath))
	res = subprocess.run(["/usr/bin/ditto", "-c", "-k", pkgPath, "{}.zip".format(pkgPath)])
	return res.returncode == 0


def changeBackgroundImageToDoneImage(path: str) -> bool:
	"""
	Replace the installer background image with the 'done' variant.

	:param path: base dir for Background images
	:returns: Boolean if succeeds
	"""
	image      = os.path.join(path, "Resources/Background.png")
	image_done = os.path.join(path, "Resources/Background_done.png")
	if os.path.exists(image) and os.path.exists(image_done):
		os.remove(image)
		shutil.copy2(image_done, image)
	return True


# -----------------------------------------------------------------------
# Pipeline stages
# -----------------------------------------------------------------------

def _authenticate(cfg: Config) -> bool:
	"""
	Prompt for credentials if needed and obtain an API auth token.

	:param cfg: Config instance
	:returns: True on success, False on failure
	"""
	if cfg.api_usr_name is None:
		cfg.api_usr_name = input("API User Name: ")
	if cfg.api_usr_pass is None:
		cfg.api_usr_pass = getpass.getpass('Password:')

	if not makeAuthRequest(cfg):
		print("Error: failed to get auth token. Please verify user and password.")
		return False

	if cfg.api_token == "NA":
		print("Error: auth token is NA.")
		return False

	return True


def _downloadAgentConfig(cfg: Config):
	"""
	Download agent configuration from the server and parse it.

	:param cfg: Config instance
	:returns: tuple of (agent_config dict, pubKey str, pubKeyHash str),
	          or (None, None, None) on failure
	"""
	print("Download agent configuration")
	agent_config_res = getAgentConfigurationData(cfg)
	if not agent_config_res:
		print("Error getting agent configuration, is None")
		return None, None, None

	for required_key in ('plist', 'pubKey', 'pubKeyHash'):
		if required_key not in agent_config_res:
			print("Error: agent configuration is missing '{}' key.".format(required_key))
			return None, None, None

	_tmp_datafile = '/tmp/agentConfig.plist'
	if os.path.exists(_tmp_datafile):
		os.remove(_tmp_datafile)
	with open(_tmp_datafile, "w") as f:
		f.write(agent_config_res['plist'])
	with open(_tmp_datafile, 'rb') as fp:
		_dict = plistlib.load(fp)

	return _dict['default'], agent_config_res['pubKey'], agent_config_res['pubKeyHash']


def _preparePackages(cfg: Config, agent_config: dict, pubKey: str, pubKeyHash: str) -> Optional[list]:
	"""
	Extract, configure, flatten, notarize, and compress the agent packages.

	:param cfg: Config instance
	:param agent_config: agent configuration dict
	:param pubKey: server public key string
	:param pubKeyHash: md5 hash of the public key
	:returns: list of finished .zip package paths, or None on failure
	"""
	print("Unzip and extract package")
	if not os.path.exists(cfg.agent_package_path):
		print("Error: agent package path is not defined or not found.")
		return None

	print("PKG_DEST_DIR: " + str(cfg.pkg_dest_dir))
	if not extractAgentPKG(cfg, cfg.agent_package_path):
		return None

	if cfg.pkg_tmp_dir is None:
		print("Error: package tmp dir is not defined.")
		return None

	base_dir = os.path.join(cfg.pkg_tmp_dir, "MacPatch")
	print("Working dir (base_dir) is {}".format(base_dir))

	packages = getPackagesFromArchiveDir(base_dir)
	if packages is None:
		print("Error: no packages to process.")
		return None

	print("Write config data to packages.")
	if not writeServerPubKeyToPackage(packages, pubKey, pubKeyHash):
		print("Error writing server public key data")
		return None

	if not writePlistToPackage(cfg, packages, agent_config):
		print("Error writing agent config data")
		return None

	if cfg.plugins_directory is not None:
		if not writePluginsToPackage(cfg, packages, cfg.plugins_directory):
			print("Error copying plugins to packages.")

	ver_info_file = os.path.join(base_dir, "Resources/mpInfo.plist")
	if os.path.exists(ver_info_file):
		for p in packages:
			if not writeVersionInfoToPackage(cfg, p, ver_info_file):
				print("Error writing version info to packages.")

	if cfg.registration_key is not None:
		if not writeRegKeyToPackage(packages, cfg.registration_key):
			print("Error writing registration key to packages.")

	if not changeBackgroundImageToDoneImage(base_dir):
		print("Error changing pkg background image.")

	packages.append(base_dir)
	flatten_packages = flattenPackages(cfg, packages, cfg.pkg_tmp_dir)

	if cfg.notorize:
		n = (
			NotarizeTool(cfg.dev_account, cfg.apple_id_app_password, cfg.dev_team)
			if cfg.notarize_tool == "notarytool" else
			Notorize(cfg.dev_account, cfg.apple_id_app_password)
		)
	else:
		n = None

	_finished_packages = []
	for f in flatten_packages:
		removePKG     = False
		removePKGPath = f
		if "toSign_" in f:
			f         = f.replace('toSign_', '')
			removePKG = True

		if cfg.notorize:
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


def _uploadPackages(cfg: Config, finished_packages: list) -> None:
	"""
	Save upload manifest to disk and optionally post packages to the server.

	:param cfg: Config instance
	:param finished_packages: list of .zip package paths to upload
	"""
	formData = {
		"app":      cfg.agent_dictionary,
		"update":   cfg.updater_dictionary,
		"plugins":  [],
		"profiles": []
	}

	uploadData = {
		'pkgs':   finished_packages,
		'data':   formData,
		'token':  cfg.api_token,
		'pkgDir': cfg.pkg_tmp_dir
	}
	with open(os.path.join(cfg.pkg_tmp_dir, 'uploadData.json'), 'w') as outfile:
		json.dump(uploadData, outfile)

	if cfg.upload_pkgs:
		uploadPackagesToServer(cfg, finished_packages, formData)
	else:
		print("Upload packages is disabled.")


def processAgentPackage(cfg: Config) -> None:
	"""
	Orchestrate the full agent package build and upload pipeline:
	authenticate, download config, prepare packages, and upload.

	:param cfg: Config instance
	"""
	print("Begin Processing Agent Packages")

	if not _authenticate(cfg):
		return

	agent_config, pubKey, pubKeyHash = _downloadAgentConfig(cfg)
	if agent_config is None:
		return

	finished_packages = _preparePackages(cfg, agent_config, pubKey, pubKeyHash)
	if finished_packages is None:
		return

	_uploadPackages(cfg, finished_packages)
	subprocess.run(['/usr/bin/open', cfg.pkg_tmp_dir])


def uploadPackagesToServer(cfg: Config, packages: list, formData: dict) -> bool:
	"""
	Upload finished packages to the MacPatch server.

	:param cfg: Config instance
	:param packages: list of .zip package paths
	:param formData: metadata dict to post alongside the packages
	:returns: True on success, False on failure
	"""
	aid  = str(uuid.uuid4())
	_url = _build_url(cfg, "/agent/upload/{}/{}".format(aid, cfg.api_token), prefix="/api/v3")

	fileData = {}
	print("Processing packages for uploading to MacPatch server")
	for p in packages:
		if "Base.pkg" in p:
			fileData['fBase']     = ('Base.pkg.zip',    open(p, 'rb'), 'application/octet-stream')
		elif "Updater.pkg" in p:
			fileData['fUpdate']   = ('Updater.pkg.zip', open(p, 'rb'), 'application/octet-stream')
		elif "MacPatch.pkg" in p:
			fileData['fComplete'] = ('MacPatch.pkg.zip', open(p, 'rb'), 'application/octet-stream')

	_files = {
		'fBase':     fileData['fBase'],
		'fUpdate':   fileData['fUpdate'],
		'fComplete': fileData['fComplete'],
		'jData':     ('', json.dumps(formData), 'application/json')
	}

	try:
		print("Uploading packages to MacPatch server ...")
		_response = requests.post(_url, files=_files, verify=cfg.verify_ssl)
		print(_response.text)

		if _response.ok:
			res      = _response.json()
			_resDict = res["result"]
			print(_resDict)
			if "token" in _resDict:
				cfg.api_token = _resDict['token']
				return True

		return False

	except requests.exceptions.HTTPError as err:
		print("Http Error:", err)
	except requests.exceptions.ConnectionError as errc:
		print("Error Connecting:", errc)
	except requests.exceptions.Timeout as errt:
		print("Timeout Error:", errt)
	except requests.exceptions.RequestException as err:
		print("Request Error:", err)

	return False


def uploadTestedPackagesToServer(cfg: Config, dataFile: str) -> None:
	"""
	Re-upload packages from a previously saved uploadData.json manifest.

	:param cfg: Config instance
	:param dataFile: path to uploadData.json
	"""
	with open(dataFile) as f:
		uploadData = json.load(f)

	cfg.api_token   = uploadData['token']
	cfg.pkg_tmp_dir = uploadData['pkgDir']
	uploadPackagesToServer(cfg, uploadData['pkgs'], uploadData['data'])


# -----------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------

def main():
	os.system('clear')
	print("")
	print("******* MacPatch Agent Uploader *******")
	print("")

	parser = argparse.ArgumentParser(description='MacPatch Agent Package Uploader')

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
	parser.add_argument('--notarize-tool', dest='notarizeTool', choices=['altool', 'notarytool'], default=None, help='Notarization tool: altool (legacy, Xcode <15) or notarytool (Xcode 15+, default).')
	parser.add_argument('--no-verify-ssl', dest='noVerifySSL', action='store_true', default=False, help='Disable SSL certificate verification (use for self-signed certs).')
	parser.add_argument('-c', dest='configFile', help='External Config File for agent upload')
	parser.add_argument('-j', dest='jUploadData', help='Upload Data file. Upload tested packages.')
	parser.add_argument('--destDir', dest='pkgDestDir', help='The base path to the processed pkg.')

	args = parser.parse_args()

	# Build config: file first, then CLI args overlay on top
	cfg = Config.from_file(args.configFile) if args.configFile else Config()
	cfg.apply_args(args)

	if args.jUploadData is not None:
		uploadTestedPackagesToServer(cfg, args.jUploadData)
	else:
		processAgentPackage(cfg)


if __name__ == "__main__":
	main()