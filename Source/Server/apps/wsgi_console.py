from mpconsole import *

mp_console_app = create_app()

# ---------------------------------------------------
# Example on how to run it using uwsgi
#
# uwsgi --wsgi-file wsgi_console.py --callable mp_console_app --master --http :9090