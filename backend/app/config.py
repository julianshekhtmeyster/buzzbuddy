from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./buzzbuddy.db"

    digital_ocean_model_access_key: str = ""
    do_model_name: str = "anthropic-claude-4.6-sonnet"
    do_base_url: str = "https://inference.do-ai.run/v1/"

    # Separate DO GenAI Agent (with its own knowledge base) that answers DD
    # (designated driver) questions about a specific session. Distinct from
    # the examiner loop above -- different endpoint, different access key,
    # never used to make impairment decisions itself.
    dd_agent_endpoint: str = ""
    dd_agent_access_key: str = ""

    twilio_account_sid: str = ""
    twilio_api_key_sid: str = ""
    twilio_api_key_secret: str = ""
    twilio_from_number: str = ""


settings = Settings()
