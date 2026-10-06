from flask import Blueprint
from flask_restful import Api

patches_5 = Blueprint('patches_5', __name__)
patches_5_api = Api(patches_5)

from . import routes
