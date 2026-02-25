from flask import Blueprint

agent = Blueprint('agent', __name__)

from . import views