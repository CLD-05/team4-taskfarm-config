# 🌱 taskfarm — Config (GitOps / CD)

> taskfarm 의 **배포 매니페스트 + ArgoCD** 레포지토리
> ArgoCD가 이 레포를 **단일 진실 공급원(SSoT)** 으로 추적합니다.

![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D)
![Kustomize](https://img.shields.io/badge/Kustomize-overlays-326CE5)

---

## 📌 이 레포의 역할

쿠버네티스에 **무엇을 배포할지**를 선언적으로 관리합니다.
앱 코드는 [team4-taskfarm-app](#), 인프라는 [team4-taskfarm-infra](#).

> CI(app)가 이미지를 ECR에 올리고 이 레포의 **image tag를 갱신**하면,
> ArgoCD가 변경을 감지해 클러스터에 동기화합니다.

---

## 🗂 디렉터리 구조

```
config/
├── base/                     # 환경 공통 매니페스트
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── serviceaccount.yaml
│   ├── ingress.yaml          # ALB annotation
│   └── kustomization.yaml
├── overlays/
│   ├── dev/                  # dev 전용 패치 (image tag, replicas 등)
│   │   └── kustomization.yaml
│   └── prod/                 # prod 전용 패치
│       └── kustomization.yaml
├── externalsecret/           # ESO용 ExternalSecret (Gemini 키 등)
└── argocd/
    └── application.yaml       # App of Apps (root)
```

> **환경 차이는 브랜치가 아니라 overlays 디렉터리로.** (main 단일)

---

## 🔄 배포 흐름

```
[app CI] 이미지 ECR push → 이 레포 overlays/{env} image tag 갱신(PR/자동)
       ↓
[ArgoCD] 변경 감지
       ↓
dev  : 자동 동기화 (auto-sync)
prod : overlays/prod 이미지 태그 변경 PR + 승인으로 승격
```

- **dev:** 자동 sync + selfHeal
- **prod:** 승인 게이트 (실수 배포 방지)

---

## 🌳 ArgoCD App of Apps

```
Terraform(infra) → ArgoCD 설치 + root Application 1개 (이 레포 가리킴)
       ↓
root Application → 하위 Application 생성 (taskfarm-dev, taskfarm-prod, monitoring 등)
```

> root 하나만 부트스트랩하면, 나머지는 이 레포가 선언적으로 관리합니다.

---

## 🔑 ExternalSecret (ESO)

- Secrets Manager의 **Gemini API 키**를 K8s Secret으로 동기화
- 매니페스트는 이 레포에서 관리, 실제 키 값은 **Secrets Manager에만** (이 레포엔 참조만)

```yaml
# 예: externalsecret/gemini-key.yaml (값 아님, 참조만)
# - SecretStore: namespace 단위
# - remoteRef: Secrets Manager의 키 path
```

> ⚠️ **실제 키 값·비밀번호는 절대 이 레포에 커밋 금지.** ARN/path 참조만.

---

## ⚠️ 운영 주의

- ArgoCD에서 **destroy/삭제 전 반드시 `kubectl delete ingress` 먼저** (LBC가 만든 ALB 정리)
- prod 동기화는 항상 승인 거쳐서. 자동 sync 켜지 말 것.
- 18시 이후 kubectl 차단 — 동기화 작업은 그 전에.

---

## 📐 매니페스트 컨벤션

- ServiceMonitor의 label은 kube-prometheus-stack의 release label과 **일치**시킬 것 (안 그러면 scrape 안 됨)
- Ingress에 `Team=team4` 태그 annotation 포함
- 환경별 값은 overlays에서 패치, base는 공통만
