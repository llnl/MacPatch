from flask import request, current_app, send_from_directory
from flask_restful import reqparse

from . import *
from .. mputil import *

parser = reqparse.RequestParser()

# Clientin Info/Status
class mainIndex(MPResource):

    def __init__(self):
        self.reqparse = reqparse.RequestParser()
        super(mainIndex, self).__init__()

    def get(self, file):
        print current_app.config['WEB_CONTENT_DIR'] + "/" + file
        return send_from_directory(current_app.config['WEB_CONTENT_DIR'], file, as_attachment=True)


main_api.add_resource(mainIndex,     '/<path:file>')