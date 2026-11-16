from flask import Blueprint
from flask_restful import Api

register_5 = Blueprint('register_5', __name__)
register_5_api = Api(register_5)

from . import routes
