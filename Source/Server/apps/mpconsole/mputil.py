'''
	Extent flask_restful.Resource

	Need access to HTTP_X header data

	This module should be renamed to be more descriptive :)
'''

from flask import current_app
import json
import os.path
from . mplogger import log_Debug, log_Info, log_Error

from Crypto.PublicKey import RSA
from Crypto.Signature import PKCS1_v1_5
from Crypto.Hash import SHA256, SHA
from base64 import b64encode, b64decode, encodestring

from . import db
from . model import MPAgentRegistration, MpClient, AdmGroupUsers, AdmUsers, AdmUsersInfo, MpSiteKeys
from . mplogger import log_Debug, log_Info, log_Error

# ----------------------------------------------------------------------------
'''
	Read Server Config file
'''

def read_config_file(configFile):

	data = {}
	if os.path.exists(configFile.strip()):
		try:
			with open(configFile.strip()) as data_file:
				data = json.load(data_file)

		except OSError:
			print('Well darn.')

	else:
		print("Error, could not open file " + configFile.strip())

	return data

def mpConfig():
	cnfFile = current_app.config['SITECONFIG_FILE']
	_config = read_config_file(cnfFile)
	return _config

def return_data_for_root_key(key):
	_config = mpConfig()
	if _config is None:
		return None

	_config = _config['settings']
	if key in _config:
		return _config[key]
	else:
		return None

def return_data_for_server_key(key):
	_config = mpConfig()
	if _config is None:
		return None

	_config = _config['settings']['server']
	if key in _config:
		return _config[key]
	else:
		return _config

# ----------------------------------------------------------------------------
'''
	Sign Message
'''

def signData(data):
	qKeys = MpSiteKeys.query.filter(MpSiteKeys.active == '1').first()
	if qKeys is not None:
		# Using SHA1 padding
		rsakey = RSA.importKey(qKeys.priKey)
		signer = PKCS1_v1_5.new(rsakey)
		digest = SHA.new()

		digest.update(data)
		sign = signer.sign(digest)
		return b64encode(sign)
	else:
		return None

def verifySignedData(signature, data):
	qKeys = MpSiteKeys.query.filter(MpSiteKeys.active == '1').first()
	if qKeys is not None:
		# Using SHA1 padding
		rsakey = RSA.importKey(qKeys.pubKey)
		signer = PKCS1_v1_5.new(rsakey)
		digest = SHA.new()

		digest.update(data)
		if signer.verify(digest, b64decode(signature)):
			return True

	return False

# ----------------------------------------------------------------------------
'''
	Utility Functions
'''

import os
import shutil
import stat

def copytree(src, dst, symlinks = False, ignore = None):
	if not os.path.exists(dst):
		os.makedirs(dst)
		shutil.copystat(src, dst)
	lst = os.listdir(src)
	if ignore:
		excl = ignore(src, lst)
		lst = [x for x in lst if x not in excl]
	for item in lst:
		s = os.path.join(src, item)
		d = os.path.join(dst, item)
		if symlinks and os.path.islink(s):
			if os.path.lexists(d):
				os.remove(d)
			os.symlink(os.readlink(s), d)
			try:
				st = os.lstat(s)
				mode = stat.S_IMODE(st.st_mode)
				os.lchmod(d, mode)
			except:
				pass # lchmod not available
		elif os.path.isdir(s):
			copytree(s, d, symlinks, ignore)
		else:
			shutil.copy2(s, d)
