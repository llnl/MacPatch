from flask import Blueprint
from flask_restful import Api

antivirus_2 = Blueprint('antivirus_2', __name__)
antivirus_2_api = Api(antivirus_2)

from . import routes