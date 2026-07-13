from flask import request
from werkzeug.utils import secure_filename
from flask import current_app as app
from flask_mail import Message
from flask_restful import reqparse
from sqlalchemy.exc import IntegrityError
from datetime import datetime
from distutils.version import LooseVersion
import base64
import os
import shutil
import re
import uuid

from . import *
from mpapi.app import db
from mpapi.mputil import *
from mpapi.model import *
from mpapi.mplogger import *
from .. wsresult import *
from .. shared.software import *

from flask_mail import Mail

parser = reqparse.RequestParser()


def validate_client_id(client_id):
    """
    Validate client_id to prevent path traversal.
    Only allow alphanumeric, hyphens, and underscores.
    """
    if not client_id:
        raise ValueError("client_id is required")

    # Must match UUID or safe alphanumeric format
    if not re.match(r'^[a-zA-Z0-9_-]{1,64}$', client_id):
        raise ValueError(f"Invalid client_id format: {client_id}")

    # Explicitly block path traversal patterns
    if '..' in client_id or '/' in client_id or '\\' in client_id:
        raise ValueError(f"Path traversal detected in client_id: {client_id}")

    return client_id


def validate_hostname(hostname):
    """
    Validate hostname to prevent injection.
    RFC 1123 compliant: alphanumeric, hyphens, dots.
    """
    if not hostname:
        raise ValueError("hostname is required")

    if not re.match(r'^[a-zA-Z0-9.-]{1,253}$', hostname):
        raise ValueError(f"Invalid hostname format: {hostname}")

    return hostname


def get_safe_support_directory():
    """
    Get a dedicated directory for support uploads.
    Create it if it doesn't exist, with restricted permissions.
    """
    # Use a dedicated subdirectory under /tmp or app-configured path
    base_upload_dir = app.config.get('SUPPORT_UPLOAD_DIR', '/tmp/macpatch_support')

    if not os.path.exists(base_upload_dir):
        os.makedirs(base_upload_dir, mode=0o700)  # Owner only

    return base_upload_dir


class SupportDataMessage(MPResource):

    def __init__(self):
        self.reqparse = reqparse.RequestParser()
        super(SupportDataMessage, self).__init__()

    def post(self, client_id, hostname):
        req = request

        try:
            # REQUIRED: Authenticate the request
            # Uncomment and implement your auth check:
            # if not verify_client_token(request.headers.get('Authorization')):
            #     return {"result": {}, "errorno": 401, "errormsg": 'Unauthorized'}, 401

            # Validate inputs BEFORE using them
            validated_client_id = validate_client_id(client_id)
            validated_hostname = validate_hostname(hostname)

            if 'file' not in req.files:
                return {"result": {}, "errorno": 400, "errormsg": 'No file provided'}, 400

            file = req.files['file']

            # Check file was actually uploaded
            if file.filename == '':
                return {"result": {}, "errorno": 400, "errormsg": 'Empty filename'}, 400

            # Validate file size (10MB limit)
            file.seek(0, os.SEEK_END)
            file_size = file.tell()
            file.seek(0)

            MAX_FILE_SIZE = 100 * 1024 * 1024  # 100MB
            if file_size > MAX_FILE_SIZE:
                return {"result": {}, "errorno": 413, "errormsg": 'File too large'}, 413

            if file_size == 0:
                return {"result": {}, "errorno": 400, "errormsg": 'Empty file'}, 400

            # Sanitize filename
            fileName = secure_filename(file.filename)
            if not fileName:
                fileName = 'support_data.zip'

            # Validate file is a zip (check magic bytes)
            file_header = file.read(4)
            file.seek(0)
            if file_header not in [b'PK\x03\x04', b'PK\x05\x06', b'PK\x07\x08']:
                return {"result": {}, "errorno": 400, "errormsg": 'File must be a ZIP archive'}, 400

            # Use safe base directory
            safe_base_dir = get_safe_support_directory()

            # Create unique subdirectory using UUID to prevent race conditions
            # DO NOT use client_id directly in path anymore
            unique_dir_name = f"{validated_client_id}_{uuid.uuid4().hex[:8]}"
            upload_dir = os.path.join(safe_base_dir, unique_dir_name)

            # Double-check no path traversal occurred (defense in depth)
            upload_dir_real = os.path.realpath(upload_dir)
            safe_base_real = os.path.realpath(safe_base_dir)

            if not upload_dir_real.startswith(safe_base_real):
                logit(f"[SECURITY] Path traversal attempt blocked: {client_id}")
                return {"result": {}, "errorno": 400, "errormsg": 'Invalid path'}, 400

            # Create directory with restrictive permissions
            os.makedirs(upload_dir, mode=0o700, exist_ok=False)

            # Save file
            filePath = os.path.join(upload_dir, fileName)
            file.save(filePath)

            # Send email
            mail = Mail()
            mail.init_app(app)

            msg = Message(
                f"MacPatch - Support Data From {validated_hostname}",
                sender=app.config.get('SUPPORT_EMAIL_SENDER', 'mpprod01@llnl.gov'),
                recipients=app.config.get('SUPPORT_EMAIL_RECIPIENTS', ['macpatch-help@llnl.gov'])
            )
            msg.body = f"Log Capture From {validated_client_id} ({validated_hostname})\n"

            with open(filePath, 'rb') as fp:
                msg.attach(fileName, "application/zip", fp.read())

            mail.send(msg)

            # Cleanup - remove directory after successful send
            if os.path.exists(upload_dir):
                shutil.rmtree(upload_dir)

            logit(f"Support data received from {validated_client_id} ({validated_hostname})")
            return {"result": {"uploaded": fileName}, "errorno": 200, "errormsg": ''}, 200

        except ValueError as ve:
            # Validation error
            logit(f"[SECURITY] Validation error in support upload: {ve}")
            return {"result": {}, "errorno": 400, "errormsg": str(ve)}, 400

        except Exception as e:
            # Log error but don't expose internal details to client
            logit(f"Error processing support upload: {e}")

            # Cleanup on error
            try:
                if 'upload_dir' in locals() and os.path.exists(upload_dir):
                    shutil.rmtree(upload_dir)
            except:
                pass

            return {"result": {}, "errorno": 500, "errormsg": 'Upload failed'}, 500


# Add Routes Resources
# CRITICAL: Add authentication decorator here
support_api.add_resource(SupportDataMessage, '/support/data/<string:client_id>/<string:hostname>')
