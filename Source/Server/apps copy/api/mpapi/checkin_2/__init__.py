from flask import Blueprint
from flask_restful import Api

checkin_2 = Blueprint('checkin_2', __name__)
checkin_2_api = Api(checkin_2)

from . import routes