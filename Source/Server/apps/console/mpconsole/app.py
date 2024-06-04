import os
import json
import sys
from flask import Flask, session, g
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, current_user
from flask_caching import Cache
from flask_cors import CORS
from pymysql import OperationalError as PyOperationalError
from datetime import timedelta

import logging
import logging.handlers
from mpconsole.config import Config
from mpconsole.extensions import db, migrate
from mpconsole.mplogger import *

db = SQLAlchemy()
cors = CORS()
cache = Cache()

# Configure authentication
login_manager = LoginManager()
login_manager.session_protection = "strong"
login_manager.login_view = "auth.login"

def create_app(config_object=Config):
	app = Flask(__name__)
	
	# Read-in Config Data
	app.config.from_object(config_object)

	# Jinja Options
	app.jinja_env.trim_blocks = True
	app.jinja_env.lstrip_blocks = True

	# Configure SQLALCHEMY_DATABASE_URI for MySQL
	_uri = f"mysql+pymysql://{app.config['DB_USER']}:{app.config['DB_PASS']}@{app.config['DB_HOST']}:{app.config['DB_PORT']}/{app.config['DB_NAME']}"
	app.config['SQLALCHEMY_DATABASE_URI'] = _uri

	@app.before_request
	def before_request():
		session.permanent = True
		app.permanent_session_lifetime = timedelta(minutes=15)
		session.modified = True
		g.user = current_user

	@app.teardown_request
	def shutdown_session(exception):
		db.session.rollback()
		db.session.remove()

	@app.context_processor
	def baseData():
		enableIntune = 0
		if app.config['ENABLE_INTUNE']:
			enableIntune = 1

		return dict(patchGroupCount=patchGroupCount(), clientCount=clientCount(), intune=enableIntune)

	read_siteconfig_server_data(app)

	# MDM Schema Setup
	if app.config['ENABLE_INTUNE']:
		# Read Schema File and Store In App Var
		mdm_schema_file = app.config['STATIC_JSON_DIR']+"/mdm_schema.json"
		if os.path.exists(mdm_schema_file.strip()):
			schema_data = {}
			try:
				with open(mdm_schema_file.strip()) as data_file:
					schema_data = json.load(data_file)

				app.config["MDM_SCHEMA"] = schema_data
			except OSError:
				print('Well darn.')
				return

	initialize_extensions(app)
	register_blueprints(app)

	return app

def initialize_extensions(app):
	db.init_app(app)
	login_manager.init_app(app)
	migrate.init_app(app, db)

	setup_logging(app)

def register_blueprints(app):
	from .errors import errors as errors_blueprint
	app.register_blueprint(errors_blueprint)

	from .main import main as main_blueprint
	app.register_blueprint(main_blueprint, url_prefix='/')

	if app.config['ALLOW_CONTENT_DOWNLOAD']:
		from .content import content as content_blueprint
		app.register_blueprint(content_blueprint, url_prefix='/mp-content')

	from .auth import auth as auth_blueprint
	app.register_blueprint(auth_blueprint, url_prefix='/auth')

	from .agent import agent as agent_blueprint
	app.register_blueprint(agent_blueprint, url_prefix='/agent')

	from .dashboard import dashboard as dashboard_blueprint
	app.register_blueprint(dashboard_blueprint, url_prefix='/dashboard')

	from .clients import clients as clients_blueprint
	app.register_blueprint(clients_blueprint, url_prefix='/clients')

	from .patches import patches as patches_blueprint
	app.register_blueprint(patches_blueprint, url_prefix='/patches')

	from .registration import registration as registration_blueprint
	app.register_blueprint(registration_blueprint, url_prefix='/registration')

	from .reports import reports as reports_blueprint
	app.register_blueprint(reports_blueprint, url_prefix='/reports')

	from .software import software as software_blueprint
	app.register_blueprint(software_blueprint, url_prefix='/software')

	from .osmanage import osmanage as osmanage_blueprint
	app.register_blueprint(osmanage_blueprint, url_prefix='/osmanage')

	from .provision import provision as provision_blueprint
	app.register_blueprint(provision_blueprint, url_prefix='/provision')

	from .console import console as console_blueprint
	app.register_blueprint(console_blueprint, url_prefix='/console')

	from .test import test as test_blueprint
	app.register_blueprint(test_blueprint, url_prefix='/test')

	from .maint import maint as maint_blueprint
	app.register_blueprint(maint_blueprint, url_prefix='/maint')

	from .mdm import mdm as mdm_blueprint
	app.register_blueprint(mdm_blueprint, url_prefix='/mdm')

	return app

def setup_logging(app):
	# Configure logging
	handler = logging.handlers.TimedRotatingFileHandler(app.config['LOG_FILE'], when='midnight', interval=1, backupCount=30)

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

'''
----------------------------------------------------------------
Global
----------------------------------------------------------------
'''
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
		print("Error, could not open file " + app.config['SITECONFIG_FILE'].strip())
		return

	if "settings" in data:
		app.config['MP_SETTINGS'] = data['settings']
		return

def patchGroupCount():
	from .model import MpPatchGroup
	qGet = MpPatchGroup.query.all()
	count = len(qGet)
	return count

def clientCount():
	from .model import MpClient
	qGet = MpClient.query.with_entities(MpClient.cuuid).all()
	count = len(qGet)
	return count
