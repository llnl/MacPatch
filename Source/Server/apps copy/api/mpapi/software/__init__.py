from flask import Blueprint
from flask_restful import Api

software = Blueprint('software', __name__)
software_api = Api(software)

from . import routes