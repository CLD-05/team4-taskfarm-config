## 📌 유형
<!-- 해당하는 것에 x 표시 (예: [x]) -->
- [ ] feat: 매니페스트/Application 추가
- [ ] fix: 매니페스트 수정
- [ ] chore: 구조/설정 변경

## 🔍 무엇을 했나요?
<!-- 한두 줄로. 예: user base deployment/service 작성 -->


## 📂 대상
<!-- 건드린 범위에 x -->
- [ ] user (base / overlays)
- [ ] admin (base / overlays)
- [ ] apps (ArgoCD Application)

## ✅ 확인
<!-- config 레포는 ArgoCD가 자동 배포하므로, 빌드 검증이 가장 중요 -->
- [ ] `kubectl kustomize` 로 빌드 통과 (dev / prod overlay 둘 다)
- [ ] 이미지 태그를 직접 박지 않음 (overlay images / CI가 갱신)
- [ ] 시크릿을 평문으로 넣지 않음 (ESO/ExternalSecret 사용)
- [ ] base와 overlay의 리소스 이름·secret 참조 이름이 일치

## ⚠️ 참고 (선택)
<!-- 합의가 필요한 TODO(ECR 경로·SecretStore·엔드포인트 등)나
     리뷰어가 알아야 할 점이 있으면. 없으면 비워두세요 -->
