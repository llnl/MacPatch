from flask import Blueprint
from flask_restful import Api

support = Blueprint('support', __name__)
support_api = Api(support)

from . import routes