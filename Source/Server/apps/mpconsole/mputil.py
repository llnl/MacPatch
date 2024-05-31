'''
	Extent flask_restful.Resource

	Need access to HTTP_X header data

	This module should be renamed to be more descriptive :)
'''

from flask import current_app
import json
import os.path

from cryptography.exceptions import *
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding

from base64 import b64encode, b64decode

from . import db
from . model import MpSiteKeys
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
		print(("Error, could not open file " + configFile.strip()))

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

		if isinstance(data, dict):
			_data = ""
			for key in sorted(data):
				if not isinstance(data[key], dict):
					_data = _data + str(key) + str(data[key])
				else:
					_data = _data + str(key) + "DICT"

			data = _data

		try:
			private_key = serialization.load_pem_private_key( bytes(qKeys.priKey,'utf-8'), password=None, backend=default_backend() )
			signature = private_key.sign( data.encode('utf-8'), padding.PKCS1v15(), hashes.SHA1() )
			encodedSignature = b64encode(signature).decode('utf-8')

			return encodedSignature

		except InvalidKey:
			log_Error("InvalidKey, Unable to sign data.")
			return None
		except:
			log_Error("Error, Unable to sign data.")
			return None
	else:
		return None

def verifySignedData(signature, data):
	qKeys = MpSiteKeys.query.filter(MpSiteKeys.active == '1').first()
	if qKeys is not None:
		try:
			# Get Keys
			private_key = serialization.load_pem_private_key( bytes(qKeys.priKey,'utf-8'), password=None, backend=default_backend() )
			public_key = private_key.public_key()
			# Verify Signature
			result = public_key.verify(b64decode(signature), data.encode('utf-8'), padding.PKCS1v15(),hashes.SHA1())
			return True
		except InvalidSignature:
			log_Error("InvalidSignature, Unable to verify signature.")
			log_Debug("Signature: " + signature)
			log_Debug("Data: " + data)
			return False
		except InvalidKey:
			log_Error("InvalidKey, Unable to verify signature.")
			return False
		except:
			log_Error("Error, Unable to verify signature.")
			return False

	log_Error("[verifySignedData] Error, unable to get RSA keys from database.")
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

from datetime import datetime
def json_serial(obj):
	"""JSON serializer for objects not serializable by default json code"""

	if isinstance(obj, datetime):
		serial = obj.strftime('%Y-%m-%d %H:%M:%S')
		return serial

# ----------------------------------------------------------------------------
'''
		Base64 With Default
'''
def b64EncodeAsString(data, defaultValue=None):
	result = ''
	if defaultValue is not None:
			result = defaultValue

	if data is not None:
			if data.__class__ != 'bytes':
					if len(data) > 0:
							data = data.encode('utf-8')
							result = b64encode(data).decode('utf-8')
			else:
					if len(data) > 0:
							result = b64encode(data).decode('utf-8')

	return result




