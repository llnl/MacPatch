from flask import Blueprint
from flask_restful import Api

auth = Blueprint('auth', __name__)
auth_api = Api(auth)

from . import routes