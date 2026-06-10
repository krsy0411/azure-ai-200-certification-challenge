"""App Configuration 피처 플래그 로더 (session-05).

코드·컨테이너 재배포 없이 포털/CLI 의 피처 플래그 토글로 동작을 바꾼다.

- `azure-appconfiguration-provider` 의 `load()` 로 키/값 + Key Vault reference 자동 해석.
  Key Vault reference 는 `keyvault_credential` 로 해석되며, UAMI 의 Key Vault Secrets User
  역할(session-01 부여)을 사용한다.
- `featuremanagement` 의 `FeatureManager` 로 플래그 평가.
- 동적 새로 고침 — sentinel key 를 `refresh_on` 으로 감시하고, 피처 플래그는 별도로
  `feature_flag_refresh_enabled=True` 가 필요하다 (이게 빠지면 토글이 반영되지 않는 함정).
  자동 백그라운드 폴링이 아니므로 요청 핸들러에서 `refresh()` 를 호출해야 폴링이 일어난다.

인증은 본 워크샵 표준 Entra ID — endpoint + DefaultAzureCredential (연결 문자열 미사용).
"""

from azure.appconfiguration.provider import WatchKey
from azure.appconfiguration.provider.aio import load
from azure.identity.aio import DefaultAzureCredential
from featuremanagement import FeatureManager

from ..settings import Settings

# 이 키를 바꾸면 Provider 가 전체 설정을 새로 고친다 (Bicep 에서 등록).
_SENTINEL_KEY = "sentinel"
_REFRESH_INTERVAL_SECONDS = 30


class AppConfig:
    """App Configuration provider + 피처 플래그 평가 래퍼."""

    def __init__(self, provider, credential: DefaultAzureCredential) -> None:
        self._provider = provider
        self._credential = credential
        self._features = FeatureManager(provider)

    async def refresh(self) -> None:
        """sentinel/피처 플래그 변경을 폴링 주기에 맞춰 반영한다."""
        await self._provider.refresh()

    def is_enabled(self, flag: str) -> bool:
        return self._features.is_enabled(flag)

    async def close(self) -> None:
        await self._provider.close()
        await self._credential.close()


async def load_app_config(settings: Settings) -> AppConfig:
    """App Configuration 을 로드한다.

    호출자는 앱 종료 시 `app_config.close()` 를 책임진다 (main.py lifespan).
    """
    credential = DefaultAzureCredential()
    provider = await load(
        endpoint=settings.app_config_endpoint,
        credential=credential,
        keyvault_credential=credential,
        feature_flag_enabled=True,
        feature_flag_refresh_enabled=True,
        refresh_on=[WatchKey(_SENTINEL_KEY)],
        refresh_interval=_REFRESH_INTERVAL_SECONDS,
    )
    return AppConfig(provider, credential)
