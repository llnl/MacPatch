"""Record console database writes in the same transaction as the changed rows."""
import hashlib
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

from flask import current_app, g, has_request_context, request, session
from sqlalchemy import and_, event, or_, select
from sqlalchemy.sql.dml import Insert, Update, Delete
from sqlalchemy.sql.elements import TextClause


def _value(value):
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, bytes):
        return {'bytes': len(value), 'sha256': hashlib.sha256(value).hexdigest()}
    if isinstance(value, dict):
        return {str(k): _value(v) for k, v in value.items()}
    if isinstance(value, (tuple, list)):
        return [_value(v) for v in value]
    return value


def _secret(name):
    name = name.lower().replace('_', '').replace('-', '')
    return any(word in name for word in ('password', 'passwd', 'secret', 'token',
               'privatekey', 'prikey', 'regkey', 'autoregkey', 'userkey',
               'userpass', 'clientkey', 'akeyvalue', 'bypasscode'))


def _display(name, value, row):
    if _secret(name) or (name.lower() in ('value', 'data', 'config_value')
                        and _secret(str(row.get('key', row.get('name', ''))))):
        return '[redacted]' if value is not None else None
    if isinstance(value, dict):
        return {k: _display(str(k), v, value) for k, v in value.items()}
    if isinstance(value, list):
        return [_display(name, v, row) for v in value]
    return _value(value)


def _identity(table, row):
    return {column.name: _value(row[column.name]) for column in table.primary_key}


def _by_keys(table, rows):
    return or_(*(and_(*(column == row[column.name] for column in table.primary_key))
                 for row in rows))


def _metadata():
    if not getattr(g, 'change_log_request_id', None):
        g.change_log_request_id = str(uuid.uuid4())
    oid = session.get('oid_user') or {}
    actor = session.get('user') or (oid.get('preferred_username') if isinstance(oid, dict) else None)
    return dict(created_at=datetime.now(timezone.utc).replace(tzinfo=None),
                actor=str(actor or 'system')[:255], request_id=g.change_log_request_id,
                endpoint=str(request.endpoint or '')[:255], method=request.method)


def install_change_log(engine, log_table):
    if getattr(engine, '_macpatch_change_log_installed', False):
        return
    engine._macpatch_change_log_installed = True

    def active(options):
        return (has_request_context()
                and current_app.config.get('CHANGE_LOG_ENABLED', True)
                and not options.get('change_log_internal'))

    @event.listens_for(engine, 'before_execute')
    def reject_untracked_sql(conn, statement, multiparams, params, options):
        if active(options) and isinstance(statement, TextClause):
            sql = statement.text.lstrip().upper()
            if sql.startswith(('INSERT ', 'UPDATE ', 'DELETE ', 'REPLACE ', 'TRUNCATE ')):
                raise RuntimeError('Console writes must use SQLAlchemy tables so change_log can record field changes.')

    @event.listens_for(engine, 'before_cursor_execute')
    def snapshot(conn, cursor, sql, parameters, context, executemany):
        if not active(context.execution_options) or not context.compiled:
            return
        statement = context.compiled.statement
        if not isinstance(statement, (Update, Delete)) or statement.table.name == log_table.name:
            return
        table = statement.table
        if not len(table.primary_key):
            raise RuntimeError('Console change logging requires a primary key: ' + table.name)
        rows = {}
        # Compiled parameters include ORM primary-key binds and bulk-update values.
        for values in context.compiled_parameters:
            query = select(table)
            if statement.whereclause is not None:
                query = query.where(statement.whereclause)
            for row in conn.execute(query.with_for_update(), values).mappings():
                row = dict(row)
                rows[tuple(row[c.name] for c in table.primary_key)] = row
        context._change_log_before = list(rows.values())

    @event.listens_for(engine, 'after_execute')
    def record(conn, statement, multiparams, params, options, result):
        if not active(options) or not isinstance(statement, (Insert, Update, Delete)):
            return
        table = statement.table
        if table.name == log_table.name:
            return
        if not len(table.primary_key):
            raise RuntimeError('Console change logging requires a primary key: ' + table.name)
        before = getattr(result.context, '_change_log_before', [])
        if isinstance(statement, Insert):
            # SQLAlchemy exposes generated keys for single and batched ORM inserts.
            keys = result.inserted_primary_key_rows
            if not keys or any(any(v is None for v in key) for key in keys):
                raise RuntimeError('Cannot identify inserted rows for change_log: ' + table.name)
            identities = [dict(zip((c.name for c in table.primary_key), key)) for key in keys]
            after = [dict(row) for row in conn.execute(select(table).where(_by_keys(table, identities))).mappings()]
            pairs = [(None, row) for row in after]
            action = 'create'
        elif isinstance(statement, Delete):
            pairs = [(row, None) for row in before]
            action = 'delete'
        else:
            if not before:
                return
            after = {tuple(row[c.name] for c in table.primary_key): dict(row)
                     for row in conn.execute(select(table).where(_by_keys(table, before))).mappings()}
            pairs = [(row, after.get(tuple(row[c.name] for c in table.primary_key))) for row in before]
            if any(new is None for old, new in pairs):
                raise RuntimeError('Changing primary keys is not supported by change_log: ' + table.name)
            action = 'update'
        entries = []
        metadata = _metadata()
        for old, new in pairs:
            row = new if new is not None else old
            changes = {}
            for column in table.columns:
                name = column.name
                old_value = old.get(name) if old is not None else None
                new_value = new.get(name) if new is not None else None
                if old is not None and new is not None and old_value == new_value:
                    continue
                changes[name] = {'before': _display(name, old_value, old or row),
                                 'after': _display(name, new_value, new or row)}
            if not changes:
                continue
            label = next((row.get(key) for key in ('group_name', 'name', 'patch_name',
                         'patchname', 'supatchname', 'user_id', 'title') if row.get(key)), '')
            entries.append(dict(metadata, action=action, record_table=table.name,
                                record_key=_identity(table, row), record_label=str(label)[:255], changes=changes))
        if entries:
            conn.execute(log_table.insert().execution_options(change_log_internal=True), entries)
