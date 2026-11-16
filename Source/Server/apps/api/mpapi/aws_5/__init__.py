from flask import Blueprint
from flask_restful import Api

aws_5 = Blueprint('aws_5', __name__)
aws_5_api = Api(aws_5)

from . import routes
