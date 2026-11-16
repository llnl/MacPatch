"""Configure Flask-WTF token signing for the console's crypto environment."""
import hashlib

import flask_wtf.csrf as flask_wtf_csrf
from itsdangerous import URLSafeTimedSerializer


class _SHA256CSRFSerializer(URLSafeTimedSerializer):
    def __init__(self, *args, **kwargs):
        signer_kwargs = dict(kwargs.pop('signer_kwargs', None) or {})
        signer_kwargs['digest_method'] = hashlib.sha256
        super().__init__(*args, signer_kwargs=signer_kwargs, **kwargs)


def configure_csrf_signing():
    """Use a concrete SHA-256 constructor for CSRF generation and validation.

    Flask-WTF 1.3 does not expose serializer signer options. Its default uses
    ItsDangerous' _lazy_sha1 wrapper, which some Python/OpenSSL builds reject
    as an HMAC digest. Replace only Flask-WTF's serializer reference so its
    template tokens, AJAX protection, and FlaskForm fields use the same signer.
    Other ItsDangerous serializers keep their existing behavior.

    Pages rendered before this change must be reloaded to get a new token.
    """
    flask_wtf_csrf.URLSafeTimedSerializer = _SHA256CSRFSerializer
