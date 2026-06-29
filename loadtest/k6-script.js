// k6 load test for the ephemeral environments.
//
// Runs from the ephemeral-env workflow (action: cycle) against the URL passed
// in TARGET_URL. Point TARGET_URL at your application's public endpoint
// (an ALB/NLB hostname or ingress URL) once the app in app/ is deployed.
//
// Local run:  k6 run -e TARGET_URL=https://example.com loadtest/k6-script.js

import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  // Ramp to 50 virtual users, hold, then ramp down.
  stages: [
    { duration: "1m", target: 50 },
    { duration: "3m", target: 50 },
    { duration: "1m", target: 0 },
  ],
  // Fail the test (and therefore flag the run) if the service degrades.
  thresholds: {
    http_req_failed: ["rate<0.01"], // less than 1% errors
    http_req_duration: ["p(95)<500"], // 95th percentile under 500ms
  },
};

const target = __ENV.TARGET_URL;

export default function () {
  const res = http.get(target);
  check(res, { "status is 200": (r) => r.status === 200 });
  sleep(1);
}
