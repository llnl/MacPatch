"""Add the console change log.

Revision ID: 100017
Revises: 100016
"""
from alembic import op, context
import sqlalchemy as sa

revision = '100017'
down_revision = '100016'


def upgrade():
    # Existing deployments may have used the additive init-change-log command.
    if not context.is_offline_mode() and sa.inspect(op.get_bind()).has_table('change_log'):
        return
    op.create_table('change_log',
        sa.Column('rid', sa.BigInteger().with_variant(sa.Integer(), 'sqlite'), primary_key=True, autoincrement=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('actor', sa.String(255), nullable=False),
        sa.Column('action', sa.String(10), nullable=False),
        sa.Column('record_table', sa.String(255), nullable=False),
        sa.Column('record_key', sa.JSON(), nullable=False),
        sa.Column('record_label', sa.String(255), nullable=False),
        sa.Column('changes', sa.JSON(), nullable=False),
        sa.Column('request_id', sa.String(36), nullable=False),
        sa.Column('endpoint', sa.String(255), nullable=False),
        sa.Column('method', sa.String(10), nullable=False))
    op.create_index('ix_change_log_created_id', 'change_log', ['created_at', 'rid'])
    op.create_index('ix_change_log_actor_created', 'change_log', ['actor', 'created_at'])
    op.create_index('ix_change_log_table_created', 'change_log', ['record_table', 'created_at'])
    op.create_index('ix_change_log_request_id', 'change_log', ['request_id'])


def downgrade():
    op.drop_table('change_log')
