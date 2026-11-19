"""Add per user console preferences.

Revision ID: 100018
Revises: 100017
"""
from alembic import op, context
import sqlalchemy as sa

revision = '100018'
down_revision = '100017'


def upgrade():
    if not context.is_offline_mode() and sa.inspect(op.get_bind()).has_table('mp_adm_user_prefs'):
        return
    op.create_table('mp_adm_user_prefs',
        sa.Column('rid', sa.BigInteger().with_variant(sa.Integer(), 'sqlite'), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.String(255), nullable=False),
        sa.Column('pref_key', sa.String(200), nullable=False),
        sa.Column('value', sa.JSON(), nullable=False),
        sa.Column('mdate', sa.DateTime(), nullable=False),
        sa.UniqueConstraint('user_id', 'pref_key', name='uq_adm_user_prefs_user_key'))


def downgrade():
    op.drop_table('mp_adm_user_prefs')
