'''
	Extent flask_restful.Resource

	Need access to HTTP_X header data

	This module should be renamed to be more descriptive :)
'''

from flask import request, current_app
import flask_restful
import hashlib
import sys
import json
import os.path
import hmac
from ldap3 import Server, Connection, ALL, AUTO_BIND_NO_TLS, SUBTREE, ALL_ATTRIBUTES
from itsdangerous.url_safe import URLSafeTimedSerializer as Serializer
from itsdangerous import BadSignature, SignatureExpired
from werkzeug.security import check_password_hash

from cryptography.exceptions import *
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding

from base64 import b64encode, b64decode

from mpapi.app import db
from mpapi.model import MPAgentRegistration, MpClient, AdmGroupUsers, AdmUsers, AdmUsersInfo, MpSiteKeys
from mpapi.mplogger import *
from mpapi.mpldap import MPldap

# ----------------------------------------------------------------------------
'''
	Extended flask_restful.Resource
	Use on all API resources.
	Includes requires MacPatch HTTP Header Fields
'''
class MPResource(flask_restful.Resource):
	def __init__(self):
		req = request.environ
		self.req_signature  = self.reqKeyValue(req, 'HTTP_X_API_SIGNATURE')
		self.req_akey       = self.reqKeyValue(req, 'HTTP_X_API_KEY')
		self.req_ts         = self.reqKeyValue(req, 'HTTP_X_API_TS')
		self.req_agent      = self.reqKeyValue(req, 'HTTP_X_AGENT_ID')
		self.req_agent_ver  = self.reqKeyValue(req, 'HTTP_X_AGENT_VER')
		self.req_uri        = self.reqKeyValue(req, 'PATH_INFO')

	def reqKeyValue(self, req, key):
		if key in req:
			return req[key]
		else:
			return 'NA'

# ----------------------------------------------------------------------------
'''
	Verify Signature
	Verify ClientID
	Verify API Key
'''

def isValidSignature(Signature, ClientID, Data, TimeStamp):

	if not current_app.config['REQUIRE_SIGNATURES']:
		# REQUIRE_SIGNATURES is false, return true on signature
		# evaluation
		return True

	qGet = MPAgentRegistration.query.filter_by(cuuid=ClientID).first()
	if qGet is not None:
		rec = qGet.asDict
		cKey = rec['clientKey']

		log_Debug('[isValidSignature][Data]: (%s)' % (str(Data)))
		log_Debug('[isValidSignature][Time]: (%s)' % (TimeStamp))

		secret = bytes(cKey,'utf-8')
		message_str = '%s-%s' % (str(Data), TimeStamp)
		message = bytes(message_str, 'utf-8')

		log_Debug('[isValidSignature][secret]: (%s)' % (secret[-4:]))
		log_Debug('[isValidSignature][message_str]: (%s)' % (message_str))

		xSigHash = hmac.new(secret, message, hashlib.sha256).hexdigest()

		log_Debug('[isValidSignature][Signature][Expected]: %s' % (Signature))
		log_Debug('[isValidSignature][Signature][Verified]: %s' % (xSigHash))

		if xSigHash.lower() == Signature.lower():
			return True
		else:
			log_Error("Signature hash verify failed.")
			log_Error("%s == %s".format(Signature,xSigHash))
			return False
	else:
		return False

def isValidClientID(ClientID):

	if 'VERIFY_CLIENTID' not in current_app.config:
		return True
	else:
		if not current_app.config['VERIFY_CLIENTID']:
			return True

	if 'CLIENTID_ZERO' in current_app.config:
		if current_app.config['CLIENTID_ZERO']:
			return True

	client_obj = MPAgentRegistration.query.filter_by(cuuid=ClientID).first()

	if client_obj:
		return True
	else:
		return False

def isValidAPIKey(key_hash, dtstamp):

	# Get the API Key from the siteconfig.json
	apiKey = return_data_for_server_key('apiKey')
	apiKeyExtra = "%s-%s" % (apiKey, dtstamp)
	_apiKeyHash = hashlib.sha1(apiKeyExtra.encode('utf-8')).hexdigest()

	if _apiKeyHash.lower() == key_hash.lower():
		return True
	else:
		return False


