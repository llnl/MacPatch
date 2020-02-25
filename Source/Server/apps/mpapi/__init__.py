import os
import logging, logging.handlers
import json
import subprocess
from flask import Flask
from mpapi.config import DevelopmentConfig, ProductionConfig
from mpapi.extensions import db, migrate, cache
from datetime import datetime, date

if os.getenv("MPAPI_ENV") == 'prod':
	DefaultConfig = ProductionConfig
else:
	DefaultConfig = DevelopmentConfig

def create_app(config_object=DefaultConfig):

	app = Flask(__name__)

	# Add teardown_request to the app, here we ensure the db session is removed after the
	# request has been completed in any way.
	# db.session.remove will call rollback explicitly if needed
	@app.teardown_request
	def shutdown_session(exception):
		if not exception:
			db.session.commit()

		db.session.remove()

	@app.teardown_appcontext
	def teardown_appcontext(response_or_exc):
		db.session.remove()

	app.config.from_object(config_object)
	app.config.from_pyfile('../config.cfg', silent=True)
	app.config.from_pyfile('../conf_wsapi.cfg', silent=True)
	app.config['JSON_SORT_KEYS'] = False

	# Configure SQLALCHEMY_DATABASE_URI for MySQL
	_uri = "mysql+pymysql://%s:%s@%s:%s/%s" % (app.config['DB_USER'], app.config['DB_PASS'], app.config['DB_HOST'], app.config['DB_PORT'], app.config['DB_NAME'])
	app.config['SQLALCHEMY_DATABASE_URI'] = _uri

	# Configure logging location and log file name
	log_file = app.config['LOGGING_LOCATION'] + "/mpwsapi.log"
	if not os.path.exists(app.config['LOGGING_LOCATION']):
		os.makedirs(app.config['LOGGING_LOCATION'])
		subprocess.call(['chmod', '2775', app.config['LOGGING_LOCATION']])

	# This config option will convert all date objects to string
	app.config['RESTFUL_JSON'] = {'default': json_serial}

	# Set default log level
	_log_level = logging.INFO

	# If app is set to debug set logging to debug
	if app.config['DEBUG']:
		app.config['LOGGING_LEVEL'] = 'debug'

	if app.config['LOGGING_LEVEL'].lower() == 'info':
		_log_level = logging.INFO
	elif app.config['LOGGING_LEVEL'].lower() == 'debug':
		_log_level = logging.DEBUG
	elif app.config['LOGGING_LEVEL'].lower() == 'warning':
		_log_level = logging.WARNING
	elif app.config['LOGGING_LEVEL'].lower() == 'error':
		_log_level = logging.ERROR
	elif app.config['LOGGING_LEVEL'].lower() == 'critical':
		_log_level = logging.CRITICAL
	else:
		_log_level = logging.INFO

	# Set and Enable Logging
	handler = logging.handlers.TimedRotatingFileHandler(log_file, when='midnight', interval=1, backupCount=30)
	handler.setLevel(_log_level) # This is needed for log rotation
	# Set log file formatting
	formatter = logging.Formatter(app.config['LOGGING_FORMAT'])
	handler.setFormatter(formatter)
	# Add handler and set app log level
	app.logger.addHandler(handler)
	app.logger.setLevel(_log_level)

	read_siteconfig_server_data(app)
	register_extensions(app)
	register_blueprints(app)
	cache.init_app(app, config={'CACHE_TYPE': 'simple'})
	return app

def read_siteconfig_server_data(app):

	data = {}
	if os.path.exists(app.config['SITECONFIG_FILE'].strip()):
		try:
			with open(app.config['SITECONFIG_FILE'].strip()) as data_file:
				data = json.load(data_file)

		except OSError:
			print('Well darn.')
			return

	else:
		print(("Error, could not open file " + app.config['SITECONFIG_FILE'].strip()))
		return

	if "settings" in data:
		app.config['MP_SETTINGS'] = data['settings']
		return

def register_extensions(app):
	db.init_app(app)
	migrate.init_app(app, db)

