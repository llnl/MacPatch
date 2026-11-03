"""Verify welcome-page warning text loaded from console dotenv configuration."""
import importlib.util
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from flask import Flask, render_template


ROOT = Path(__file__).resolve().parents[1] / 'mpconsole'


class AuthWelcomeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.appsdir = Path(self.temp.name)
        self.config_path = self.appsdir / 'console/mpconsole/config.py'
        self.config_path.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / 'config.py', self.config_path)
        (self.appsdir / '.mpglobal').write_text('SECRET_KEY=' + 'test-only-key-' * 4 + '\n')

    def welcome(self, settings='', dev_settings=''):
        (self.appsdir / '.mpconsole').write_text(settings)
        (self.appsdir / '.mpconsole_dev').write_text(dev_settings)
        # Load the real configuration against isolated dotenv files, without local secrets.
        with patch.dict(os.environ, {}, clear=True):
            spec = importlib.util.spec_from_file_location('welcome_config_under_test', self.config_path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)

        app = Flask(__name__, template_folder=str(ROOT / 'templates'))
        app.config.from_object(module.Config)
        for endpoint in ('auth.login', 'local_auth.login', 'agent.clientDownload'):
            app.add_url_rule('/' + endpoint, endpoint=endpoint, view_func=lambda: '')
        app.add_url_rule('/', view_func=lambda: render_template(
            'auth_welcome.html', allow_local=app.config['LOCAL_AUTH_ALLOWED']))
        response = app.test_client().get('/')
        self.assertEqual(response.status_code, 200)
        return response.get_data(as_text=True)

    def test_existing_warning_remains_the_default(self):
        html = self.welcome()
        self.assertIn('**WARNING**WARNING**WARNING**WARNING**', html)
        self.assertIn('This is a Department of Energy (DOE) computer system.', html)
        self.assertIn('THERE IS NO RIGHT OF PRIVACY IN THIS SYSTEM.', html)
        self.assertIn('DISCLOSURE OF COMPUTER ACTIVITY.', html)

    def test_console_file_configures_header_and_multiline_body_as_text(self):
        html = self.welcome(
            'auth_banner_title="Welcome & usage notice"\n'
            'auth_banner_text="First paragraph.\n'
            'Second paragraph with <b>literal markup</b>."\n')
        self.assertIn('Welcome &amp; usage notice', html)
        self.assertIn('First paragraph.\nSecond paragraph with &lt;b&gt;literal markup&lt;/b&gt;.', html)
        self.assertNotIn('This is a Department of Energy (DOE) computer system.', html)

    def test_development_config_can_override_warning_text(self):
        html = self.welcome('auth_banner_title="Production notice"\n',
                            'auth_banner_title="Development notice"\n'
                            'auth_banner_text="Development system."\n')
        self.assertIn('Development notice', html)
        self.assertIn('Development system.', html)
        self.assertNotIn('Production notice', html)


if __name__ == '__main__':
    unittest.main()
