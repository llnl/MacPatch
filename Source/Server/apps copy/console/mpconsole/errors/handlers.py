from flask import render_template
from mpconsole.app import db
from . import errors


@errors.app_errorhandler(404)
def not_found_error(error):
    return render_template('errors/404_new.html'), 404


@errors.app_errorhandler(500)
def internal_error(error):
    db.session.rollback()
    return render_template('errors/404_new.html'), 500