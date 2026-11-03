"""Run with: .consoleenv/bin/python -m unittest discover -s console/tests"""
import ast
import importlib.util
import unittest
from datetime import datetime
from pathlib import Path

from flask import Flask, session
from sqlalchemy import (BigInteger, Column, DateTime, Integer, String, JSON, Index,
                        create_engine, select, update, delete, insert, text)
from sqlalchemy.orm import DeclarativeBase, Session

ROOT = Path(__file__).resolve().parents[1] / 'mpconsole'
spec = importlib.util.spec_from_file_location('change_log_under_test', ROOT / 'change_log.py')
recorder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recorder)

class Base(DeclarativeBase):
    pass

# Load the real model definition without starting the configured Redis/MySQL app.
node = next(n for n in ast.parse((ROOT / 'model.py').read_text()).body
            if isinstance(n, ast.ClassDef) and n.name == 'ChangeLog')
namespace = dict(CommonBase=Base, BigInteger=BigInteger, Integer=Integer, Column=Column,
                 DateTime=DateTime, String=String, JSON=JSON, Index=Index)
exec(compile(ast.Module(body=[node], type_ignores=[]), '<ChangeLog model>', 'exec'), namespace)
ChangeLog = namespace['ChangeLog']

class Group(Base):
    __tablename__ = 'mp_patch_groups'
    id = Column(Integer, primary_key=True)
    name = Column(String)
    state = Column(String)
    password_hash = Column(String)

class ChangeLogTests(unittest.TestCase):
    def setUp(self):
        self.app = Flask(__name__)
        self.app.secret_key = 'test-only'
        self.engine = create_engine('sqlite://')
        Base.metadata.create_all(self.engine)
        recorder.install_change_log(self.engine, ChangeLog.__table__)
        recorder.install_change_log(self.engine, ChangeLog.__table__)
        self.sql = Session(self.engine)
        self.context = self.app.test_request_context('/patches/group/edit/1', method='POST')
        self.context.push()
        session['user'] = 'test-admin'

    def tearDown(self):
        self.sql.close()
        self.context.pop()
        self.engine.dispose()

    def logs(self):
        return self.sql.scalars(select(ChangeLog).order_by(ChangeLog.rid)).all()

    def test_create_update_delete_and_generated_id(self):
        group = Group(name='Default', state='Create', password_hash='old-secret')
        self.sql.add(group)
        self.sql.commit()
        group.name = 'Production'
        group.password_hash = 'new-secret'
        self.sql.commit()
        self.sql.delete(group)
        self.sql.commit()
        logs = self.logs()
        self.assertEqual([r.action for r in logs], ['create', 'update', 'delete'])
        self.assertEqual(logs[0].record_key, {'id': 1})
        self.assertEqual(logs[1].changes['name'], {'before': 'Default', 'after': 'Production'})
        self.assertEqual(logs[1].changes['password_hash'], {'before': '[redacted]', 'after': '[redacted]'})
        self.assertEqual(logs[0].actor, 'test-admin')
        self.assertEqual(len({r.request_id for r in logs}), 1)
        self.assertEqual(logs[0].method, 'POST')
        self.assertIsInstance(logs[0].created_at, datetime)
        self.assertNotIn('state', logs[1].changes)

    def test_bulk_update_delete_and_noop(self):
        self.sql.add_all([Group(name='One', state='Create'), Group(name='Two', state='Create'), Group(name='Three', state='QA')])
        self.sql.commit()
        self.sql.query(Group).filter(Group.state == 'Create').update({'state': 'QA'})
        self.sql.commit()
        self.assertEqual(len(self.logs()), 5)
        self.assertEqual([r.changes['state'] for r in self.logs()[3:]], [{'before': 'Create', 'after': 'QA'}] * 2)
        self.sql.query(Group).filter(Group.state == 'QA').update({'state': 'QA'})
        self.sql.commit()
        self.assertEqual(len(self.logs()), 5)
        self.sql.query(Group).filter(Group.name.in_(['One', 'Two'])).delete(synchronize_session=False)
        self.sql.commit()
        self.assertEqual([r.action for r in self.logs()[-2:]], ['delete', 'delete'])

    def test_rollback_and_outside_request(self):
        self.sql.add(Group(name='Not committed'))
        self.sql.flush()
        self.sql.rollback()
        self.assertEqual(self.logs(), [])
        self.context.pop()
        with self.engine.begin() as conn:
            conn.execute(insert(Group).values(name='Background job'))
        self.context.push()
        self.assertEqual(self.logs(), [])

    def test_core_executemany_and_failed_log_rolls_back(self):
        with self.engine.begin() as conn:
            conn.execute(insert(Group), [{'id': 10, 'name': 'One'}, {'id': 11, 'name': 'Two'}])
        self.assertEqual(len(self.logs()), 2)
        self.sql.rollback()
        # A missing log table must not leave an unlogged committed change.
        ChangeLog.__table__.drop(self.engine)
        with self.assertRaises(Exception):
            with self.engine.begin() as conn:
                conn.execute(update(Group).where(Group.id == 10).values(name='Unsaved'))
        self.assertEqual(self.sql.get(Group, 10).name, 'One')

    def test_redaction_nested_values_and_raw_sql(self):
        self.assertEqual(recorder._display('data', {'token': 'secret', 'label': '<tag>'}, {}), {'token': '[redacted]', 'label': '<tag>'})
        self.assertEqual(recorder._display('value', 'secret', {'key': 'client_secret'}), '[redacted]')
        self.assertEqual(recorder._display('priKey', 'secret', {}), '[redacted]')
        with self.assertRaises(RuntimeError):
            self.sql.execute(text("DELETE FROM mp_patch_groups"))
        self.sql.rollback()
        self.assertEqual(self.logs(), [])

    def test_disable_and_reenable_recording(self):
        self.sql.add(Group(name='Original'))
        self.sql.commit()
        self.app.config['CHANGE_LOG_ENABLED'] = False
        self.sql.execute(update(Group).where(Group.id == 1).values(name='Not logged'))
        self.sql.commit()
        self.assertEqual(len(self.logs()), 1)
        self.app.config['CHANGE_LOG_ENABLED'] = True
        self.sql.execute(update(Group).where(Group.id == 1).values(name='Logged again'))
        self.sql.commit()
        self.assertEqual(len(self.logs()), 2)
        self.assertEqual(self.logs()[1].changes['name'],
                         {'before': 'Not logged', 'after': 'Logged again'})
        self.sql.rollback()
        self.app.config['CHANGE_LOG_ENABLED'] = False
        ChangeLog.__table__.drop(self.engine)
        self.sql.execute(text("UPDATE mp_patch_groups SET name = 'Disabled without log table' WHERE id = 1"))
        self.sql.commit()
        self.assertEqual(self.sql.get(Group, 1).name, 'Disabled without log table')

if __name__ == '__main__':
    unittest.main()
