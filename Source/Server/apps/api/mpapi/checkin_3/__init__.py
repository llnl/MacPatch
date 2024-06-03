from flask import Blueprint
from flask_restful import Api

checkin_3 = Blueprint('checkin_3', __name__)
checkin_3_api = Api(checkin_3)

from . import routes