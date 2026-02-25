from flask import Blueprint
from flask_restful import Api

agent = Blueprint('agent', __name__)
agent_api = Api(agent)

from . import routes