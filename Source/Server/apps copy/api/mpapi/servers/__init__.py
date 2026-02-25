from flask import Blueprint
from flask_restful import Api

servers = Blueprint('servers', __name__)
servers_api = Api(servers)

from . import routes