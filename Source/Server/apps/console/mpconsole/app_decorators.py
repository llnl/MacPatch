import flask
from datetime import datetime, timedelta
from functools import wraps

from mpconsole.config import Config
from mpconsole.session_auth import session_expired_response

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
		if conf.LOCAL_AUTH_ALLOWED:
			if not flask.session.get("user"):
				return session_expired_response()
		else:    
			if not flask.session.get("oid_user"):
				return session_expired_response()
		
		return f(*args, **kwargs)
	return decorated_function
