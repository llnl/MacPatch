from flask import Blueprint
from flask_restful import Api

antivirus = Blueprint('antivirus', __name__)
antivirus_api = Api(antivirus)

from . import routes