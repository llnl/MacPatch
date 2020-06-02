from flask import render_template, redirect, url_for
from flask_login import login_required, current_user, login_user
from sqlalchemy.exc import SQLAlchemyError, OperationalError

from .  import main
from .. import login_manager
from .. model import *

@login_manager.user_loader
def load_user(userid):
	if userid != 'None':
		try:
			admUsr = AdmUsers.query.get(int(userid))
			return admUsr
		except SQLAlchemyError:
			return AdmUsers()

@login_manager.unauthorized_handler
def unauthorized():
	"""Redirect unauthorized users to Login page."""
	return render_template('login.html'), 200

@main.route('/')
@login_required
def index():
	return redirect(url_for('dashboard.index'))