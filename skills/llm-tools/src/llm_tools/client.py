from __future__ import annotations

from openai import OpenAI

from .config import ProviderConfig, get_api_key


def make_client(provider: ProviderConfig) -> OpenAI:
    return OpenAI(
        base_url=provider.base_url,
        api_key=get_api_key(provider),
        default_headers=provider.extra_headers or None,
    )


def chat(
    provider: ProviderConfig,
    model: str,
    messages: list[dict],
    *,
    max_tokens: int = 4096,
    temperature: float = 0.2,
) -> str:
    client = make_client(provider)
    resp = client.chat.completions.create(
        model=model,
        messages=messages,
        max_tokens=max_tokens,
        temperature=temperature,
    )
    content = resp.choices[0].message.content
    if content is None:
        raise SystemExit(
            f"Empty response from {provider.base_url} (model={model}). "
            "Try raising --max-tokens; some 'thinking' models exhaust the budget on reasoning tokens alone."
        )
    return content
