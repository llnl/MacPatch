from flask import Blueprint
from flask_restful import Api

patches = Blueprint('patches', __name__)
patches_api = Api(patches)

from . import routes