from flask import Blueprint
from flask_restful import Api

register = Blueprint('register', __name__)
register_api = Api(register)

from . import routes