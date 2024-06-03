import os
import logging, logging.handlers
import json
import subprocess
import sys

from flask import Flask, request, abort
from datetime import datetime, date
from distutils.version import LooseVersion

from mpapi.config import Config
from mpapi.extensions import db, migrate, cache

def create_app(config_object=Config):

	app = Flask(__name__)
	
	# Read-in Config Data
	app.config.from_object(config_object)

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
	app.config['JSON_SORT_KEYS'] = False

	# Configure SQLALCHEMY_DATABASE_URI for MySQL
	_uriBase = f"mysql+pymysql://{app.config['DB_USER']}:{app.config['DB_PASS']}@{app.config['DB_HOST']}:{app.config['DB_PORT']}"
	_uriFull = f"{_uriBase}/{app.config['DB_NAME']}"
	app.config['SQLALCHEMY_DATABASE_URI'] = _uriFull
	app.config['DB_URI_STRING'] = _uriBase

	# This config option will convert all date objects to string
	app.config['RESTFUL_JSON'] = {'default': json_serial}

	read_siteconfig_server_data(app)
	register_extensions(app)
	register_blueprints(app)

	@app.before_request
	def only_supported_agents():
		req = request.environ
		pathInfo = req['PATH_INFO']
		for allowPath in app.config['BEFORE_REQUEST']:
			if allowPath in pathInfo:
				app.logger.info("Bypass before_request for " + pathInfo)
				break
			else:
				_req_agent_ver = '0'
				if 'HTTP_X_AGENT_VER' in req:
					_req_agent_ver = req['HTTP_X_AGENT_VER']

				# Agent Ver is Less than Min Agent Ver
				if app.config['VERIFY_MIN_AGENT_VER']:
					if LooseVersion(_req_agent_ver) < LooseVersion(app.config['MIN_AGENT_VER']):
						abort(409)
						#return {'errorno': 409, 'errormsg': 'Agent Version not accepted.', 'result': {}}, 409
					else:
						break

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
	cache.init_app(app, config={'CACHE_TYPE': 'simple'})

	setup_logging(app)

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

	from .agent_3 import agent_3 as bp_agent_3
	app.register_blueprint(bp_agent_3, url_prefix='/api/v3')

	from .auth import auth as bp_auth
	app.register_blueprint(bp_auth, url_prefix=app.config['URL_PREFIX'])

	from .autopkg import autopkg as bp_autopkg
	app.register_blueprint(bp_autopkg, url_prefix=app.config['URL_PREFIX'])

	from .aws import aws as bp_aws
	app.register_blueprint(bp_aws, url_prefix=app.config['URL_PREFIX'])

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

def setup_logging(app):
	# Configure logging
	handler = logging.handlers.RotatingFileHandler(app.config['LOG_FILE'], maxBytes=10485760, backupCount=30)

	if app.config['LOGGING_LEVEL'].lower() == 'info':
		app.logger.setLevel(logging.INFO)
	elif app.config['LOGGING_LEVEL'].lower() == 'debug':
		app.logger.setLevel(logging.DEBUG)
	elif app.config['LOGGING_LEVEL'].lower() == 'warning':
		app.logger.setLevel(logging.WARNING)
	elif app.config['LOGGING_LEVEL'].lower() == 'error':
		app.logger.setLevel(logging.ERROR)
	elif app.config['LOGGING_LEVEL'].lower() == 'critical':
		app.logger.setLevel(logging.CRITICAL)
	else:
		app.logger.setLevel(logging.INFO)

	app.logger.setLevel(logging.DEBUG)
	handler = logging.StreamHandler(sys.stdout)
	formatter = logging.Formatter(app.config['LOGGING_FORMAT'])
	handler.setFormatter(formatter)
	app.logger.addHandler(handler)

def json_serial(obj):
	"""JSON serializer for objects not serializable by default json code"""

	if isinstance(obj, (date, datetime)):
		serial = obj.isoformat()
		return serial
