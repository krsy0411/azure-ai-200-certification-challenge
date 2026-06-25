#!/usr/bin/env python
"""scripts/seed_app_config.py — App Configuration 설정값 시딩 (session-05).

본 챌린지의 App Configuration store 는 `disableLocalAuth: true` (액세스 키 비활성,
Entra ID + RBAC 만 허용) 로 배포된다. 이런 store 에 키/값·Key Vault 참조·피처
플래그를 **Bicep 으로** 넣으면, 배포자(사용자)의 `App Configuration Data Owner`
역할이 같은 배포 안에서 부여되는 데다 그 역할이 데이터플레인에 전파되는 데 수 분이
걸려, 첫 배포가 `Forbidden` 으로 깨진다. 그래서 store·역할은 Bicep 으로 만들고,
**설정값은 배포가 끝난 뒤 이 스크립트로 시딩**한다 (Entra 토큰 데이터플레인 쓰기).

RBAC 전파가 아직 안 끝났으면 `Forbidden` 이 날 수 있으므로, 전파될 때까지 재시도한다.

실행 (apps/api 의 의존성 환경 사용 — azure-appconfiguration 포함):

    uv run --project apps/api python scripts/seed_app_config.py

필요 환경변수:
    APP_CONFIG_ENDPOINT   App Configuration store 엔드포인트
    AOAI_ENDPOINT         Azure OpenAI 엔드포인트
    COSMOS_ENDPOINT       Cosmos DB 엔드포인트
    PG_HOST              PostgreSQL FQDN
    REDIS_HOST           Managed Redis 호스트
    KV_VAULT_URI         Key Vault vault URI (끝에 / 포함)
"""

from __future__ import annotations

import json
import os
import time

from azure.appconfiguration import AzureAppConfigurationClient, ConfigurationSetting
from azure.core.exceptions import HttpResponseError
from azure.identity import DefaultAzureCredential

# charset=utf-8 를 붙여 az CLI 가 만드는 것과 정확히 일치시킨다.
# 없으면 `az appconfig feature` 서브커맨드가 플래그를 인식하지 못한다 (content-type 정확 매칭).
_FF_CONTENT_TYPE = "application/vnd.microsoft.appconfig.ff+json;charset=utf-8"
_KVREF_CONTENT_TYPE = "application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8"

# RBAC 데이터플레인 전파 대기 — 배포 직후 역할이 아직 안 퍼졌으면 Forbidden 이 난다.
_RETRY_MAX_SECONDS = 600
_RETRY_INTERVAL_SECONDS = 20


def _env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"환경변수 {name} 가 필요합니다.")
    return value


def _feature_flag_value(flag_id: str, enabled: bool) -> str:
    # description·display_name 을 포함해야 az CLI 의 `az appconfig feature`
    # (list/show/enable/disable, docs 3 단계 토글 실험) 가 플래그를 인식한다.
    return json.dumps(
        {
            "id": flag_id,
            "description": "",
            "enabled": enabled,
            "conditions": {"client_filters": []},
            "display_name": None,
        }
    )


def _settings() -> list[ConfigurationSetting]:
    aoai = _env("AOAI_ENDPOINT")
    cosmos = _env("COSMOS_ENDPOINT")
    pg_host = _env("PG_HOST")
    redis_host = _env("REDIS_HOST")
    vault_uri = _env("KV_VAULT_URI")

    plain = {
        "aoai:endpoint": aoai,
        "cosmos:endpoint": cosmos,
        "pg:host": pg_host,
        "redis:host": redis_host,
        # sentinel — refresh_on 워치 키. 값이 바뀌면 provider 가 키/값을 다시 읽는다.
        "sentinel": "1",
    }
    items = [ConfigurationSetting(key=k, value=v) for k, v in plain.items()]

    # Key Vault 참조 — 값이 아니라 secret URI 포인터. provider 가 load() 시 자동 해석.
    items.append(
        ConfigurationSetting(
            key="secrets:aoai-endpoint",
            value=json.dumps({"uri": f"{vault_uri}secrets/aoai-endpoint"}),
            content_type=_KVREF_CONTENT_TYPE,
        )
    )

    # 피처 플래그 — semantic cache ON, pg backend OFF.
    items.append(
        ConfigurationSetting(
            key=".appconfig.featureflag/enable_semantic_cache",
            value=_feature_flag_value("enable_semantic_cache", True),
            content_type=_FF_CONTENT_TYPE,
        )
    )
    items.append(
        ConfigurationSetting(
            key=".appconfig.featureflag/enable_pg_backend",
            value=_feature_flag_value("enable_pg_backend", False),
            content_type=_FF_CONTENT_TYPE,
        )
    )
    return items


def main() -> None:
    endpoint = _env("APP_CONFIG_ENDPOINT")
    credential = DefaultAzureCredential()
    client = AzureAppConfigurationClient(base_url=endpoint, credential=credential)
    settings = _settings()

    print(f"App Configuration 시딩 — {len(settings)} 개 설정 → {endpoint}")
    deadline = time.monotonic() + _RETRY_MAX_SECONDS
    while True:
        try:
            for setting in settings:
                client.set_configuration_setting(setting)
            break
        except HttpResponseError as exc:
            # 403 = Data Owner 역할이 데이터플레인에 아직 전파되지 않음 — 잠시 후 재시도.
            if exc.status_code == 403 and time.monotonic() < deadline:
                print(
                    "  RBAC 전파 대기 중 (Forbidden) — "
                    f"{_RETRY_INTERVAL_SECONDS}s 후 재시도..."
                )
                time.sleep(_RETRY_INTERVAL_SECONDS)
                continue
            raise

    client.close()
    credential.close()
    print(f"완료 — 키/값 {len(settings) - 3} 개 + 피처 플래그 2 개 시딩.")


if __name__ == "__main__":
    main()
