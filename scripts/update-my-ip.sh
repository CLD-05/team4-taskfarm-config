#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="ap-northeast-2"

validate_ipv4() {
  local ip="$1"

  ip="${ip//$'\r'/}"
  ip="${ip#"${ip%%[![:space:]]*}"}"
  ip="${ip%"${ip##*[![:space:]]}"}"

  [[ "$ip" =~ ^(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$ ]]
}

CONFIG_REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$CONFIG_REPO/.." && pwd)"
INFRA_REPO="$ROOT_DIR/team4-taskfarm-infra"

MEMBERS_FILE="$CONFIG_REPO/members-ip.json"
INGRESS_FILE="$CONFIG_REPO/manifests/admin/overlays/prod/ingress.yaml"
TFVARS_FILE="$INFRA_REPO/infra/envs/prod/infra/terraform.tfvars"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq가 필요합니다. Git Bash 기준으로 jq 설치 후 다시 실행하세요." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI가 필요합니다." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl이 필요합니다." >&2
  exit 1
fi

if [ ! -f "$MEMBERS_FILE" ]; then
  echo "members-ip.json 파일이 없습니다: $MEMBERS_FILE" >&2
  exit 1
fi

echo "AWS 사용자 확인 중..."

AWS_ARN="$(aws sts get-caller-identity --query Arn --output text --region "$AWS_REGION")"
echo "현재 AWS ARN: $AWS_ARN"

MEMBER="$(basename "$AWS_ARN" | sed 's/^team4-//')"

echo "감지된 멤버 식별자: $MEMBER"

if ! jq -e --arg member "$MEMBER" 'has($member)' "$MEMBERS_FILE" >/dev/null; then
  echo "members-ip.json에 해당 멤버가 없습니다: $MEMBER" >&2
  exit 1
fi

MY_IP="$(curl -s ifconfig.me)"
echo "감지된 현재 IP: $MY_IP"

if ! validate_ipv4 "$MY_IP"; then
  echo "IP 형식이 올바르지 않습니다: $MY_IP" >&2
  exit 1
fi

echo "members-ip.json 갱신 중..."
tmp="$(mktemp)"
jq --arg member "$MEMBER" --arg ip "$MY_IP" '.[$member] = $ip' "$MEMBERS_FILE" > "$tmp"
mv "$tmp" "$MEMBERS_FILE"

echo "팀원 IP 목록 검증 중..."

if jq -e 'to_entries[] | select(.value == "" or .value == null or .value == "0.0.0.0")' "$MEMBERS_FILE" >/dev/null; then
  echo "members-ip.json에 비어 있거나 기본값인 IP가 있습니다." >&2
  echo "팀원 전체 IP가 채워져 있어야 안전하게 갱신할 수 있습니다." >&2
  exit 1
fi

while IFS=$'\t' read -r member ip; do
  if ! validate_ipv4 "$ip"; then
    echo "members-ip.json에 잘못된 IP 형식이 있습니다: $member=$ip" >&2
    exit 1
  fi
done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' "$MEMBERS_FILE")

CIDRS_CSV="$(jq -r '[.[] + "/32"] | join(",")' "$MEMBERS_FILE")"
CIDRS_TFVARS="$(jq -r '[.[] + "/32"] | map("\"" + . + "\"") | join(", ")' "$MEMBERS_FILE")"

echo "생성된 CIDR 목록:"
echo "$CIDRS_CSV"

echo "admin ingress inbound-cidrs 갱신 중..."

if ! grep -q "alb.ingress.kubernetes.io/certificate-arn" "$INGRESS_FILE"; then
  echo "ingress.yaml에서 certificate-arn 항목을 찾을 수 없습니다. HTTPS 설정을 확인하세요." >&2
  exit 1
fi

if ! grep -q "alb.ingress.kubernetes.io/inbound-cidrs" "$INGRESS_FILE"; then
  echo "ingress.yaml에서 inbound-cidrs 항목을 찾을 수 없습니다." >&2
  exit 1
fi

sed -i.bak -E "s#^([[:space:]]*)alb.ingress.kubernetes.io/inbound-cidrs:.*#\1alb.ingress.kubernetes.io/inbound-cidrs: \"$CIDRS_CSV\"#" "$INGRESS_FILE"
rm -f "$INGRESS_FILE.bak"

echo "terraform.tfvars public_access_cidrs 갱신 중..."

if ! grep -q "public_access_cidrs" "$TFVARS_FILE"; then
  echo "terraform.tfvars에서 public_access_cidrs 항목을 찾을 수 없습니다." >&2
  exit 1
fi

sed -i.bak -E "s#^[[:space:]]*public_access_cidrs[[:space:]]*=[[:space:]]*\[.*\]#public_access_cidrs = [$CIDRS_TFVARS]#" "$TFVARS_FILE"
rm -f "$TFVARS_FILE.bak"

echo
echo "갱신 완료."
echo

echo "===== config repo diff ====="
cd "$CONFIG_REPO"
git diff -- manifests/admin/overlays/prod/ingress.yaml

echo
read -p "ingress.yaml 변경사항을 commit/push 할까요? (y/N): " PUSH_CONFIRM

if [[ "$PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
  git add manifests/admin/overlays/prod/ingress.yaml

  if git diff --cached --quiet; then
    echo "커밋할 변경사항이 없습니다."
  else
    git commit -m "chore: update admin access cidrs"
    git push
  fi
else
  echo "config repo commit/push를 건너뜁니다."
fi

echo
echo "===== infra repo diff ====="
cd "$INFRA_REPO"
git diff -- infra/envs/prod/infra/terraform.tfvars

echo
read -p "EKS public_access_cidrs 변경을 terraform apply 할까요? (y/N): " APPLY_CONFIRM

if [[ "$APPLY_CONFIRM" =~ ^[Yy]$ ]]; then
  cd "$INFRA_REPO/infra/envs/prod/infra"
  terraform plan -target=module.eks.aws_eks_cluster.main

  echo
  read -p "위 plan 확인 후 apply를 진행할까요? (y/N): " FINAL_APPLY_CONFIRM

  if [[ "$FINAL_APPLY_CONFIRM" =~ ^[Yy]$ ]]; then
    terraform apply -target=module.eks.aws_eks_cluster.main
  else
    echo "terraform apply를 취소했습니다."
  fi
else
  echo "terraform apply를 건너뜁니다."
fi