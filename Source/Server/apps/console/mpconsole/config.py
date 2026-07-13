import os
import secrets
from dotenv import load_dotenv
from datetime import timedelta
from redis import Redis

basedir = os.path.abspath(os.path.dirname(__file__))
consoledir = os.path.dirname(basedir)
appsdir = os.path.dirname(consoledir)

dotFileGlobal=os.path.join(appsdir, '.mpglobal')
dotFileConsole=os.path.join(appsdir, '.mpconsole')
load_dotenv(dotFileGlobal, override=True)
load_dotenv(dotFileConsole, override=True)

MP_ROOT_DIR	= os.environ.get('MP_ROOT_DIR') or '/opt/MacPatch'
MP_SRV_DIR	= MP_ROOT_DIR+'/Server'

def get_secret_key():
	"""
	Get SECRET_KEY from environment variable.
	CRITICAL SECURITY: SECRET_KEY must be set in environment or .mpglobal file.
	If not set, application will fail to start (no insecure fallback).
	"""
	secret_key = os.environ.get('SECRET_KEY')
	if not secret_key:
		raise RuntimeError(
			"CRITICAL SECURITY ERROR: SECRET_KEY environment variable is not set!\n"
			"Generate a secure key with: python -c 'import secrets; print(secrets.token_hex(32))'\n"
			"Set it in .mpglobal file or environment variable before starting the application."
		)
	if len(secret_key) < 32:
		raise RuntimeError(
			"CRITICAL SECURITY ERROR: SECRET_KEY must be at least 32 characters long.\n"
			f"Current length: {len(secret_key)}. Generate a new key with:\n"
			"python -c 'import secrets; print(secrets.token_hex(32))'"
		)
	return secret_key

def get_secret_keys():
	"""
	Get list of SECRET_KEYs for graceful key rotation.

	Returns a list with:
	- Primary key (used for signing new tokens) - SECRET_KEY
	- Old keys (accepted for verification only) - SECRET_KEY_OLD, SECRET_KEY_OLD_2, etc.

	This allows graceful key rotation without immediately invalidating all tokens.

	Example rotation workflow:
	1. Set SECRET_KEY_OLD to current SECRET_KEY
	2. Set SECRET_KEY to new key
	3. Restart services
	4. Wait for old tokens to expire (e.g., 24 hours)
	5. Remove SECRET_KEY_OLD
	"""
	keys = [get_secret_key()]  # Primary key always first

	# Add old keys for validation during transition
	old_key = os.environ.get('SECRET_KEY_OLD')
	if old_key and len(old_key) >= 32:
		keys.append(old_key)

	old_key_2 = os.environ.get('SECRET_KEY_OLD_2')
	if old_key_2 and len(old_key_2) >= 32:
		keys.append(old_key_2)

	return keys

def as_bool(value):
	if value:
		return value.lower() in ['true', 'yes', 'on', '1']
	return False

def as_none(value):
	if value.lower() in ['none', '', 'empty', '0']:
		return None
	else:
		return value

