from flask import Blueprint
from flask_restful import Api

srv = Blueprint('srv_utils', __name__)
srv_api = Api(srv)

from . import routes