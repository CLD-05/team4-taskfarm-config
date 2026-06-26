# Team4 pre-commit hook

## 목적

커밋 전에 로컬에서 기본 보안 검사를 수행하여 시크릿, tfvars, tfstate, 개인 키 파일 등이 Git에 올라가는 것을 방지한다.

GitHub Actions의 gitleaks 검사는 PR 또는 push 이후에 실행되므로, pre-commit hook은 로컬에서 1차로 실수를 막기 위한 용도이다.

## 설치 방법

레포 루트에서 아래 명령어를 실행한다.

```bash
bash scripts/install-hooks.sh