def register_blueprints(app):

	if app.config['ALLOW_CONTENT_DOWNLOAD']:
		# If Debug, allow file download, else prod use NGINX
		# for file downloads
		from .main import main as bp_main
		app.register_blueprint(bp_main, url_prefix='/mp-content')

	from .agent import agent as bp_agent
	app.register_blueprint(bp_agent, url_prefix=app.config['URL_PREFIX'])

	from .agent_2 import agent_2 as bp_agent_2
	app.register_blueprint(bp_agent_2, url_prefix='/api/v2')

	from .antivirus import antivirus as bp_antivirus
	app.register_blueprint(bp_antivirus, url_prefix=app.config['URL_PREFIX'])

	from .auth import auth as bp_auth
	app.register_blueprint(bp_auth, url_prefix=app.config['URL_PREFIX'])

	from .autopkg import autopkg as bp_autopkg
	app.register_blueprint(bp_autopkg, url_prefix=app.config['URL_PREFIX'])

	from .checkin import checkin as bp_checkin
	app.register_blueprint(bp_checkin, url_prefix=app.config['URL_PREFIX'])

	from .checkin_2 import checkin_2 as bp_checkin_2
	app.register_blueprint(bp_checkin_2, url_prefix='/api/v2')
 
	from .checkin_3 import checkin_3 as bp_checkin_3
	app.register_blueprint(bp_checkin_3, url_prefix='/api/v3')

	from .inventory import inventory as bp_inventory
	app.register_blueprint(bp_inventory, url_prefix=app.config['URL_PREFIX'])

	from .inventory_2 import inventory_2 as bp_inventory_2
	app.register_blueprint(bp_inventory_2, url_prefix='/api/v2')

	from .inventory_3 import inventory_3 as bp_inventory_3
	app.register_blueprint(bp_inventory_3, url_prefix='/api/v3')

	from .mac_profiles import mac_profiles as bp_mac_profiles
	app.register_blueprint(bp_mac_profiles, url_prefix=app.config['URL_PREFIX'])

	from .mac_profiles_2 import mac_profiles_2 as bp_mac_profiles_2
	app.register_blueprint(bp_mac_profiles_2, url_prefix='/api/v2')

	from .patches import patches as bp_patches
	app.register_blueprint(bp_patches, url_prefix=app.config['URL_PREFIX'])

	from .patches_2 import patches_2 as bp_patches_2
	app.register_blueprint(bp_patches_2, url_prefix='/api/v2')

	from .patches_3 import patches_3 as bp_patches_3
	app.register_blueprint(bp_patches_3, url_prefix='/api/v3')

	from .patches_4 import patches_4 as bp_patches_4
	app.register_blueprint(bp_patches_4, url_prefix='/api/v4')

	from .provisioning import provisioning as bp_provisioning
	app.register_blueprint(bp_provisioning, url_prefix=app.config['URL_PREFIX'])

	from .register import register as bp_register
	app.register_blueprint(bp_register, url_prefix=app.config['URL_PREFIX'])

	from .register_2 import register_2 as bp_register_2
	app.register_blueprint(bp_register_2, url_prefix='/api/v2')

	from .servers import servers as bp_servers
	app.register_blueprint(bp_servers, url_prefix=app.config['URL_PREFIX'])

	from .servers_2 import servers_2 as bp_servers_2
	app.register_blueprint(bp_servers_2, url_prefix='/api/v2')

	from .software import software as bp_software
	app.register_blueprint(bp_software, url_prefix=app.config['URL_PREFIX'])

	from .software_2 import software_2 as bp_software_2
	app.register_blueprint(bp_software_2, url_prefix='/api/v2')

	from .software_3 import software_3 as bp_software_3
	app.register_blueprint(bp_software_3, url_prefix='/api/v3')

	from .software_4 import software_4 as bp_software_4
	app.register_blueprint(bp_software_4, url_prefix='/api/v4')

	from .srv_utils import srv as bp_srv_utils
	app.register_blueprint(bp_srv_utils, url_prefix=app.config['URL_PREFIX'])

	from .status import status as bp_status
	app.register_blueprint(bp_status, url_prefix=app.config['URL_PREFIX'])

	from .support import support as bp_support
	app.register_blueprint(bp_support, url_prefix=app.config['URL_PREFIX'])

def json_serial(obj):
	"""JSON serializer for objects not serializable by default json code"""

	if isinstance(obj, (date, datetime)):
		serial = obj.isoformat()
		return serial
