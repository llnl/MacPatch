from flask import Blueprint
from flask_restful import Api

software_4 = Blueprint('software_4', __name__)
software_4_api = Api(software_4)

from . import routes