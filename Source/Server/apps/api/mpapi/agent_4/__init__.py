from flask import Blueprint
from flask_restful import Api

agent_4 = Blueprint('agent_4', __name__)
agent_4_api = Api(agent_4)

from . import routes