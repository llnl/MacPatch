"""
Share one TLS context between all MySQL connections of a worker.

PyMySQL builds a new ssl context for every connection it opens, and building one loads the
system CA bundle from disk (ssl.create_default_context -> load_default_certs). Under load this was
about 20% of the CPU of an API worker.

When no SSL options are given (this app's database URI has none) PyMySQL builds the same
context every time, so it is built once and reused. Behaviour does not change: the connection is
still opportunistic TLS, with no certificate verification, exactly as before. Connections that pass
SSL options (a CA file and so on) are not touched.
"""
import threading

_lock = threading.Lock()
_installed = False


def install():
	"""Patch PyMySQL once. Does nothing if PyMySQL does not look as expected."""
	global _installed

	with _lock:
		if _installed:
			return False

		try:
			from pymysql.connections import Connection
		except Exception:
			return False

		original = getattr(Connection, '_create_ssl_ctx', None)
		if original is None:
			return False

		cached = {}

		def _create_ssl_ctx(self, sslp):
			# Only the "no options" context is shared, anything else is built as before
			if isinstance(sslp, dict) and not sslp:
				ctx = cached.get('default')
				if ctx is None:
					ctx = original(self, sslp)
					cached['default'] = ctx
				return ctx
			return original(self, sslp)

		Connection._create_ssl_ctx = _create_ssl_ctx
		_installed = True
		return True