# ----------------------------------------------------------------------------
'''
	Authentication for users & User rights
'''
def authUser(username_or_token, password):

	res = False
	# first try to authenticate by token
	user = verify_auth_token(username_or_token)
	if not user or (user == "BadSignature" or user == "SignatureExpired"):
		# First Check Local Admin Account
		res = defaultAdminAuth(username_or_token, password)
		if res:
			return res

		# Check Database Accounts
		res = dbUserAuth(username_or_token, password)
		if res:
			return res

		# Last Check LDAP Accounts
		if current_app.config['LDAP_SRVC_ENABLED']:
			# Init LDAP class
			mpLDAP = MPldap(current_app)
			# Seach the directory for user logging in
			foundUserDN = mpLDAP.findOUN(username_or_token)

			if foundUserDN is not None:
				# User was found in the directory 
				# Lets try the auth for the user logging in
				if mpLDAP.authOUN(foundUserDN, username_or_token, password):
					return True
	else:
		# Token Was Good
		return True

	log_Error("Error unable to verify user against any datasource.")
	return res

'''
	Default Auth User
'''
def defaultAdminAuth(user, password):
	users = return_data_for_root_key('users')
	if "admin" in users:
		admin = users['admin']
		if admin['enabled']:
			if user == admin['name'] and password.lower() == admin['pass'].lower():
				return True
			else:
				return False
		else:
			print("Default admin account is disabled.")
			return False
	else:
		return False

'''
	Database Auth User
'''
def dbUserAuth(user, password):

	try:
		admUser = AdmUsers.query.filter(AdmUsers.user_id == user, AdmUsers.enabled == 1).first()
		if admUser:
			res = check_password_hash(admUser.user_pass, password)
			if res:
				return True
			else:
				log_Error("Error with user name or password.")
				return False
		else:
			log_Error("Error with user name or password.")
			return False

	except:  # catch *all* exceptions
		e = sys.exc_info()[0]
		print(e)
		return False

'''
	LDAP User Auth
'''
def ldapAuth(ldap_conf, user, password):
	try:
		server = None
		_config = current_app.config
		if 'server' in ldap_conf and 'port' in ldap_conf and 'useSSL' in ldap_conf:
			_use_ssl = True
			if ldap_conf['useSSL'] is False:
				log_Warn('SSL is not enabled for LDAP queries, this is not recommended.')
				_use_ssl = False

			if not isinstance(ldap_conf['port'], int):
				ldap_conf['port'] = int(ldap_conf['port'])

			server = Server(host=ldap_conf['server'], port=ldap_conf['port'], use_ssl=_use_ssl)

		conn = Connection(server, user=userID, password=password)

		didBind = conn.bind()
		if not didBind:
			log_Error("Error with user name or password. Unable to bind to ldap server.")
			return False

		_sFilter = "(&(objectClass=*)(" + ldap_conf['loginAttr'] + "=" + userID + "))"
		didSearch = conn.search(search_base=ldap_conf['searchbase'], search_filter=_sFilter,
					search_scope=SUBTREE, attributes=ALL_ATTRIBUTES, get_operational_attributes=True)

		if not didSearch:
			conn.unbind()
			log_Error("Error unable to find user info in directory.")
			return False
		else:
			res = conn.entries[0]
			conn.unbind()
			return res

	except:  # catch *all* exceptions
		e = sys.exc_info()[0]
		log_Error(e)
		return False

'''
	User Rights Methods
'''
def adminUserRights(user):
	'''
		Get User Rights for user account id

		:param user:
		:return:
	'''
	try:
		admObj = None
		admUser = AdmUsers.query.filter(AdmUsers.user_id == user, AdmUsers.enabled == 1).first()
		if not admUser:
			log_Error("No user (%s) found to check for rights.".format(user))
			return None

		admObj = AdmUsersInfo.query.filter(AdmUsersInfo.user_id == user, AdmUsersInfo.enabled == 1).first()
		if admObj:
			return admObj
		else:
			log_Error("User %s not found or user is disabled.".format(user))
			return None

	except:  # catch *all* exceptions
		e = sys.exc_info()[0]
		print(e)
		return None

