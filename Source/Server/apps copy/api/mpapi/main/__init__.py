from flask import Blueprint
from flask_restful import Api

main = Blueprint('main', __name__)
main_api = Api(main)

from . import routes