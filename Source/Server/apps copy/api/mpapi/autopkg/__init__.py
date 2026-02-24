from flask import Blueprint
from flask_restful import Api

autopkg = Blueprint('autopkg', __name__)
autopkg_api = Api(autopkg)

from . import routes