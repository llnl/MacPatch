"""Shared response for missing or expired console sessions."""
from flask import jsonify, redirect, request, session, url_for
from flask_login import logout_user


def session_expired_response():
    logout_user()
    session.clear()
    # Expire Flask-Login's remember cookie as well as the console session.
    session['_remember'] = 'clear'
    login_url = url_for('main.index')
    if (request.headers.get('X-Requested-With') == 'XMLHttpRequest'
            or request.is_json
            or request.accept_mimetypes.best == 'application/json'):
        response = jsonify(error='session_expired',
                           errormsg='Your session has expired. Please log in again.',
                           login_url=login_url)
        response.status_code = 401
    else:
        response = redirect(login_url)
    response.headers['X-MacPatch-Login'] = login_url
    response.headers['Cache-Control'] = 'no-store'
    return response
