import os
from dotenv import load_dotenv
from datetime import timedelta

basedir = os.path.abspath(os.path.dirname(__file__))
appsdir = os.path.dirname(basedir)

dotFile=os.path.join(appsdir, '.mpconsole')
load_dotenv(dotFile, override=True)

MP_ROOT_DIR	= os.environ.get('MP_ROOT_DIR') or '/opt/MacPatch'
MP_SRV_DIR	= MP_ROOT_DIR+'/Server'

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
	SECRET_KEY          		= '~t\x86\xc9\x1ew\x8bOcX\x85O\xb6\xa2\x11kL\xd1\xce\x7f\x14<y\x9e'
	PERMANENT_SESSION_LIFETIME	= timedelta(minutes=10)

	# Logging
	LOGGING_FORMAT      = '%(asctime)s [%(name)s][%(levelname).3s] --- %(message)s'
	LOGGING_LEVEL       = os.environ.get('LOGGING_LEVEL') or 'info'
	LOGGING_LOCATION    = MP_SRV_DIR+'/apps/logs'
	LOG_FILE_NAME		= os.environ.get('LOG_FILE_NAME') or 'mpconsole.log'
	LOG_FILE 			= LOGGING_LOCATION + '/' + LOG_FILE_NAME

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
	ENABLE_INTUNE				= True
	INTUNE_RESOURCE				= "https://graph.microsoft.com"
	INTUNE_TENANT				= ""
	INTUNE_AUTHORITY_HOST_URL	= ""
	INTUNE_CLIENT_ID			= ""
	INTUNE_CLIENT_SECRET		= ""
	INTUNE_USER					= ""
	INTUNE_USER_PASS			= ""