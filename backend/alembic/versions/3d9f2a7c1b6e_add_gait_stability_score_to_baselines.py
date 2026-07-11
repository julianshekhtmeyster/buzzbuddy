"""add gait_stability_score to baselines

Revision ID: 3d9f2a7c1b6e
Revises: 11a161e8331d
Create Date: 2026-07-11 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '3d9f2a7c1b6e'
down_revision: Union[str, Sequence[str], None] = '11a161e8331d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('baselines', sa.Column('gait_stability_score', sa.Float(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('baselines', 'gait_stability_score')
