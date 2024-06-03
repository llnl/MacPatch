from flask import current_app, send_from_directory

from . import content
from . import *
from mpconsole.mputil import *

@content.route('/<path:file>')
def content(file):
	return send_from_directory(current_app.config['CONTENT_DIR'] + "/Web/", file, as_attachment=True)
