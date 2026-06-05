"""App Configuration 피처 플래그 로더 (session-05).

코드·컨테이너 재배포 없이 포털/CLI 의 피처 플래그 토글로 동작을 바꾼다.

- `azure-appconfiguration-provider` 의 `load()` 로 키/값 + Key Vault reference 자동 해석.
- `featuremanagement` 의 `FeatureManager` 로 플래그 평가.
- 동적 새로 고침 — sentinel key `refresh_on` + 피처 플래그는 별도 `feature_flag_refresh_enabled=True`.

본 파일은 시작본 stub 이다. anchor 주석을 따라 load_app_config 본체를 채운다.
완성본은 save-points/session-05/complete/ 또는 docs/sessions/05-app-config-flags.md 참고.
"""

from azure.appconfiguration.provider import WatchKey
from azure.appconfiguration.provider.aio import load
from azure.identity.aio import DefaultAzureCredential
from featuremanagement import FeatureManager

from ..settings import Settings

_SENTINEL_KEY = "sentinel"
_REFRESH_INTERVAL_SECONDS = 30


class AppConfig:
    """App Configuration provider + 피처 플래그 평가 래퍼."""

    def __init__(self, provider, credential: DefaultAzureCredential) -> None:
        self._provider = provider
        self._credential = credential
        self._features = FeatureManager(provider)

    async def refresh(self) -> None:
        await self._provider.refresh()

    def is_enabled(self, flag: str) -> bool:
        return self._features.is_enabled(flag)

    async def close(self) -> None:
        await self._provider.close()
        await self._credential.close()


async def load_app_config(settings: Settings) -> AppConfig:
    # 힌트: DefaultAzureCredential() 로 endpoint=settings.app_config_endpoint 에 load().
    # Key Vault reference 해석을 위해 keyvault_credential=credential 전달.
    # 동적 토글에는 네 가지가 모두 필요: feature_flags_enabled=True,
    # feature_flag_refresh_enabled=True, refresh_on=[WatchKey(_SENTINEL_KEY)],
    # refresh_interval=_REFRESH_INTERVAL_SECONDS. 그 뒤 AppConfig(provider, credential) 반환.
    raise NotImplementedError("load_app_config 를 구현하세요.")
