# 🌱 taskfarm — Config (GitOps / CD)

> taskfarm 의 **배포 매니페스트 + ArgoCD** 레포지토리
> ArgoCD가 이 레포를 **단일 진실 공급원(SSoT)** 으로 추적합니다.

![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D)
![Kustomize](https://img.shields.io/badge/Kustomize-base%2Foverlays-326CE5)
![KEDA](https://img.shields.io/badge/KEDA-autoscale-00B4E6)

---

## 📌 이 레포의 역할

쿠버네티스에 **무엇을 배포할지**를 선언적으로 관리합니다.
앱 코드는 [team4-taskfarm-app](#), 인프라는 [team4-taskfarm-infra](#).

> CI(app)가 이미지를 ECR에 올리고 이 레포의 **image tag를 갱신**하면,
> ArgoCD가 변경을 감지해 클러스터에 동기화합니다.

---

## 🗂 디렉터리 구조 (실제)

```
team4-taskfarm-config/
├── apps/                     # ── App-of-Apps (ArgoCD Application 정의) ──
│   ├── root-dev.yaml         #   dev 루트: user-dev/admin-dev/common 포함
│   ├── root-prod.yaml        #   prod 루트: user-prod/admin-prod/monitoring 포함
│   ├── user-dev.yaml  user-prod.yaml
│   ├── admin-dev.yaml admin-prod.yaml
│   ├── observability-dev.yaml  monitoring-prod.yaml
│   └── common.yaml           #   ClusterSecretStore 등 공통
│
├── manifests/                # ── 실제 K8s 매니페스트 (Kustomize) ──
│   ├── user/                 #   :8080  base + overlays(dev/prod)
│   │   ├── base/             #     deployment·service·configmap·sa·externalsecret
│   │   └── overlays/dev,prod #     patch(replicas/env)·ingress·externalsecret
│   ├── admin/                #   :8081  동일 구조
│   ├── common/               #   ClusterSecretStore (ESO)
│   ├── monitoring/           #   ServiceMonitor·KEDA ScaledObject·Grafana 대시보드·PrometheusRule
│   │   ├── base/  overlays/dev,prod
│   │   └── dashboards/       #     taskfarm/JVM/springboot/falco 대시보드 json
│   └── observability/
│       └── fargate-logging/dev  #  dev Fargate 로그 → CloudWatch (Fluent Bit)
│
├── load-test/                # k6 스크립트 (CPU 트리거 / 큐 트리거 데모)
├── scripts/                  # pre-commit 훅 (시크릿 커밋 차단)
└── docs/                     # pre-commit-hook.md 등
```

> **환경 차이는 브랜치가 아니라 overlays 디렉터리로.** (main 단일)
> user/admin은 base를 공유하고, dev/prod overlay가 image tag·replicas·ingress·ExternalSecret을 패치합니다.

---

## 🌳 ArgoCD App-of-Apps 구조

```
Terraform(infra) → ArgoCD 설치 + root Application 부트스트랩 (이 레포 apps/ 를 가리킴)
       ↓
apps/root-dev.yaml   → user-dev / admin-dev / common      (dev)
apps/root-prod.yaml  → user-prod / admin-prod / monitoring (prod)
       ↓
각 Application → manifests/{user,admin,monitoring,...}/overlays/{env} 동기화
```

- **root 하나만 부트스트랩**하면, 나머지 Application은 이 레포가 선언적으로 생성·관리
- `apps/root-dev.yaml`은 `apps/` 경로에서 `{user-dev,admin-dev,common}.yaml`만 include

---

## 🔄 배포 흐름

```
[app CI] 이미지 ECR push → 이 레포 manifests/{user,admin}/overlays/{env} image tag 갱신
       ↓
[ArgoCD] 변경 감지 (OutOfSync)
       ↓
dev  : 자동 동기화 (automated: prune + selfHeal)
prod : 이미지 태그 변경 PR + 승인으로 승격 (승인 게이트)
       ↓
EKS Rolling Update → readinessProbe 통과 → 트래픽 전환 → Slack 알림
```

- **dev:** auto-sync + prune + selfHeal (root-dev.yaml에 명시)
- **prod:** 승인 게이트 (실수 배포 방지)

---

## ⚡ 오토스케일 (KEDA)

`manifests/monitoring/` 의 **ScaledObject**가 user Pod를 스케일합니다.

- **듀얼 트리거**: ① Redis 큐 `listLength ≥ 10` (AI 추천 적체) ② CPU 70%
- **대상**: user만 스케일 / admin 고정
- **환경 차등**: overlay가 base를 덮음 → **dev max 2 / prod max 5**
- dev/prod의 Redis 주소는 `overlays/{env}/keda-redis-address-patch.yaml`로 주입

---

## 🔑 ExternalSecret (ESO)

- Secrets Manager의 **Gemini API 키·DB 자격증명·Grafana·Slack** 을 K8s Secret으로 동기화
- `manifests/common/clustersecretstore.yaml` = ClusterSecretStore (클러스터 단위)
- 각 앱의 `overlays/{env}/externalsecret.yaml` = 실제 참조(remoteRef)

```yaml
# 값이 아니라 "참조"만 이 레포에 존재
# ClusterSecretStore → Secrets Manager path 지정
# ExternalSecret → remoteRef 로 특정 키 매핑 → K8s Secret 생성
```

> ⚠️ **실제 키 값·비밀번호는 절대 이 레포에 커밋 금지.** ARN/path 참조만.

---

## 📊 관측성 매니페스트

- `servicemonitor-user.yaml` / `servicemonitor-admin.yaml` — Prometheus scrape 대상
- `dashboards/` — Grafana 대시보드(taskfarm·JVM·Spring Boot APM·Falco)
- `overlays/prod/prometheusrule-taskfarm.yaml` — SLI 알람 규칙(5xx 등)
- `overlays/prod/ingress-grafana.yaml`, `ingress-argocd.yaml` — prod 노출
- `observability/fargate-logging/dev` — **dev는 Fargate**라 노드 DaemonSet 대신 Fargate 로깅 설정으로 CloudWatch 전송

---

## ⚠️ 운영 주의

- ArgoCD에서 **destroy/삭제 전 반드시 `kubectl delete ingress` 먼저** (LBC가 만든 ALB 정리, 안 그러면 VPC destroy 막힘)
- **prod 동기화는 항상 승인 거쳐서.** prod에 자동 sync 켜지 말 것.
- 18시 이후 kubectl 차단 — 동기화 작업은 그 전에.
- ServiceMonitor의 label은 kube-prometheus-stack의 **release label과 일치**시킬 것 (안 그러면 scrape 안 됨).

---

## 🧰 배포/확인 명령어 (참고)

```bash
# ArgoCD Application 상태
kubectl get applications -n argocd

# 특정 앱 동기화 상태/헬스
kubectl get application taskfarm-root-dev -n argocd -o wide

# Kustomize 렌더 미리보기 (실제 배포 전 검증)
kubectl kustomize manifests/user/overlays/dev
kubectl kustomize manifests/admin/overlays/prod

# KEDA ScaledObject 확인
kubectl get scaledobject -A
```

---

## 📐 매니페스트 컨벤션

- **환경 차이는 overlays로**, base는 공통만
- Ingress에 `Team=team4` 태그 annotation 포함
- ServiceMonitor label = 프로메테우스 release label 일치
- 시크릿은 ExternalSecret 참조만, 평문 금지 (pre-commit 훅으로 커밋 차단)
