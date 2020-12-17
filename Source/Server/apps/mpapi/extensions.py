from flask import Flask

from flask_sqlalchemy_cache import CachingQuery
from flask_sqlalchemy import SQLAlchemy, Model
Model.query_class = CachingQuery
db = SQLAlchemy(query_class=CachingQuery)

from flask_migrate import Migrate
migrate = Migrate()

from flask_caching import Cache
cache = Cache()
