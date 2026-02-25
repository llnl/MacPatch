from flask import Blueprint
from flask_restful import Api

register_2 = Blueprint('register_2', __name__)
register_2_api = Api(register_2)

from . import routes