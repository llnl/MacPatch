from flask import Blueprint
from flask_restful import Api

patches_4 = Blueprint('patches_4', __name__)
patches_4_api = Api(patches_4)

from . import routes