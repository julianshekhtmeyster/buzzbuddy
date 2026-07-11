from openai import OpenAI

from ..config import settings

client = OpenAI(base_url=settings.do_base_url, api_key=settings.digital_ocean_model_access_key or "not-set")
