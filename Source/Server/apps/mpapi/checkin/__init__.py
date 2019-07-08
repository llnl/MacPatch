from flask import Blueprint
from flask_restful import Api

checkin = Blueprint('checkin', __name__)
checkin_api = Api(checkin)

from . import routes