"""Registration client listing regression tests, without the configured MySQL app."""
import ast
import json
import unittest
from datetime import date, datetime
from pathlib import Path
from types import SimpleNamespace

from flask import Flask
from sqlalchemy import BigInteger, Column, DateTime, Integer, String, Text, create_engine
from sqlalchemy.orm import DeclarativeBase, Session


ROOT = Path(__file__).resolve().parents[1] / 'mpconsole'


class Base(DeclarativeBase):
    pass


# Exercise the real model definitions and query with portable SQLite column types.
model_names = {'CommonBase', 'MPAgentRegistration', 'MpClientGroups', 'MpClientGroupMembers'}
model_nodes = [node for node in ast.parse((ROOT / 'model.py').read_text()).body
               if isinstance(node, ast.ClassDef) and node.name in model_names]
namespace = dict(db=SimpleNamespace(Model=Base), date=date, datetime=datetime,
                 BigInteger=BigInteger().with_variant(Integer, 'sqlite'), Column=Column,
                 Integer=Integer, String=String, DateTime=DateTime, MEDIUMTEXT=Text)
exec(compile(ast.Module(body=model_nodes, type_ignores=[]), '<registration models>', 'exec'), namespace)
MPAgentRegistration = namespace['MPAgentRegistration']
MpClientGroups = namespace['MpClientGroups']
MpClientGroupMembers = namespace['MpClientGroupMembers']

route_nodes = [node for node in ast.parse((ROOT / 'registration/views.py').read_text()).body
               if isinstance(node, ast.FunctionDef) and node.name in ('clients', 'searchForGroup')]
for node in route_nodes:
    node.decorator_list = []
serializer = next(node for node in ast.parse((ROOT / 'mputil.py').read_text()).body
                  if isinstance(node, ast.FunctionDef) and node.name == 'json_serial')
namespace['json'] = json
exec(compile(ast.Module(body=[serializer] + route_nodes, type_ignores=[]),
             '<registration routes>', 'exec'), namespace)


class RegistrationClientViewTests(unittest.TestCase):
    def setUp(self):
        self.app = Flask(__name__)
        self.app.config['TESTING'] = True
        self.app.add_url_rule('/registration/clients', view_func=namespace['clients'])
        self.engine = create_engine('sqlite://')
        Base.metadata.create_all(self.engine)
        self.sql = Session(self.engine)
        for model in (MPAgentRegistration, MpClientGroups, MpClientGroupMembers):
            model.query = self.sql.query(model)
        self.client = self.app.test_client()

    def tearDown(self):
        self.sql.close()
        self.engine.dispose()

    def add_client(self, client_id, group_id):
        self.sql.add(MPAgentRegistration(
            cuuid=client_id, hostname=client_id, serialno='test-serial',
            reg_date=datetime(2026, 11, 3, 12), clientKey='private-client-key',
            pubKeyPem='private-public-key', pubKeyPemHash='private-key-hash'))
        self.sql.add(MpClientGroupMembers(cuuid=client_id, group_id=group_id))

    def test_missing_group_does_not_break_registered_client_listing(self):
        self.sql.add(MpClientGroups(group_id='known-group', group_name='Production'))
        self.add_client('known-client', 'known-group')
        self.add_client('orphan-client', 'missing-group')
        self.sql.commit()

        response = self.client.get('/registration/clients?search=')
        self.assertEqual(response.status_code, 200)
        rows = {row['cuuid']: row for row in json.loads(response.data)}
        self.assertEqual(set(rows), {'known-client', 'orphan-client'})
        self.assertEqual(rows['known-client']['group_name'], 'Production')
        self.assertEqual(rows['orphan-client']['group_name'], 'Unknown Group')
        for row in rows.values():
            self.assertEqual(row['reg_date'], '2026-11-03 12:00:00')
            for key in ('clientKey', 'pubKeyPem', 'pubKeyPemHash'):
                self.assertNotIn(key, row)

    def test_empty_group_table_still_returns_registered_clients(self):
        self.add_client('orphan-client', 'missing-group')
        self.sql.commit()
        response = self.client.get('/registration/clients')
        self.assertEqual(response.status_code, 200)
        rows = json.loads(response.data)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['group_name'], 'Unknown Group')

    def test_no_registered_clients_returns_an_empty_list(self):
        response = self.client.get('/registration/clients')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(json.loads(response.data), [])


if __name__ == '__main__':
    unittest.main()
