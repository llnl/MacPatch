"""00016 - Inventory processing statistics

Revision ID: 100016
Revises: 100015
Create Date: 2026-10-06

"""

# revision identifiers, used by Alembic.
revision = '100016'
down_revision = '100015'

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


def upgrade():

	op.create_table('mp_inv_stats',
		sa.Column('rid', sa.BigInteger(), nullable=False, autoincrement=True),
		sa.Column('started', sa.DateTime(), nullable=False),
		sa.Column('cuuid', sa.String(length=50), server_default='', nullable=False),
		sa.Column('inv_table', sa.String(length=255), server_default='', nullable=False),
		sa.Column('result', sa.String(length=30), nullable=False),
		sa.Column('error_no', sa.Integer(), nullable=True),
		sa.Column('error_stage', sa.String(length=20), nullable=True),
		sa.Column('error_msg', mysql.TEXT(), nullable=True),
		sa.Column('file_name', sa.String(length=255), nullable=True),
		sa.Column('file_bytes', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('rows_received', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('rows_inserted', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('rows_updated', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('rows_purged', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('table_created', sa.Integer(), server_default='0', nullable=True),
		sa.Column('queued_ms', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('schema_ms', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('load_ms', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('total_ms', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('mp_server', sa.String(length=255), nullable=True),
		sa.PrimaryKeyConstraint('rid')
	)
	op.create_index(op.f('ix_mp_inv_stats_started'), 'mp_inv_stats', ['started'], unique=False)
	op.create_index(op.f('ix_mp_inv_stats_cuuid'), 'mp_inv_stats', ['cuuid'], unique=False)
	op.create_index(op.f('ix_mp_inv_stats_inv_table'), 'mp_inv_stats', ['inv_table'], unique=False)
	op.create_index(op.f('ix_mp_inv_stats_result'), 'mp_inv_stats', ['result'], unique=False)

	op.create_table('mp_inv_stats_daily',
		sa.Column('rid', sa.BigInteger(), nullable=False, autoincrement=True),
		sa.Column('day', sa.Date(), nullable=False),
		sa.Column('inv_table', sa.String(length=255), nullable=False),
		sa.Column('result', sa.String(length=30), nullable=False),
		sa.Column('loads', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('rows_inserted', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('rows_updated', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('rows_purged', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('file_bytes', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('queued_ms_total', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('queued_ms_max', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('load_ms_total', sa.BigInteger(), server_default='0', nullable=True),
		sa.Column('load_ms_max', sa.BigInteger(), server_default='0', nullable=True),
		sa.PrimaryKeyConstraint('rid'),
		sa.UniqueConstraint('day', 'inv_table', 'result', name='uq_mp_inv_stats_daily')
	)
	op.create_index(op.f('ix_mp_inv_stats_daily_day'), 'mp_inv_stats_daily', ['day'], unique=False)


def downgrade():

	op.drop_index(op.f('ix_mp_inv_stats_daily_day'), table_name='mp_inv_stats_daily')
	op.drop_table('mp_inv_stats_daily')

	op.drop_index(op.f('ix_mp_inv_stats_result'), table_name='mp_inv_stats')
	op.drop_index(op.f('ix_mp_inv_stats_inv_table'), table_name='mp_inv_stats')
	op.drop_index(op.f('ix_mp_inv_stats_cuuid'), table_name='mp_inv_stats')
	op.drop_index(op.f('ix_mp_inv_stats_started'), table_name='mp_inv_stats')
	op.drop_table('mp_inv_stats')
