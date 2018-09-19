import os
basedir = os.path.abspath(os.path.dirname(__file__))


class BaseConfig:

	DEBUG               = False
	TESTING             = False

	# Web Server Options
	# Use 127.0.0.1 and port 3601, NGINX will be the outward facing
	# avenue for clients to communicate.
	SRV_HOST            = '127.0.0.1'
	SRV_PORT            = 3601

	# URL Options
	API_PREFIX          = 'api'
	API_VERSION         = 'v1'
	URL_PREFIX          = '/' + API_PREFIX + '/' + API_VERSION

	# Database Options
	DB_USER                         = 'mpdbadm'
	DB_PASS                         = 'password'
	DB_HOST                         = 'localhost'
	DB_PORT                         = '3306'
	DB_NAME                         = 'MacPatchDB3'
	SQLALCHEMY_DATABASE_URI         = 'mysql+pymysql://'
	SQLALCHEMY_TRACK_MODIFICATIONS  = False
	SQLALCHEMY_POOL_SIZE            = 50
	SQLALCHEMY_POOL_TIMEOUT         = 20
	SQLALCHEMY_POOL_RECYCLE         = 170

	# App Options
	SECRET_KEY              = '~t\x86\xc9\x1ew\x8bOcX\x85O\xb6\xa2\x11kL\xd1\xce\x7f\x14<y\x9e'
	LOGGING_FORMAT          = '%(asctime)s [%(name)s][%(levelname).3s] --- %(message)s'
	LOGGING_LEVEL           = 'info'
	LOGGING_LOCATION        = '/opt/MacPatch/Server/apps/logs'

	# MacPatch App Options
	SITECONFIG_FILE         = '/opt/MacPatch/Server/etc/siteconfig.json'
	VERIFY_CLIENTID         = True
	VERIFY_CLIENTID_OLD     = True
	REQUIRE_SIGNATURES      = False
	ALLOW_MIXED_SIGNATURES  = True
	POST_CHECKIN_TO_SYSLOG  = False

	CONTENT_DIR             = '/opt/MacPatch/Content'
	WEB_CONTENT_DIR 	    = '/opt/MacPatch/Content/Web'
	AGENT_CONTENT_DIR       = '/opt/MacPatch/Content/Web/clients'
	PATCH_CONTENT_DIR       = '/opt/MacPatch/Content/Web/patches'

	ALLOW_CONTENT_DOWNLOAD	= False


class DevelopmentConfig(BaseConfig):

	DEBUG               = True


class ProductionConfig(BaseConfig):

	DEBUG               = False


config = {
	"development": "mpapi.config.DevelopmentConfig",
	"prduction": "mpapi.config.ProductionConfig"
}
