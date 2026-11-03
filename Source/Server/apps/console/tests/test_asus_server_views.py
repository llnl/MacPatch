"""AJAX listing regression tests for Apple Software Update Servers."""
import ast
import unittest
from pathlib import Path

from flask import Flask, jsonify
from sqlalchemy import BigInteger, Column, Integer, String, create_engine, desc
from sqlalchemy.orm import DeclarativeBase, Session


ROOT = Path(__file__).resolve().parents[1] / 'mpconsole'


class Base(DeclarativeBase):
    pass


model = next(node for node in ast.parse((ROOT / 'model.py').read_text()).body
             if isinstance(node, ast.ClassDef) and node.name == 'MpAsusCatalog')
namespace = dict(CommonBase=Base, BigInteger=BigInteger().with_variant(Integer, 'sqlite'),
                 Column=Column, Integer=Integer, String=String)
exec(compile(ast.Module(body=[model], type_ignores=[]), '<ASUS model>', 'exec'), namespace)
MpAsusCatalog = namespace['MpAsusCatalog']

route = next(node for node in ast.parse((ROOT / 'console/views.py').read_text()).body
             if isinstance(node, ast.FunctionDef) and node.name == 'asusServersList')
route.decorator_list = []
namespace.update(jsonify=jsonify, desc=desc)
exec(compile(ast.Module(body=[route], type_ignores=[]), '<ASUS list route>', 'exec'), namespace)


class AsusServerListTests(unittest.TestCase):
    def setUp(self):
        self.app = Flask(__name__)
        self.app.config['TESTING'] = True
        self.app.add_url_rule('/console/servers/asus/list', view_func=namespace['asusServersList'])
        self.engine = create_engine('sqlite://')
        Base.metadata.create_all(self.engine)
        self.sql = Session(self.engine)
        MpAsusCatalog.query = self.sql.query(MpAsusCatalog)
        self.client = self.app.test_client()

    def tearDown(self):
        self.sql.close()
        self.engine.dispose()

    def add_server(self, minor, proxy=0, active=1):
        server = MpAsusCatalog(catalog_url=f'https://example.test/catalog-{minor}',
                               os_major=10, os_minor=minor, proxy=proxy,
                               active=active, catalog_group_name='Default')
        self.sql.add(server)
        return server

    def test_empty_list_has_json_response_and_zero_total(self):
        response = self.client.get('/console/servers/asus/list')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.is_json)
        self.assertEqual(response.json, {'data': [], 'total': 0})

    def test_row_count_order_and_display_values(self):
        self.add_server(14, proxy=0, active=1)
        self.add_server(15, proxy=1, active=0)
        self.sql.commit()
        response = self.client.get('/console/servers/asus/list')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.is_json)
        self.assertEqual(response.json['total'], 2)
        rows = response.json['data']
        self.assertEqual([row['os_minor'] for row in rows], [15, 14])
        self.assertEqual((rows[0]['proxy'], rows[0]['active']), ('Yes', 'No'))
        self.assertEqual((rows[1]['proxy'], rows[1]['active']), ('No', 'Yes'))
        self.assertEqual(set(rows[0]), {'rid', 'catalog_url', 'os_major', 'os_minor', 'proxy', 'active'})

    def test_repeated_requests_include_committed_add_edits_and_deletes(self):
        server = self.add_server(14)
        self.sql.commit()
        self.assertEqual(self.client.get('/console/servers/asus/list').json['total'], 1)

        server.catalog_url = 'https://example.test/updated-catalog'
        self.add_server(15)
        self.sql.commit()
        updated = self.client.get('/console/servers/asus/list').json
        self.assertEqual(updated['total'], 2)
        self.assertEqual(updated['data'][1]['catalog_url'], server.catalog_url)

        self.sql.delete(server)
        self.sql.commit()
        updated = self.client.get('/console/servers/asus/list').json
        self.assertEqual(updated['total'], 1)
        self.assertEqual(updated['data'][0]['os_minor'], 15)


if __name__ == '__main__':
    unittest.main()
