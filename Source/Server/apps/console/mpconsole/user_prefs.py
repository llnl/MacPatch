"""Per user console preferences, stored server side so they follow the user to any browser."""
import hashlib
import json
import re
from datetime import datetime, timezone

from flask import has_request_context, session

from mpconsole.app import db
from mpconsole.model import AdmUserPrefs

KEY_PATTERN = re.compile(r'^[A-Za-z0-9_./:@-]{1,200}$')
MAX_COLUMNS = 200
MAX_PER_USER = 500


def current_user():
    """Same identity the change log uses: the local login name, else the Entra preferred_username."""
    if not has_request_context():
        return None
    oid = session.get('oid_user') or {}
    user = session.get('user') or (oid.get('preferred_username') if isinstance(oid, dict) else None)
    return str(user)[:255] if user else None


def valid_columns(value):
    """{field: bool}, bounded, so a client cannot store arbitrary data."""
    if not isinstance(value, dict) or len(value) > MAX_COLUMNS:
        return False
    return all(isinstance(k, str) and 0 < len(k) <= 100 and isinstance(v, bool) for k, v in value.items())


def column_hash(value):
    """Short fingerprint of a saved column choice; the browser compares it with the one it stored."""
    return hashlib.sha1(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()[:12]


def prefs_for_user():
    """{'columns': {key: hash}} for the page ({} when nobody is logged in). Only hashes are sent, the
    browser asks for the data of a table when its own copy has a different hash."""
    user = current_user()
    if user is None:
        return {}
    try:
        rows = AdmUserPrefs.query.filter(AdmUserPrefs.user_id == user,
                                         AdmUserPrefs.pref_key.like('columns:%')).limit(MAX_PER_USER).all()
    except Exception:
        db.session.rollback()   # table not migrated yet: pages still work from the browser copy
        return {}
    return {'columns': {r.pref_key[len('columns:'):]: column_hash(r.value) for r in rows}}


def get_columns(user, key):
    row = AdmUserPrefs.query.filter(AdmUserPrefs.user_id == user,
                                    AdmUserPrefs.pref_key == 'columns:' + key).first()
    return row.value if row is not None else None


def save_columns(user, key, value):
    pref_key = 'columns:' + key
    row = AdmUserPrefs.query.filter(AdmUserPrefs.user_id == user, AdmUserPrefs.pref_key == pref_key).first()
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    if row is None:
        if AdmUserPrefs.query.filter(AdmUserPrefs.user_id == user).count() >= MAX_PER_USER:
            return False
        db.session.add(AdmUserPrefs(user_id=user, pref_key=pref_key, value=value, mdate=now))
    else:
        row.value = value
        row.mdate = now
    db.session.commit()
    return True


def reset_columns(user, key):
    AdmUserPrefs.query.filter(AdmUserPrefs.user_id == user,
                              AdmUserPrefs.pref_key == 'columns:' + key).delete()
    db.session.commit()
