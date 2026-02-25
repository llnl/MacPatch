from flask import Blueprint
from flask_restful import Api

inventory_3 = Blueprint('inventory_3', __name__)
inventory_3_api = Api(inventory_3)

from . import routes