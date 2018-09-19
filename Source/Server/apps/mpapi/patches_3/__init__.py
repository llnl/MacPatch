from flask import Blueprint
from flask_restful import Api

patches_3 = Blueprint('patches_3', __name__)
patches_3_api = Api(patches_3)

from . import routes