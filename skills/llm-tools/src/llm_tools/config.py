from __future__ import annotations

import os
import tomllib
from pathlib import Path

from pydantic import BaseModel, Field, field_validator


CONFIG_PATHS = [
    Path.cwd() / ".llm-tools.toml",
    Path(os.environ.get("LLM_TOOLS_CONFIG", "")) if os.environ.get("LLM_TOOLS_CONFIG") else None,
    Path.home() / ".config" / "llm-tools" / "config.toml",
]


class ProviderConfig(BaseModel):
    base_url: str
    api_key_env: str | None = None
    default_model: str
    extra_headers: dict[str, str] = Field(default_factory=dict)

    @field_validator("api_key_env")
    @classmethod
    def _no_secret_in_env_name(cls, v: str | None) -> str | None:
        if v is None:
            return v
        if v.startswith(("sk-", "sk_", "Bearer ")) or len(v) > 64:
            raise ValueError(
                "api_key_env should be the NAME of an environment variable "
                "(e.g. \"KIMI_API_KEY\"), not the secret itself. The current value "
                "looks like an actual API key. Set the key in your shell rc "
                "(`export KIMI_API_KEY=sk-...`) and put the variable name here."
            )
        if not v.replace("_", "").isalnum():
            raise ValueError(
                f"api_key_env={v!r} is not a valid env-var name (letters, digits, underscores only)."
            )
        return v


class TaskRouting(BaseModel):
    provider: str
    model: str | None = None
    max_tokens: int | None = None
    temperature: float | None = None


class Config(BaseModel):
    providers: dict[str, ProviderConfig]
    routing: dict[str, TaskRouting] = Field(default_factory=dict)

    def resolve(self, task: str, provider_override: str | None, model_override: str | None) -> tuple[ProviderConfig, str]:
        provider_name = provider_override
        model = model_override
        if provider_name is None:
            route = self.routing.get(task)
            if route is None:
                raise SystemExit(
                    f"No routing configured for task '{task}' and no --provider given. "
                    f"Add [routing.{task}] to your config or pass --provider."
                )
            provider_name = route.provider
            if model is None:
                model = route.model

        if provider_name not in self.providers:
            raise SystemExit(
                f"Unknown provider '{provider_name}'. Configured: {sorted(self.providers)}"
            )
        provider = self.providers[provider_name]
        if model is None:
            model = provider.default_model
        return provider, model


def load_config() -> Config:
    for candidate in CONFIG_PATHS:
        if candidate is None:
            continue
        if candidate.exists():
            with candidate.open("rb") as fh:
                data = tomllib.load(fh)
            return Config.model_validate(data)
    raise SystemExit(
        "No llm-tools config found. Create ~/.config/llm-tools/config.toml "
        "(see config.example.toml in the llm-tools repo) or set LLM_TOOLS_CONFIG."
    )


def get_api_key(provider: ProviderConfig) -> str:
    if provider.api_key_env is None:
        return "not-needed"
    key = os.environ.get(provider.api_key_env)
    if not key:
        raise SystemExit(
            f"Environment variable '{provider.api_key_env}' is not set "
            f"(needed for provider with base_url={provider.base_url})."
        )
    return key
