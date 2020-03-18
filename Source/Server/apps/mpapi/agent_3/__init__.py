from flask import Blueprint
from flask_restful import Api

agent_3 = Blueprint('agent_3', __name__)
agent_3_api = Api(agent_3)

from . import routes