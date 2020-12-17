import os
import logging
basedir = os.path.abspath(os.path.dirname(__file__))

MP_ROOT_DIR = '/opt/MacPatch'
MP_SRV_DIR = MP_ROOT_DIR+'/Server'

class BaseConfig:

	DEBUG   						= False
	TESTING 						= False
	BASEDIR 						= basedir
	MAX_CONTENT_LENGTH              = 9000 * 1024 * 1024    # 9000 Mb limit
	# DEBUG_TB_ENABLED = True
	# SQLALCHEMY_RECORD_QUERIES = False

	# Web Server Options
	# Use 127.0.0.1 and port 3601, NGINX will be the outward facing
	# avenue for clients to communicate.
	SRV_HOST                        = '127.0.0.1'
	SRV_PORT                        = 3602

	CORS_HEADERS 					= 'Content-Type'

	# Database Options
	DB_USER                         = 'mpdbadm'
	DB_PASS                         = 'password'
	DB_HOST                         = 'localhost'
	DB_PORT                         = '3306'
	DB_NAME                         = 'MacPatchDB'
	SQLALCHEMY_DATABASE_URI         = 'mysql+pymysql://'
	SQLALCHEMY_TRACK_MODIFICATIONS  = False
	SQLALCHEMY_ENGINE_OPTIONS = { 'pool_size' : 50,
                                  'pool_recycle': 120,
                                  'pool_timeout': 20,
                                  'pool_pre_ping': True }

	# App Options
	SECRET_KEY          = '~t\x86\xc9\x1ew\x8bOcX\x85O\xb6\xa2\x11kL\xd1\xce\x7f\x14<y\x9e'
	LOGGING_FORMAT      = '%(asctime)s [%(name)s][%(levelname).3s] --- %(message)s'
	LOGGING_LEVEL       = 'info'
	LOGGING_LOCATION    = MP_SRV_DIR+'/apps/logs'

	# MacPatch App Options
	SITECONFIG_FILE     = MP_SRV_DIR+'/etc/siteconfig.json'
	CONTENT_DIR         = MP_ROOT_DIR+'/Content'
	AGENT_CONTENT_DIR   = MP_ROOT_DIR+'/Content/Web/clients'
	PATCH_CONTENT_DIR   = MP_ROOT_DIR+'/Content/Web/patches'
	SW_CONTENT_DIR      = MP_ROOT_DIR+'/Content/Web/sw'

	STATIC_DIR 					= basedir + '/static'
	STATIC_JSON_DIR 			= STATIC_DIR + '/json'

	JOBS_FILE 					= STATIC_JSON_DIR+'/jobs.json'
	JOBS 						= []

	SCHEDULER_API_ENABLED 		= True
	ALLOW_CONTENT_DOWNLOAD 		= False
	REDIRECT_TO_NEW_API 		= True

	# AWS - MP
	USE_AWS_S3					= False
	AWS_S3_KEY					= None
	AWS_S3_SECRET				= None
	AWS_S3_BUCKET				= None
	AWS_S3_REGION				= None

	# InTune - MDM
	ENABLE_INTUNE				= True
	INTUNE_RESOURCE				= "https://graph.microsoft.com"
	INTUNE_TENANT				= ""
	INTUNE_AUTHORITY_HOST_URL	= ""
	INTUNE_CLIENT_ID			= ""
	INTUNE_CLIENT_SECRET		= ""
	INTUNE_USER					= ""
	INTUNE_USER_PASS			= ""

class DevelopmentConfig(BaseConfig):

	DEBUG                           = True
	LOGGING_LEVEL                   = 'debug'
	DEBUG_TB_INTERCEPT_REDIRECTS    = False
	SQLALCHEMY_TRACK_MODIFICATIONS  = False
	ALLOW_CONTENT_DOWNLOAD 			= True

class ProductionConfig(BaseConfig):

	DEBUG                           = False
	LOGGING_LEVEL                   = 'info'

config = {
	"development": "mpapi.config.DevelopmentConfig",
	"prduction": "mpapi.config.ProductionConfig"
}
