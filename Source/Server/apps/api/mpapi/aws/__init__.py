from flask import Blueprint
from flask_restful import Api

aws = Blueprint('aws', __name__)
aws_api = Api(aws)

from . import routes