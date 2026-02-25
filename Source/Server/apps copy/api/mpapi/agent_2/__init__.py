from flask import Blueprint
from flask_restful import Api

agent_2 = Blueprint('agent_2', __name__)
agent_2_api = Api(agent_2)

from . import routes