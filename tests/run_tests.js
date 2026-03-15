#!/usr/bin/env node

"use strict";

const https    = require("https");
const http     = require("http");
const { URL }  = require("url");

// ── CLI / env config ──────────────────────────────────────────────────────────
function getArg(flag, envVar) {
  const idx = process.argv.indexOf(flag);
  return idx !== -1 ? process.argv[idx + 1] : process.env[envVar] || "";
}

const config = {
  userPoolId:  getArg("--user-pool-id", "COGNITO_USER_POOL_ID"),
  clientId:    getArg("--client-id",    "COGNITO_CLIENT_ID"),
  username:    getArg("--username",     "COGNITO_USERNAME"),
  password:    getArg("--password",     "COGNITO_PASSWORD"),
  // Trim trailing slash so we never end up with double slashes in URLs
  apiUsEast1:  getArg("--api-us", "API_URL_US_EAST_1").replace(/\/$/, ""),
  apiEuWest1:  getArg("--api-eu", "API_URL_EU_WEST_1").replace(/\/$/, ""),
};

// Validate required fields
const missing = Object.entries(config)
  .filter(([, v]) => !v)
  .map(([k]) => k);

if (missing.length) {
  console.error(`\n  Missing required config: ${missing.join(", ")}`);
  console.error("    Set via CLI flags or environment variables.\n");
  process.exit(1);
}

// ── ANSI colours ──────────────────────────────────────────────────────────────
const c = {
  reset:  "\x1b[0m",
  bold:   "\x1b[1m",
  green:  "\x1b[32m",
  red:    "\x1b[31m",
  yellow: "\x1b[33m",
  cyan:   "\x1b[36m",
  dim:    "\x1b[2m",
};

function pass(msg) { console.log(`  ${c.green}✔${c.reset}  ${msg}`); }
function fail(msg) { console.log(`  ${c.red}✘${c.reset}  ${msg}`); }
function info(msg) { console.log(`  ${c.cyan}ℹ${c.reset}  ${msg}`); }

