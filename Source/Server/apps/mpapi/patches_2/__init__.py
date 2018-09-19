from flask import Blueprint
from flask_restful import Api

patches_2 = Blueprint('patches_2', __name__)
patches_2_api = Api(patches_2)

from . import routes