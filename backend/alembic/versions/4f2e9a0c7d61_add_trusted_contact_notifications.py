"""add trusted contact invitations and notification delivery state

Revision ID: 4f2e9a0c7d61
Revises: 11a161e8331d
Create Date: 2026-07-11

"""

import datetime
import secrets
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "4f2e9a0c7d61"
down_revision: Union[str, Sequence[str], None] = "11a161e8331d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("users") as batch_op:
        batch_op.add_column(sa.Column("access_token_hash", sa.String(), nullable=True))
    op.create_index("ix_users_access_token_hash", "users", ["access_token_hash"])

    with op.batch_alter_table("dd_contacts") as batch_op:
        batch_op.add_column(sa.Column("invite_code", sa.String(), nullable=True))
        batch_op.add_column(
            sa.Column(
                "invite_status",
                sa.String(),
                server_default="pending",
                nullable=False,
            )
        )
        batch_op.add_column(sa.Column("invite_expires_at", sa.DateTime(), nullable=True))
        batch_op.add_column(sa.Column("accepted_at", sa.DateTime(), nullable=True))
        batch_op.add_column(sa.Column("access_token_hash", sa.String(), nullable=True))
        batch_op.add_column(
            sa.Column("sms_consent", sa.Boolean(), server_default=sa.false(), nullable=False)
        )
        batch_op.add_column(sa.Column("sms_consent_at", sa.DateTime(), nullable=True))
        batch_op.add_column(sa.Column("created_at", sa.DateTime(), nullable=True))
        batch_op.add_column(sa.Column("updated_at", sa.DateTime(), nullable=True))

    # Existing contacts receive a seven-day one-use invitation.
    connection = op.get_bind()
    contacts = sa.table(
        "dd_contacts",
        sa.column("id", sa.String()),
        sa.column("invite_code", sa.String()),
        sa.column("invite_expires_at", sa.DateTime()),
        sa.column("created_at", sa.DateTime()),
        sa.column("updated_at", sa.DateTime()),
    )
    now = datetime.datetime.utcnow()
    expires_at = now + datetime.timedelta(days=7)
    contact_ids = connection.execute(sa.select(contacts.c.id)).scalars().all()
    for contact_id in contact_ids:
        connection.execute(
            contacts.update()
            .where(contacts.c.id == contact_id)
            .values(
                invite_code=secrets.token_urlsafe(18),
                invite_expires_at=expires_at,
                created_at=now,
                updated_at=now,
            )
        )

    op.create_index("ix_dd_contacts_invite_code", "dd_contacts", ["invite_code"], unique=True)
    op.create_index("ix_dd_contacts_access_token_hash", "dd_contacts", ["access_token_hash"])

    with op.batch_alter_table("events") as batch_op:
        batch_op.add_column(sa.Column("selected_contact_id", sa.String(), nullable=True))
        batch_op.create_foreign_key(
            "fk_events_selected_contact_id_dd_contacts",
            "dd_contacts",
            ["selected_contact_id"],
            ["id"],
        )

    # Preserve behavior for existing one-contact users without ever selecting
    # one arbitrarily when multiple contacts exist.
    events = sa.table(
        "events",
        sa.column("id", sa.String()),
        sa.column("user_id", sa.String()),
        sa.column("selected_contact_id", sa.String()),
    )
    contact_users = sa.table(
        "dd_contacts",
        sa.column("id", sa.String()),
        sa.column("user_id", sa.String()),
    )
    user_ids = connection.execute(sa.select(events.c.user_id).distinct()).scalars().all()
    for user_id in user_ids:
        matching_contact_ids = connection.execute(
            sa.select(contact_users.c.id).where(contact_users.c.user_id == user_id)
        ).scalars().all()
        if len(matching_contact_ids) == 1:
            connection.execute(
                events.update()
                .where(events.c.user_id == user_id)
                .values(selected_contact_id=matching_contact_ids[0])
            )

    with op.batch_alter_table("agent_sessions") as batch_op:
        batch_op.add_column(
            sa.Column(
                "notification_status",
                sa.String(),
                server_default="not_requested",
                nullable=False,
            )
        )
        batch_op.add_column(sa.Column("notification_attempt_id", sa.String(), nullable=True))

    op.create_table(
        "contact_devices",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("contact_id", sa.String(), nullable=False),
        sa.Column("device_token", sa.String(), nullable=False),
        sa.Column("environment", sa.String(), nullable=False, server_default="production"),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["contact_id"], ["dd_contacts.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("contact_id", "device_token", name="uq_contact_device_token"),
    )
    op.create_index("ix_contact_devices_contact_id", "contact_devices", ["contact_id"])

    op.create_table(
        "notification_attempts",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("session_id", sa.String(), nullable=False),
        sa.Column("contact_id", sa.String(), nullable=False),
        sa.Column("contact_device_id", sa.String(), nullable=True),
        sa.Column("kind", sa.String(), nullable=False),
        sa.Column("channel", sa.String(), nullable=False),
        sa.Column("status", sa.String(), nullable=False, server_default="pending"),
        sa.Column("provider_status", sa.String(), nullable=True),
        sa.Column("provider_message_id", sa.String(), nullable=True),
        sa.Column("provider_details", sa.JSON(), nullable=True),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("location_url", sa.String(), nullable=True),
        sa.Column("error_code", sa.String(), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("lease_expires_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("sent_at", sa.DateTime(), nullable=True),
        sa.Column("delivered_at", sa.DateTime(), nullable=True),
        sa.Column("acknowledged_at", sa.DateTime(), nullable=True),
        sa.Column("acknowledgement_response", sa.String(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["contact_device_id"], ["contact_devices.id"]),
        sa.ForeignKeyConstraint(["contact_id"], ["dd_contacts.id"]),
        sa.ForeignKeyConstraint(["session_id"], ["agent_sessions.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "session_id",
            "contact_id",
            "kind",
            name="uq_notification_attempt_session_contact_kind",
        ),
    )
    op.create_index("ix_notification_attempts_session_id", "notification_attempts", ["session_id"])
    op.create_index("ix_notification_attempts_contact_id", "notification_attempts", ["contact_id"])
    op.create_index(
        "ix_notification_attempts_provider_message_id",
        "notification_attempts",
        ["provider_message_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_notification_attempts_provider_message_id", table_name="notification_attempts")
    op.drop_index("ix_notification_attempts_contact_id", table_name="notification_attempts")
    op.drop_index("ix_notification_attempts_session_id", table_name="notification_attempts")
    op.drop_table("notification_attempts")
    op.drop_index("ix_contact_devices_contact_id", table_name="contact_devices")
    op.drop_table("contact_devices")

    with op.batch_alter_table("agent_sessions") as batch_op:
        batch_op.drop_column("notification_attempt_id")
        batch_op.drop_column("notification_status")

    with op.batch_alter_table("events") as batch_op:
        batch_op.drop_constraint(
            "fk_events_selected_contact_id_dd_contacts",
            type_="foreignkey",
        )
        batch_op.drop_column("selected_contact_id")

    op.drop_index("ix_dd_contacts_access_token_hash", table_name="dd_contacts")
    op.drop_index("ix_dd_contacts_invite_code", table_name="dd_contacts")
    with op.batch_alter_table("dd_contacts") as batch_op:
        batch_op.drop_column("updated_at")
        batch_op.drop_column("created_at")
        batch_op.drop_column("access_token_hash")
        batch_op.drop_column("sms_consent_at")
        batch_op.drop_column("sms_consent")
        batch_op.drop_column("accepted_at")
        batch_op.drop_column("invite_expires_at")
        batch_op.drop_column("invite_status")
        batch_op.drop_column("invite_code")

    op.drop_index("ix_users_access_token_hash", table_name="users")
    with op.batch_alter_table("users") as batch_op:
        batch_op.drop_column("access_token_hash")
