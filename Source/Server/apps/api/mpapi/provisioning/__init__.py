from flask import Blueprint
from flask_restful import Api

provisioning = Blueprint('provisioning', __name__)
provisioning_api = Api(provisioning)

from . import routes