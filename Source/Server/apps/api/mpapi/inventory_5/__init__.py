from flask import Blueprint
from flask_restful import Api

inventory_5 = Blueprint('inventory_5', __name__)
inventory_5_api = Api(inventory_5)

from . import routes
