from flask import Blueprint
from flask_restful import Api

inventory = Blueprint('inventory', __name__)
inventory_api = Api(inventory)

from . import routes