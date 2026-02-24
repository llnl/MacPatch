from flask import Blueprint
from flask_restful import Api

mac_profiles = Blueprint('mac_profiles', __name__)
mac_profiles_api = Api(mac_profiles)

from . import routes