from flask import Blueprint

content = Blueprint('content', __name__)

from . import views