import flask
from datetime import datetime, timedelta
from functools import wraps

from mpconsole.config import Config

def login_required(f):
	"""
	Decorator for flask endpoints, ensuring that the user is authenticated and redirecting to log-in page if not.
	Example:
	```
		from flask import current_app as app
		@login_required
		@app.route("/")
		def index():
			return 'route protected'
	```
	"""
	conf = Config()

	@wraps(f)
	def decorated_function(*args, **kwargs):
		#if not config.REQUIRE_AUTHENTICATION:
			# Disable authentication, for use in dev/test only!
			#if config.HTTPS_SCHEME == 'https':
			#    raise ValueError('Not supported: Cant turn off authentication for https endpoints')

		#    current_app.logger.error('Authentication is disabled! For dev/test only!')
		#    flask.session['user'] = {'name': 'auth disabled'}
		#    return f(*args, **kwargs)
		#if flask.current_app.config['LOCAL_AUTH_ALLOWED']:
		if conf.LOCAL_AUTH_ALLOWED:
			if not flask.session.get("user"):
				flask.session.clear()
				return flask.redirect(flask.url_for('main.index'))
		else:    
			if not flask.session.get("oid_user"):
				flask.session.clear()
				return flask.redirect(flask.url_for('main.index'))
		
		return f(*args, **kwargs)
	return decorated_function