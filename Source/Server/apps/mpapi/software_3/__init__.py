from flask import Blueprint
from flask_restful import Api

software_3 = Blueprint('software_3', __name__)
software_3_api = Api(software_3)

from . import routes