from flask import Blueprint
from flask_restful import Api

software_2 = Blueprint('software_2', __name__)
software_2_api = Api(software_2)

from . import routes