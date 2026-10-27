'''
	Extent flask_restful.Resource

	Need access to HTTP_X header data

	This module should be renamed to be more descriptive :)
'''

from flask import current_app
import json
import os.path
import jwt
from datetime import datetime, timedelta

from cryptography.exceptions import *
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.fernet import Fernet

from base64 import b64encode, b64decode, urlsafe_b64encode

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

# ----------------------------------------------------------------------------
'''
	Symmetric Encryption/Decryption using Fernet
'''
def _get_encryption_key():
	"""Derive a Fernet key from the SECRET_KEY"""
	import sys
	secret_key = current_app.config['SECRET_KEY'].encode('utf-8')
	# Use a fixed salt for key derivation (same as API)
	salt = b'MacPatch_DB_Config_Salt_v1'
	kdf = PBKDF2HMAC(
		algorithm=hashes.SHA256(),
		length=32,
		salt=salt,
		iterations=100000,
		backend=default_backend()
	)
	key = urlsafe_b64encode(kdf.derive(secret_key))
	return key

def encryptData(data):
	"""Encrypt data using Fernet symmetric encryption"""
	import sys
	try:
		if isinstance(data, dict):
			data = json.dumps(data)
		if isinstance(data, str):
			data = data.encode('utf-8')

		key = _get_encryption_key()
		f = Fernet(key)
		encrypted = f.encrypt(data)
		return b64encode(encrypted).decode('utf-8')
	except Exception as e:
		exc_type, exc_obj, exc_tb = sys.exc_info()
		message = str(e.args[0]) if e.args else str(e)
		log_Error('[encryptData][Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
		return None

def decryptData(encrypted_data):
	"""Decrypt data using Fernet symmetric encryption"""
	import sys
	import traceback
	try:
		if isinstance(encrypted_data, str):
			encrypted_data = b64decode(encrypted_data.encode('utf-8'))

		key = _get_encryption_key()
		f = Fernet(key)
		decrypted = f.decrypt(encrypted_data)

		# Try to parse as JSON, otherwise return as string
		try:
			return json.loads(decrypted.decode('utf-8'))
		except:
			return decrypted.decode('utf-8')
	except Exception as e:
		exc_type, exc_obj, exc_tb = sys.exc_info()
		message = str(e) if str(e) else repr(e)
		log_Error('[decryptData][Exception][Line: {}] Type: {} Message: {}'.format(
			exc_tb.tb_lineno, exc_type.__name__, message))
		log_Error('[decryptData] Traceback: {}'.format(traceback.format_exc()))
		return None

def generate_jwt_token(expiration_minutes=5):
	"""Generate JWT token for Console-to-API authentication"""
	try:
		secret_key = current_app.config.get('SECRET_KEY')
		if not secret_key:
			log_Error('[generate_jwt_token] SECRET_KEY not found in config')
			return None

		payload = {
			'exp': datetime.utcnow() + timedelta(minutes=expiration_minutes),
			'iat': datetime.utcnow(),
			'iss': 'mpconsole',
			'aud': 'mpapi'
		}

		token = jwt.encode(payload, secret_key, algorithm='HS256')
		log_Debug('[generate_jwt_token] JWT token generated successfully')
		return token
	except Exception as e:
		log_Error('[generate_jwt_token] Failed to generate token: {}'.format(str(e)))
		return None

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