// ── Generic HTTPS request helper ──────────────────────────────────────────────
function request(method, url, headers = {}, body = null) {
  return new Promise((resolve, reject) => {
    const parsed  = new URL(url);
    const lib     = parsed.protocol === "https:" ? https : http;
    const options = {
      hostname: parsed.hostname,
      port:     parsed.port || (parsed.protocol === "https:" ? 443 : 80),
      path:     parsed.pathname + parsed.search,
      method,
      headers:  { "Content-Type": "application/json", ...headers },
    };

    const start = Date.now();
    const req   = lib.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        const latency = Date.now() - start;
        let parsed;
        try   { parsed = JSON.parse(data); }
        catch { parsed = data; }
        resolve({ status: res.statusCode, body: parsed, latency });
      });
    });

    req.on("error", reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// ── Step 1 – Cognito authentication (USER_PASSWORD_AUTH) ──────────────────────
async function getJwt() {
  console.log(`\n${c.bold}═══ Step 1: Cognito Authentication ═══${c.reset}`);
  info(`Authenticating as ${config.username} …`);

  // Cognito InitiateAuth endpoint (no SDK needed – plain HTTPS POST)
  const endpoint = `https://cognito-idp.us-east-1.amazonaws.com/`;
  const payload  = {
    AuthFlow:       "USER_PASSWORD_AUTH",
    ClientId:       config.clientId,
    AuthParameters: {
      USERNAME: config.username,
      PASSWORD: config.password,
    },
  };

  const res = await request(
    "POST",
    endpoint,
    {
      "X-Amz-Target": "AWSCognitoIdentityProviderService.InitiateAuth",
      "Content-Type": "application/x-amz-json-1.1",
    },
    payload
  );

  if (res.status !== 200 || !res.body?.AuthenticationResult?.IdToken) {
    console.error(`${c.red}Cognito auth failed (HTTP ${res.status}):${c.reset}`, res.body);
    process.exit(1);
  }

  const token = res.body.AuthenticationResult.IdToken;
  pass(`JWT obtained (${token.length} chars, latency: ${res.latency} ms)`);
  return token;
}

// ── Step 2 – Concurrent /greet calls ─────────────────────────────────────────
async function testGreet(jwt) {
  console.log(`\n${c.bold}═══ Step 2: Concurrent GET /greet ═══${c.reset}`);

  const endpoints = [
    { label: "us-east-1", url: `${config.apiUsEast1}/greet`, expectedRegion: "us-east-1" },
    { label: "eu-west-1", url: `${config.apiEuWest1}/greet`, expectedRegion: "eu-west-1" },
  ];

  const results = await Promise.all(
    endpoints.map(async ({ label, url, expectedRegion }) => {
      info(`[${label}] → ${url}`);
      const res = await request("GET", url, { Authorization: jwt });
      return { label, expectedRegion, ...res };
    })
  );

  let allPassed = true;
  for (const r of results) {
    const actualRegion = r.body?.region;
    const ok = r.status === 200 && actualRegion === r.expectedRegion;
    if (ok) {
      pass(
        `[${r.label}] HTTP ${r.status} | region="${actualRegion}" ✓ | latency: ${c.bold}${r.latency} ms${c.reset}`
      );
    } else {
      fail(
        `[${r.label}] HTTP ${r.status} | expected region="${r.expectedRegion}", got "${actualRegion}" | latency: ${r.latency} ms`
      );
      console.log(`        ${c.dim}Response:${c.reset}`, JSON.stringify(r.body, null, 2));
      allPassed = false;
    }
  }

  // Latency comparison
  if (results.length === 2 && results.every((r) => r.status === 200)) {
    const diff = Math.abs(results[0].latency - results[1].latency);
    info(
      `Geographic latency delta: ${c.yellow}${diff} ms${c.reset}` +
      ` (${results[0].label}=${results[0].latency}ms vs ${results[1].label}=${results[1].latency}ms)`
    );
  }

  return allPassed;
}

// ── Step 3 – Concurrent /dispatch calls ──────────────────────────────────────
async function testDispatch(jwt) {
  console.log(`\n${c.bold}═══ Step 3: Concurrent POST /dispatch ═══${c.reset}`);

  const endpoints = [
    { label: "us-east-1", url: `${config.apiUsEast1}/dispatch`, expectedRegion: "us-east-1" },
    { label: "eu-west-1", url: `${config.apiEuWest1}/dispatch`, expectedRegion: "eu-west-1" },
  ];

  const results = await Promise.all(
    endpoints.map(async ({ label, url, expectedRegion }) => {
      info(`[${label}] → ${url}`);
      const res = await request("POST", url, { Authorization: jwt }, {});
      return { label, expectedRegion, ...res };
    })
  );

  let allPassed = true;
  for (const r of results) {
    const actualRegion = r.body?.region;
    const ok = r.status === 200 && actualRegion === r.expectedRegion;
    if (ok) {
      pass(
        `[${r.label}] HTTP ${r.status} | region="${actualRegion}" ✓ | latency: ${c.bold}${r.latency} ms${c.reset}`
      );
      info(`  ECS taskArn: ${r.body?.taskArn}`);
    } else {
      fail(
        `[${r.label}] HTTP ${r.status} | expected region="${r.expectedRegion}", got "${actualRegion}" | latency: ${r.latency} ms`
      );
      console.log(`        ${c.dim}Response:${c.reset}`, JSON.stringify(r.body, null, 2));
      allPassed = false;
    }
  }

  if (results.length === 2 && results.every((r) => r.status === 200)) {
    const diff = Math.abs(results[0].latency - results[1].latency);
    info(
      `Geographic latency delta: ${c.yellow}${diff} ms${c.reset}` +
      ` (${results[0].label}=${results[0].latency}ms vs ${results[1].label}=${results[1].latency}ms)`
    );
  }

  return allPassed;
}

// ── Main ──────────────────────────────────────────────────────────────────────
(async () => {
  console.log(`\n${c.bold}${c.cyan}╔══════════════════════════════════════╗`);
  console.log(`║   AWS Assessment – E2E Test Suite    ║`);
  console.log(`╚══════════════════════════════════════╝${c.reset}`);
  console.log(`  Regions : us-east-1 + eu-west-1`);
  console.log(`  User    : ${config.username}`);
  console.log(`  Date    : ${new Date().toISOString()}`);

  const jwt = await getJwt();

  const greetPassed    = await testGreet(jwt);
  const dispatchPassed = await testDispatch(jwt);

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log(`\n${c.bold}═══ Summary ═══${c.reset}`);
  if (greetPassed && dispatchPassed) {
    console.log(`\n  ${c.green}${c.bold}All tests PASSED ✔${c.reset}\n`);
    process.exit(0);
  } else {
    console.log(`\n  ${c.red}${c.bold}Some tests FAILED ✘${c.reset}\n`);
    process.exit(1);
  }
})();