from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./buzzbuddy.db"

    digital_ocean_model_access_key: str = ""
    do_model_name: str = "anthropic-claude-4.6-sonnet"
    do_base_url: str = "https://inference.do-ai.run/v1/"

    twilio_account_sid: str = ""
    twilio_api_key_sid: str = ""
    twilio_api_key_secret: str = ""
    # Twilio signs callbacks with the Account Auth Token, not the API key secret.
    twilio_auth_token: str = ""
    twilio_from_number: str = ""

    # Public origin used for Twilio delivery callbacks, e.g. https://api.example.com.
    public_base_url: str = ""

    # Apple Push Notification service token credentials.
    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_bundle_id: str = ""
    # Supply exactly one of the private-key variants below. Literal `\\n`
    # sequences are expanded for secrets copied into deployment environment vars.
    apns_private_key: str = ""
    apns_private_key_base64: str = ""
    apns_private_key_path: str = ""

    contact_invite_ttl_hours: int = 168
    notification_timeout_seconds: float = 10.0
    # A worker must finish a provider request within this window. Expired
    # attempts become "ambiguous" instead of remaining stuck in-flight.
    notification_attempt_lease_seconds: int = 120


settings = Settings()