def isValidAutoPKGUser(user):
	if isLocalServerAdmin(user):
		return True

	admUsr = adminUserRights(user)
	if admUsr:
		if admUsr.autopkg == 1:
			return True

	return False

def isValidAdminUser(user):
	if isLocalServerAdmin(user):
		return True

	admUsr = adminUserRights(user)
	if admUsr:
		if admUsr.admin == 1:
			return True

	return False

def isValidAgentUploadUser(user):
	if isLocalServerAdmin(user):
		return True

	admUsr = adminUserRights(user)
	if admUsr:
		if admUsr.agentUpload == 1:
			return True

	return False
'''
	Convenience Methods
'''
def isLocalServerAdmin(user):
	'''
	Checks to see if the user id is the local server admin account.
	If it is, and enabled it will pass true.
	This method will be used to pass all rights for the system.

	:param user:
	:return:
	'''
	users = return_data_for_root_key('users')
	if "admin" in users:
		admin = users['admin']
		if admin['enabled'] and user == admin['name']:
			return True

	return False

def isValidToken(user, token):

	_user = verify_auth_token(token)
	if user == _user:
		return True
	else:
		return False

def verify_auth_token(token):
	s = Serializer(current_app.config['SECRET_KEY'])
	try:
		data = s.loads(token)
	except SignatureExpired:
		return "SignatureExpired"  # valid token, but expired
	except BadSignature:
		return "BadSignature"  # invalid token

	return data['id']

def verify_auth_password(username_or_token, password):
	return authUser(username_or_token, password)

# ----------------------------------------------------------------------------
'''
	Send Email
'''
def sendEmailMessage(subject, message, address=None):

	admUsrLst = []
	admUsr = AdmGroupUsers.query.filter(AdmGroupUsers.email_notification == 1, AdmGroupUsers.user_email != None).all()
	for i in admUsr:
		admUsrLst.append(i.user_email)
	# If No Email Addresses then dont send
	if len(admUsrLst) <= 0:
		return
	admEmlLst = ",".join(admUsrLst)

	import smtplib
	import sys
	try:
		_msrv = return_data_for_root_key('mailserver')
		_srv = _msrv['server']
		_prt = 25
		if 'port' in _msrv:
			_prt = _msrv['port']

		session = smtplib.SMTP(_srv, _prt)
		session.ehlo()
		if 'usetls' in _msrv:
			if _msrv['usetls']:
				session.starttls()
		if 'username' in _msrv and 'password' in _msrv:
			session.login(_msrv['username'], _msrv['password'])

		headers = "\r\n".join(["from: " + 'macpatch@your.macpatch.server.com',
							"subject: " + subject,
							"to: " + admEmlLst,
							"mime-version: 1.0",
							"content-type: text/html"])

		# body_of_email can be plaintext or html!
		content = headers + "\r\n\r\n" + message
		session.sendmail('macpatch@your.macpatch.server.com', admEmlLst, content)
	except:
		print(("Unexpected error:", sys.exc_info()[0]))

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
			if not private_key:
				log_Error("Missing Private Key.")
			signature = private_key.sign( data.encode('utf-8'), padding.PKCS1v15(), hashes.SHA1() )
			encodedSignature = b64encode(signature).decode('utf-8')

			return encodedSignature

		except InvalidKey:
			log_Error("InvalidKey, Unable to sign data.")
			return None

		except Exception as e:
			log_Error("Error, Unable to sign data.")
			exc_type, exc_obj, exc_tb = sys.exc_info()
			message=str(e.args[0]).encode("utf-8")
			log_Error('[signData][Exception][Line: {}] Message: {}'.format(exc_tb.tb_lineno, message))
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
			print('InvalidSignature.')
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

def rowWithDefault(obj,attribute,defaultValue=None):
	row = obj.asDict
	if attribute in row:
		return row[attribute]
	else:
		return defaultValue


