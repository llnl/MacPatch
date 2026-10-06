from flask import Blueprint
from flask_restful import Api

software_5 = Blueprint('software_5', __name__)
software_5_api = Api(software_5)

from . import routes
