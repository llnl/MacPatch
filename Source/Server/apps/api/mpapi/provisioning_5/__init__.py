from flask import Blueprint
from flask_restful import Api

provisioning_5 = Blueprint('provisioning_5', __name__)
provisioning_5_api = Api(provisioning_5)

from . import routes
