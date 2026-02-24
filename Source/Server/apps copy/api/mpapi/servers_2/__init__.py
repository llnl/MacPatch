from flask import Blueprint
from flask_restful import Api

servers_2 = Blueprint('servers_2', __name__)
servers_2_api = Api(servers_2)

from . import routes