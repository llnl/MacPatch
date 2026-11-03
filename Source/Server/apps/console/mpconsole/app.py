# ----------------------------------------------------------
# MacPatch Admin Console
# - 4.4.0
# - Migrated to Bootstrap 4.6
#
# ----------------------------------------------------------
import os
import json
import sys
from flask import Flask, session, g, request, url_for, redirect, abort, flash, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, current_user
from flask_session import Session
from flask_caching import Cache
from flask_wtf.csrf import CSRFProtect, CSRFError
from pymysql import OperationalError as PyOperationalError
from sqlalchemy import func
from datetime import timedelta, datetime
from dateutil.parser import parse as dateParse

import logging
import logging.handlers
from flask.logging import default_handler
from mpconsole.config import Config
from mpconsole.extensions import migrate
from mpconsole.mplogger import *
from mpconsole.session_auth import session_expired_response

db = SQLAlchemy()
cache = Cache()
_session = Session()
csrf = CSRFProtect()

# Configure authentication
login_manager = LoginManager()
login_manager.session_protection = "strong"
login_manager.login_view = "auth.login"
login_manager.unauthorized_handler(session_expired_response)

def create_app(config_object=Config):
	app = Flask(__name__)
	
	# Read-in Config Data
	app.config.from_object(config_object)

	# Setup Logging
	setup_logging(app)
	
	# Define & init session for Redis
	_session.init_app(app)

	# Jinja Options
	app.jinja_env.trim_blocks = True
	app.jinja_env.lstrip_blocks = True

	# Configure SQLALCHEMY_DATABASE_URI for MySQL
	_uri = f"mysql+pymysql://{app.config['DB_USER']}:{app.config['DB_PASS']}@{app.config['DB_HOST']}:{app.config['DB_PORT']}/{app.config['DB_NAME']}"
	app.config['SQLALCHEMY_DATABASE_URI'] = _uri

	@app.before_request
	def before_request():
		if request.endpoint not in ('static', 'auth.logout', 'local_auth.logout'):
			_last_activity = session.get('last_activity')
			if isinstance(_last_activity, str):
				# Session filesystem will store the date as dateObj
				# Redis uses a str for the date
				_last_activity = dateParse(_last_activity)

			if _last_activity is not None:
				if (datetime.now(tz=_last_activity.tzinfo) - _last_activity) > timedelta(minutes=app.config['SESSION_TIMEOUT_MINUTES']):
					log_Debug(f"[before_request][{request.endpoint}]: _last_activity is greater than the session timeout.")
					return session_expired_response()
				
			session['last_activity'] = datetime.now()
			g.user = current_user

		# Every endpoint requires a logged in session, except the public ones. Routes also
		# use @login_required, this catches a route that is missing it.
		# request.endpoint is None for 404/405, let those through to the error handlers.
		if request.endpoint is None or request.endpoint in publicEndpoints(app):
			return

		if app.config['LOCAL_AUTH_ALLOWED']:
			hasSession = session.get('user') is not None or session.get('oid_user') is not None
		else:
			hasSession = session.get('oid_user') is not None

		if not hasSession:
			log_Debug(f"[before_request][{request.endpoint}]: No user session.")
			return session_expired_response()

	@app.errorhandler(CSRFError)
	def csrf_error(e):
		# Missing or invalid CSRF token, usually a stale page after the session expired
		log_Error(f"[csrf_error][{request.endpoint}]: {e.description}")
		if request.headers.get('X-Requested-With') == 'XMLHttpRequest' or request.accept_mimetypes.best == 'application/json':
			return jsonify(error='csrf_failed', errormsg='Your request could not be verified. Please reload the page and try again.'), 400

		flash('Your request could not be verified. Please try again.')
		return redirect(request.referrer or url_for('main.index'))

	@app.teardown_request
	def shutdown_session(exception):
		db.session.rollback()
		db.session.remove()

	@app.context_processor
	def baseData():
		enableIntune = 0
		if app.config['ENABLE_INTUNE']:
			enableIntune = 1

		patchGroupCount, clientCount = baseCounts()
		return dict(patchGroupCount=patchGroupCount, clientCount=clientCount, intune=enableIntune)

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
			except (OSError, ValueError) as e:
				app.logger.error(f"Unable to read MDM schema file {mdm_schema_file.strip()}: {e}")

	initialize_extensions(app)
	register_blueprints(app)
	from mpconsole.model import ChangeLog
	from mpconsole.change_log import install_change_log
	with app.app_context():
		install_change_log(db.engine, ChangeLog.__table__)

	@app.cli.command('init-change-log')
	def init_change_log():
		"""Create only the additive change_log table on an existing installation."""
		ChangeLog.__table__.create(db.engine, checkfirst=True)
		print('change_log table is ready.')

	# Setup commands (populate-db, add-admin, ...) used by ServerSetup.py
	from mpconsole.cli import register_cli
	register_cli(app)

	return app

