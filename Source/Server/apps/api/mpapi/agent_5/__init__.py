from flask import Blueprint
from flask_restful import Api

agent_5 = Blueprint('agent_5', __name__)
agent_5_api = Api(agent_5)

from . import routes
