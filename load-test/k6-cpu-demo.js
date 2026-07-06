import http from 'k6/http';
import { check } from 'k6';

// ── CPU 트리거 시연용 (KEDA CPU 스케일아웃 유발) ──
// 기존 health 스크립트는 sleep(1) + 20VU라 CPU가 안 올라감.
// 시연용은 VU를 크게 + sleep 제거 + 무거운 엔드포인트로 CPU를 끌어올린다.
export const options = {
  stages: [
    { duration: '30s', target: 100 },   // 30초간 100VU까지 급증
    { duration: '3m',  target: 200 },   // 200VU로 3분 유지 (CPU 압박)
    { duration: '30s', target: 0 },     // 마무리
  ],
  // 시연이라 threshold는 느슨하게 (실패해도 부하는 계속)
};

const BASE_URL = __ENV.BASE_URL;

// health 대신 실제 로직이 도는 엔드포인트를 때려야 CPU가 오른다.
// 인증 불필요 + 처리 있는 경로 위주. 없으면 health로 폴백.
const PATHS = (__ENV.PATHS || '/actuator/health').split(',');

export default function () {
  // sleep 없음 → 최대 부하. 여러 경로 라운드로빈.
  const path = PATHS[Math.floor(Math.random() * PATHS.length)];
  const res = http.get(`${BASE_URL}${path}`);
  check(res, { 'status ok': (r) => r.status >= 200 && r.status < 500 });
}
