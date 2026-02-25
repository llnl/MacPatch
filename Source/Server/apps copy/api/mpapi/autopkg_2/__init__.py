from flask import Blueprint
from flask_restful import Api

autopkg_2 = Blueprint('autopkg_2', __name__)
autopkg_2_api = Api(autopkg_2)

from . import routes