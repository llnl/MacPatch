from flask import Blueprint
from flask_restful import Api

checkin_5 = Blueprint('checkin_5', __name__)
checkin_5_api = Api(checkin_5)

from . import routes
