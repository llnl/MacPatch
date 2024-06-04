from flask import Blueprint
from flask_restful import Api

inventory_2 = Blueprint('inventory_2', __name__)
inventory_2_api = Api(inventory_2)

from . import routes