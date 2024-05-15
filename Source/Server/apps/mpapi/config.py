import os
from dotenv import load_dotenv
from datetime import timedelta

basedir = os.path.abspath(os.path.dirname(__file__))
appsdir = os.path.dirname(basedir)

dotFileGlobal=os.path.join(appsdir, '.mpglobal')
dotFileConsole=os.path.join(appsdir, '.mpapi')
load_dotenv(dotFileGlobal, override=True)
load_dotenv(dotFileConsole, override=True)


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

	DEBUG               			= False
	TESTING             			= False

	# Web Server Options
	# Use 127.0.0.1 and port 3601, NGINX will be the outward facing
	# avenue for clients to communicate.
	SRV_HOST            			= '127.0.0.1'
	SRV_PORT            			= 3601
	JSON_SORT_KEYS					= False

	# URL Options
	API_PREFIX          			= 'api'
	API_VERSION         			= 'v1'
	URL_PREFIX          			= '/' + API_PREFIX + '/' + API_VERSION

	# Database Options
	DB_USER                         = os.environ.get('DB_USER') or 'mpdbadm'
	DB_PASS                         = os.environ.get('DB_PASS') or 'password'
	DB_HOST                         = os.environ.get('DB_HOST') or 'localhost'
	DB_PORT                         = int(os.environ.get('DB_PORT') or '3306')
	DB_NAME                         = os.environ.get('DB_NAME') or 'MacPatchDB'
	DB_CONNECTOR					= 'mysql+pymysql'
	DB_URI_STRING					= ''
	SQLALCHEMY_DATABASE_URI         = DB_CONNECTOR+'://'
	SQLALCHEMY_TRACK_MODIFICATIONS  = False
	SQLALCHEMY_ENGINE_OPTIONS = {  'pool_size' : 200,
								   'pool_recycle':120,
								   'pool_timeout':15,
								   'pool_pre_ping': True }

	# App Options
	SECRET_KEY			= '~t\x86\xc9\x1ew\x8bOcX\x85O\xb6\xa2\x11kL\xd1\xce\x7f\x14<y\x9e'

	# Before Request
	BEFORE_REQUEST		= ['/v1/auth/', '/v1/token/', '/agent/config/', '/agent/update/', '/agent/upload/']

	# Logging
	LOGGING_FORMAT      = '%(asctime)s [%(name)s][%(levelname).3s] --- %(message)s'
	LOGGING_LEVEL       = os.environ.get('LOGGING_LEVEL') or 'info'
	LOGGING_LOCATION    = MP_SRV_DIR+'/apps/logs'
	LOG_FILE_NAME		= os.environ.get('LOG_FILE_NAME') or 'mpapi.log'
	LOG_FILE 			= LOGGING_LOCATION + '/' + LOG_FILE_NAME

	# MacPatch App Options
	SITECONFIG_FILE         	= '/opt/MacPatch/Server/etc/siteconfig.json'
	VERIFY_CLIENTID         	= as_bool(os.environ.get('VERIFY_CLIENTID') or 'no')
	CLIENTID_ZERO 				= as_bool(os.environ.get('CLIENTID_ZERO') or 'yes')
	REQUIRE_SIGNATURES      	= as_bool(os.environ.get('REQUIRE_SIGNATURES') or 'no')
	ALLOW_MIXED_SIGNATURES  	= as_bool(os.environ.get('ALLOW_MIXED_SIGNATURES') or 'yes')
	POST_CHECKIN_TO_SYSLOG  	= as_bool(os.environ.get('POST_CHECKIN_TO_SYSLOG') or 'no')
	REDIRECT_TO_NEW_API			= as_bool(os.environ.get('REDIRECT_TO_NEW_API') or 'yes')
	VERIFY_MIN_AGENT_VER		= as_bool(os.environ.get('VERIFY_MIN_AGENT_VER') or 'no')
	MIN_AGENT_VER 				= int(os.environ.get('MIN_AGENT_VER') or '0')

	# Content
	CONTENT_DIR             	= MP_ROOT_DIR+'/Content'
	WEB_CONTENT_DIR 	    	= MP_ROOT_DIR+'Content/Web'
	AGENT_CONTENT_DIR       	= MP_ROOT_DIR+'Content/Web/clients'
	PATCH_CONTENT_DIR       	= MP_ROOT_DIR+'/Content/Web/patches'

	ALLOW_CONTENT_DOWNLOAD		= as_bool(os.environ.get('ALLOW_CONTENT_DOWNLOAD') or 'no')

	# Inventory
	# Process types: DB, File, Hybrid
	INVENTORY_PROCESS			= os.environ.get('INVENTORY_PROCESS') or 'Hybrid' 
	INVENTORY_HYBRID_ROWS_LIMIT	= int(os.environ.get('INVENTORY_HYBRID_ROWS_LIMIT') or '10')

	# AWS
	USE_AWS_S3					= as_bool(os.environ.get('USE_AWS_S3') or 'no')
	AWS_S3_KEY					= os.environ.get('AWS_S3_KEY') or 'AWS_S3_KEY_STRING'
	AWS_S3_SECRET				= os.environ.get('AWS_S3_SECRET') or 'AWS_S3_SECRET_STRING'
	AWS_S3_BUCKET				= os.environ.get('AWS_S3_BUCKET') or 'AWS_S3_SECRET_STRING'
	AWS_S3_REGION				= as_none(os.environ.get('AWS_S3_REGION') or 'none')

	# InTune - MDM
	ENABLE_INTUNE				= as_bool(os.environ.get('ENABLE_INTUNE') or 'no')
	INTUNE_RESOURCE				= os.environ.get('INTUNE_RESOURCE') or 'https://graph.microsoft.com'
	INTUNE_TENANT				= os.environ.get('INTUNE_TENANT') or ''
	INTUNE_AUTHORITY_HOST_URL	= os.environ.get('INTUNE_AUTHORITY_HOST_URL') or ''
	INTUNE_CLIENT_ID			= os.environ.get('INTUNE_CLIENT_ID') or ''
	INTUNE_CLIENT_SECRET		= os.environ.get('INTUNE_CLIENT_SECRET') or ''
	INTUNE_USER					= os.environ.get('INTUNE_USER') or ''
	INTUNE_USER_PASS			= os.environ.get('INTUNE_USER_PASS') or ''

	# Email
	USE_EMAIL					= as_bool(os.environ.get('USE_EMAIL') or 'no')
	MAIL_SERVER					= os.environ.get('MAIL_SERVER') or 'smtp.example.com'
	MAIL_PORT					= 465
	MAIL_USERNAME 				= os.environ.get('MAIL_USERNAME') or 'yourId@example.com'
	MAIL_PASSWORD 				= os.environ.get('MAIL_PASSWORD') or '*****'
	MAIL_USE_TLS				= as_bool(os.environ.get('MAIL_USE_TLS') or 'no')
	MAIL_USE_SSL	 			= as_bool(os.environ.get('MAIL_USE_SSL') or 'yes')


