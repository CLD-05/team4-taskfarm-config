import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 20 },
    { duration: '3m', target: 20 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
  },
};

const BASE_URL = __ENV.BASE_URL;
const HEALTH_PATH = __ENV.HEALTH_PATH || '/actuator/health';

export default function () {
  const res = http.get(`${BASE_URL}${HEALTH_PATH}`);

  check(res, {
    'status is 200': (r) => r.status === 200,
  });

  sleep(1);
}
