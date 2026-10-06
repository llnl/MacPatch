from flask import Blueprint
from flask_restful import Api

status_5 = Blueprint('status_5', __name__)
status_5_api = Api(status_5)

from . import routes
