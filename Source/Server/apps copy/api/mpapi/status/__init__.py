from flask import Blueprint
from flask_restful import Api

status = Blueprint('status', __name__)
status_api = Api(status)

from . import routes