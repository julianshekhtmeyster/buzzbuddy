"""add final_summary to agent_sessions

Revision ID: 8b2e4f1a9c3d
Revises: 3d9f2a7c1b6e
Create Date: 2026-07-11 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '8b2e4f1a9c3d'
down_revision: Union[str, Sequence[str], None] = '3d9f2a7c1b6e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('agent_sessions', sa.Column('final_summary', sa.String(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('agent_sessions', 'final_summary')