def publicEndpoints(app):
	# Endpoints that do not require a logged in session
	endpoints = {'static', 'main.index', 'agent.clientDownload', 'content.content',
				 'auth.login', 'auth.signin_oidc', 'auth.logout', 'auth.logout_complete', 'auth.ping',
				 'local_auth.logout'}
	if app.config['LOCAL_AUTH_ALLOWED']:
		endpoints.add('local_auth.login')
	return endpoints

def initialize_extensions(app):
	db.init_app(app)
	login_manager.init_app(app)
	migrate.init_app(app, db)
	csrf.init_app(app)
	cache.init_app(app)

def register_blueprints(app):
	from .errors import errors as errors_blueprint
	app.register_blueprint(errors_blueprint)

	from .main import main as main_blueprint
	app.register_blueprint(main_blueprint, url_prefix='/')

	if app.config['ALLOW_CONTENT_DOWNLOAD']:
		from .content import content as content_blueprint
		app.register_blueprint(content_blueprint, url_prefix='/mp-content')

	# Local Auth
	from .local_auth import local_auth as local_auth_blueprint
	app.register_blueprint(local_auth_blueprint, url_prefix='/local')

	import mpconsole.auth as auth
	app.register_blueprint(auth.construct_blueprint(app.config['MSAL_AUTHORITY_CONF']), url_prefix='/auth')

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

	# Need to update mptasks, still uses adal
	#from .mdm import mdm as mdm_blueprint
	#app.register_blueprint(mdm_blueprint, url_prefix='/mdm')

	return app

class OwnedWatchedFileHandler(logging.handlers.WatchedFileHandler):
	'''
	WatchedFileHandler re-opens the log file once it has been rotated (renamed) by
	logrotate (Linux) or newsyslog (macOS), it is safe to use from every gunicorn worker.
	The log is not rotated in-process, every worker process would rotate the same file.

	When running as root (gunicorn master with preload_app), a file it creates is given
	to the owner of the log directory, so the workers can still open it after a rotation.
	'''
	def _open(self):
		stream = super()._open()
		if os.geteuid() == 0:
			try:
				_dir = os.stat(os.path.dirname(self.baseFilename))
				os.chown(self.baseFilename, _dir.st_uid, _dir.st_gid)
			except OSError:
				pass
		return stream

def setup_logging(app):
	_level = getattr(logging, app.config['LOGGING_LEVEL'].upper(), logging.INFO)
	app.logger.setLevel(_level if isinstance(_level, int) else logging.INFO)

	# Flask adds a stderr handler by default, under gunicorn that duplicates every
	# line into stderr (journald / launchd stderr file, which is not rotated)
	app.logger.removeHandler(default_handler)

	# create_app can be called more than once in a process, do not add duplicate handlers
	for _handler in [h for h in app.logger.handlers if getattr(h, '_macpatch', False)]:
		app.logger.removeHandler(_handler)
		_handler.close()

	formatter = logging.Formatter(app.config['LOGGING_FORMAT'])
	handlers = [OwnedWatchedFileHandler(app.config['LOG_FILE'])]
	if app.debug:
		handlers.append(logging.StreamHandler(sys.stdout))

	for _handler in handlers:
		_handler._macpatch = True
		_handler.setFormatter(formatter)
		app.logger.addHandler(_handler)

'''
----------------------------------------------------------------
Global
----------------------------------------------------------------
'''
def read_siteconfig_server_data(app):
	# siteconfig.json is read once at startup, mputil.return_data_for_root_key reads
	# from MP_SETTINGS. Restart the console after changing siteconfig.json.
	app.config['MP_SETTINGS'] = {}
	_file = app.config['SITECONFIG_FILE'].strip()
	try:
		with open(_file) as data_file:
			data = json.load(data_file)
	except (OSError, ValueError) as e:
		app.logger.error(f"Unable to read site config file {_file}: {e}")
		return

	app.config['MP_SETTINGS'] = data.get('settings', {})

@cache.cached(timeout=60, key_prefix='mp_base_counts')
def baseCounts():
	# Patch group & client counts shown on every page, cached so each page render
	# does not query the database
	from .model import MpPatchGroup, MpClient
	patchGroups = db.session.query(func.count()).select_from(MpPatchGroup).scalar()
	clients = db.session.query(func.count()).select_from(MpClient).scalar()
	return patchGroups, clients
