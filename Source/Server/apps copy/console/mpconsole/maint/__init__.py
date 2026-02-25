from flask import Blueprint

maint = Blueprint('maint', __name__)

from . import views