class Config(object):

	BASEDIR 				= basedir

	DEBUG   				= as_bool(os.environ.get('DEBUG') or 'no')
	TESTING 				= as_bool(os.environ.get('TESTING') or 'no')
	
	MAX_CONTENT_LENGTH		= 9000 * 1024 * 1024    # 9000 Mb limit

	# Web Server Options
	# Use 127.0.0.1 and port 3601, NGINX will be the outward facing
	# avenue for clients to communicate.
	SRV_HOST				= '127.0.0.1'
	SRV_PORT				= 3602

	USE_CORS				= as_bool(os.environ.get('USE_CORS') or 'yes')
	CORS_HEADERS			= 'Content-Type'
	OBSCURE_SALT			= int(os.environ.get('OBSCURE_SALT') or '4049') 
	MAKE_SAFE				= os.environ.get('MAKE_SAFE') or 'SomethingToMakeSafeAsAString'

	# Database Options
	DB_USER                         = os.environ.get('DB_USER') or 'mpdbadm'
	DB_PASS                         = os.environ.get('DB_PASS') or 'password'
	DB_HOST                         = os.environ.get('DB_HOST') or 'localhost'
	DB_PORT                         = int(os.environ.get('DB_PORT') or '3306')
	DB_NAME                         = os.environ.get('DB_NAME') or 'MacPatchDB'
	SQLALCHEMY_DATABASE_URI         = 'mysql+pymysql://'
	SQLALCHEMY_TRACK_MODIFICATIONS  = False
	SQLALCHEMY_ENGINE_OPTIONS = { 'pool_size' : 50,
                                  'pool_recycle': 120,
                                  'pool_timeout': 20,
                                  'pool_pre_ping': True }

	# App Options
	# CRITICAL SECURITY: SECRET_KEY must be set via environment variable
	# The hardcoded key has been removed for security. Set SECRET_KEY in .mpglobal or environment.
	SECRET_KEY          		= get_secret_key()
	SECRET_KEYS                 = get_secret_keys()  # For graceful key rotation (primary + old keys)
	PERMANENT_SESSION_LIFETIME	= timedelta(minutes=10)

	# Logging
	LOGGING_FORMAT      = '%(asctime)s [%(name)s][%(levelname).3s] --- %(message)s'
	LOGGING_LEVEL       = os.environ.get('LOGGING_LEVEL') or 'info'
	LOGGING_LOCATION    = MP_SRV_DIR+'/apps/logs'
	LOG_FILE_NAME		= os.environ.get('LOG_FILE_NAME') or 'mpconsole.log'
	LOG_FILE 			= LOGGING_LOCATION + '/' + LOG_FILE_NAME

	# Session
	SESSION_TYPE 				= 'redis' #'filesystem'
	SESSION_REDIS				= Redis(host='localhost', port=6379)
	SESSION_TIMEOUT_MINUTES		= 60
	PERMANENT_SESSION_LIFETIME	= timedelta(minutes=60)

	# MacPatch App Options
	SITECONFIG_FILE     = MP_SRV_DIR+'/etc/siteconfig.json'
	CONTENT_DIR         = MP_ROOT_DIR+'/Content'
	AGENT_CONTENT_DIR   = MP_ROOT_DIR+'/Content/Web/clients'
	PATCH_CONTENT_DIR   = MP_ROOT_DIR+'/Content/Web/patches'
	SW_CONTENT_DIR      = MP_ROOT_DIR+'/Content/Web/sw'

	STATIC_DIR			= basedir + '/static'
	STATIC_JSON_DIR		= STATIC_DIR + '/json'

	JOBS_FILE 			= STATIC_JSON_DIR+'/jobs.json'
	JOBS 				= []

	# Authentication
	LOCAL_AUTH_ALLOWED			= as_bool(os.environ.get('LOCAL_AUTH_ALLOWED') or 'yes')

	# Session
	SESSION_TYPE 				= 'redis' #'filesystem'
	SESSION_REDIS				= Redis(host='localhost', port=6379)
	SESSION_TIMEOUT_MINUTES		= 60
	PERMANENT_SESSION_LIFETIME	= timedelta(minutes=60)

	SCHEDULER_API_ENABLED 	= as_bool(os.environ.get('SCHEDULER_API_ENABLED') or 'yes')
	ALLOW_CONTENT_DOWNLOAD 	= as_bool(os.environ.get('ALLOW_CONTENT_DOWNLOAD') or 'no')
	REDIRECT_TO_NEW_API 	= as_bool(os.environ.get('REDIRECT_TO_NEW_API') or 'yes')

	# LDAP/Active Directory
	LDAP_SRVC_ENABLED		= as_bool(os.environ.get('LDAP_SRVC_ENABLED') or 'no')
	LDAP_SRVC_SERVER		= os.environ.get('LDAP_SRVC_SERVER') or 'example.com'
	LDAP_SRVC_PORT			= int(os.environ.get('LDAP_SRVC_PORT') or '636') 
	LDAP_SRVC_SSL			= as_bool(os.environ.get('LDAP_SRVC_SSL') or 'yes')
	LDAP_SRVC_USERDN		= os.environ.get('LDAP_SRVC_USERDN') or 'CN=Mac Patch,OU=Users,DC=example,DC=com'
	LDAP_SRVC_PASS			= os.environ.get('LDAP_SRVC_PASS') or 'LDAP_SRVC_PASS'
	LDAP_SRVC_SEARCHBASE	= os.environ.get('LDAP_SRVC_SEARCHBASE') or 'dc=example,dc=com'
	LDAP_SRVC_MULTISERVER	= as_bool(os.environ.get('LDAP_SRVC_MULTISERVER') or 'no')
	LDAP_SRVC_POOL_TYPE		= os.environ.get('LDAP_SRVC_POOL_TYPE') or 'FIRST' # Supports FIRST or ROUND_ROBIN

	# AWS - MP
	USE_AWS_S3				= as_bool(os.environ.get('USE_AWS_S3') or 'no')
	AWS_S3_KEY				= os.environ.get('AWS_S3_KEY') or 'AWS_S3_KEY_STRING'
	AWS_S3_SECRET			= os.environ.get('AWS_S3_SECRET') or 'AWS_S3_SECRET_STRING'
	AWS_S3_BUCKET			= os.environ.get('AWS_S3_BUCKET') or 'AWS_S3_SECRET_STRING'
	AWS_S3_REGION			= as_none(os.environ.get('AWS_S3_REGION') or 'none')

	# InTune - MDM
	ENABLE_INTUNE				= False
	INTUNE_RESOURCE				= "https://graph.microsoft.com"
	INTUNE_TENANT				= ""
	INTUNE_AUTHORITY_HOST_URL	= ""
	INTUNE_CLIENT_ID			= ""
	INTUNE_CLIENT_SECRET		= ""
	INTUNE_USER					= ""
	INTUNE_USER_PASS			= ""

	# MSAL Auth
	MSAL_CLIENT_ID		= os.environ.get('MSAL_CLIENT_ID') or 'NO_ID_SET'
	MSAL_CLIENT_SECRET  = os.environ.get('MSAL_CLIENT_SECRET') or 'NO_SECRET_SET'
	MSAL_AUTHORITY      = os.environ.get('MSAL_AUTHORITY') or 'AUTHORITY_NAME_URL_OR_ID'
	MSAL_HTTP_SCHEME	= os.environ.get('MSAL_HTTP_SCHEME') or 'https'

	MSAL_AUTHORITY_CONF	= {
		"TENANT": MSAL_AUTHORITY,
		"CLIENT_ID": MSAL_CLIENT_ID,
		"CLIENT_SECRET": MSAL_CLIENT_SECRET,
		"HTTPS_SCHEME": MSAL_HTTP_SCHEME
	}