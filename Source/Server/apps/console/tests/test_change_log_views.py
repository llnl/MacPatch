import ast
import unittest
from datetime import datetime, timedelta

from flask import Flask, request, session, jsonify, render_template
from sqlalchemy import create_engine, or_
from sqlalchemy.orm import Session

from test_change_log import Base, ChangeLog, ROOT


class ChangeLogViewTests(unittest.TestCase):
    def setUp(self):
        self.app = Flask(__name__, template_folder=str(ROOT / 'templates'))
        engine = self.engine = create_engine('sqlite://')
        Base.metadata.create_all(engine)
        self.sql = Session(engine)
        ChangeLog.query = self.sql.query(ChangeLog)
        self.allowed = True
        nodes = [n for n in ast.parse((ROOT / 'console/views.py').read_text()).body
                 if isinstance(n, ast.FunctionDef) and n.name in ('changeLogView', 'changeLogData', 'changeLogFilters')]
        for n in nodes:
            n.decorator_list = []
        from types import SimpleNamespace
        namespace = dict(localAdmin=lambda: self.allowed, adminRole=lambda: False,
                         ChangeLog=ChangeLog, request=request, session=session, jsonify=jsonify,
                         render_template=render_template, datetime=datetime, timedelta=timedelta,
                         or_=or_, db=SimpleNamespace(session=self.sql))
        exec(compile(ast.Module(body=nodes, type_ignores=[]), '<actual change-log routes>', 'exec'), namespace)
        for endpoint, path in [('changeLogData', '/data'), ('changeLogFilters', '/filters')]:
            self.app.add_url_rule(path, view_func=namespace[endpoint])
        self.sql.add_all([ChangeLog(created_at=datetime(2026, 11, 2, 12, index), actor=actor, action='update',
                          record_table='mp_patch_groups', record_key={'id': index}, record_label=name,
                          changes={'name': {'before': 'Default', 'after': name}},
                          request_id=str(index), endpoint='patches.edit', method='POST')
                         for index, (actor, name) in enumerate([('alice', 'QA'), ('bob', 'Production'), ('alice', '100% Ready')])])
        self.sql.commit()
        self.client = self.app.test_client()

    def tearDown(self):
        self.sql.close()
        self.engine.dispose()

    def test_pagination_filters_and_order(self):
        data = self.client.get('/data?limit=1&offset=1').json
        self.assertEqual(data['total'], 3)
        self.assertEqual(data['rows'][0]['actor'], 'bob')
        self.assertEqual(self.client.get('/data?actor=alice').json['total'], 2)
        self.assertEqual(self.client.get('/data?action=delete').json['total'], 0)
        self.assertEqual(self.client.get('/data?from_date=2026-11-02&to_date=2026-11-02').json['total'], 3)
        self.assertEqual(self.client.get('/data?to_date=2026-11-01').json['total'], 0)
        self.assertEqual(self.client.get('/data?search=100%25').json['total'], 1)
        self.assertEqual(self.client.get('/data').json['rows'][0]['changes']['name']['after'], '100% Ready')
        self.assertTrue(self.client.get('/data').json['rows'][0]['created_at'].endswith('Z'))
        self.assertEqual(self.client.get('/filters').json['actors'], ['alice', 'bob'])

    def test_access_and_invalid_input(self):
        self.assertEqual(self.client.get('/data?limit=bad').status_code, 400)
        self.assertEqual(self.client.get('/data?from_date=invalid').status_code, 400)
        self.allowed = False
        self.assertEqual(self.client.get('/data').status_code, 403)
        self.assertEqual(self.client.get('/filters').status_code, 403)

if __name__ == '__main__':
    unittest.main()
