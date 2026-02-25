from flask import Blueprint
from flask_restful import Api

mac_profiles_2 = Blueprint('mac_profiles_2', __name__)
mac_profiles_2_api = Api(mac_profiles_2)

from . import routes