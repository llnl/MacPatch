from flask import request, current_app, send_from_directory, session, render_template
from flask_security import login_required

from .  import content
from .  import *
from .. mputil import *

@content.route('/<path:file>')
def content(file):
	return send_from_directory(current_app.config['CONTENT_DIR'] + "/Web/", file, as_attachment=True)
