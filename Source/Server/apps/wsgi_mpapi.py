from mpapi import *

mp_api_app = create_app()

# ---------------------------------------------------
# Example on how to run it using uwsgi
#
# uwsgi --wsgi-file wsgi_mpapi.py --callable mp_api_app --master --http :8080