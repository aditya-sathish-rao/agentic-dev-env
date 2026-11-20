// The guest's only way out. A CONNECT proxy that refuses every destination the
// allowlist does not name, and logs every decision it makes.
//
// It holds no credentials for the allowlist route and terminates no TLS there: it
// forwards bytes, so a compromised guest gains nothing beyond the hosts named in
// the allowlist. The one exception is the model gateway below, which exists so the
// real model key can stay on the host.
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import https from "node:https";
import net from "node:net";

const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const at = argv.indexOf(name);
  return at >= 0 ? argv[at + 1] : fallback;
};

const port = Number(flag("--listen", "3128"));
const allowFile = flag("--allow");
const modelUpstream = flag("--model-upstream", "https://api.deepseek.com");
const keyHashOut = flag("--key-hash-out");
if (!allowFile) {
  console.error("crew-proxy: --allow <file> is required");
  process.exit(2);
}

// The model key and the guest's token are independent: the key comes from the
// vault when the proxy starts, the token is created inside the VM. Without both,
// the gateway is disabled rather than open.
const modelKey = process.env.DEEPSEEK_API_KEY;
const modelToken = process.env.CREW_MODEL_TOKEN;
const modelReady = Boolean(modelKey && modelToken);
if (keyHashOut) {
  const hash = modelKey ? crypto.createHash("sha256").update(modelKey).digest("hex") : "";
  fs.writeFileSync(keyHashOut, `${hash}\n`);
}

const rules = fs
  .readFileSync(allowFile, "utf8")
  .split("\n")
  .map((line) => line.split("#")[0].trim())
  .filter(Boolean);

const isAllowedHost = (hostname) => {
  const host = hostname.toLowerCase().replace(/\.$/, "");
  return rules.some((rule) =>
    rule.startsWith(".") ? host === rule.slice(1) || host.endsWith(rule) : host === rule,
  );
};

// Two ports, because that is all a package manager or a git remote ever needs.
// Anything else is a service the guest has no business reaching.
const isAllowedPort = (portNumber) => portNumber === 443 || portNumber === 80;

const log = (decision, target, from) =>
  console.error(`${new Date().toISOString()} ${decision} ${target} from ${from}`);

const splitTarget = (authority) => {
  const match = /^([a-z0-9.-]+)(?::(\d+))?$/i.exec(authority);
  if (!match) return undefined;
  return { hostname: match[1], port: Number(match[2] ?? 443) };
};

const deny = (socket, decision, target, from) => {
  log(decision, target, from);
  socket.end("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n");
};

// The model gateway. pi's models.json points the deepseek provider at
// http://host.lima.internal:3128/model, so the guest asks this route for
// completions and the real key is added here, in the one host process that has it.
// The route is closed unless both the vault key and the guest's token are present.
const modelPrefix = "/model";
const modelRoutes = new Map([
  ["GET /models", "/models"],
  ["POST /chat/completions", "/chat/completions"],
]);
const hopByHop = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
  "host",
  "authorization",
]);

const isModelRequest = (url) =>
  url === modelPrefix || url.startsWith(`${modelPrefix}/`) || url.startsWith(`${modelPrefix}?`);

const tokenMatches = (header) => {
  if (!modelToken || typeof header !== "string" || !header.startsWith("Bearer ")) return false;
  const given = Buffer.from(header.slice("Bearer ".length));
  const expected = Buffer.from(modelToken);
  return given.length === expected.length && crypto.timingSafeEqual(given, expected);
};

const replyJson = (response, status, payload) => {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(payload));
};

const handleModel = (request, response) => {
  const from = request.socket.remoteAddress;
  const route = new URL(request.url, "http://crew-model");
  const path = route.pathname.slice(modelPrefix.length);
  const label = `${request.method} ${path}`;

  if (!modelReady) {
    log("DENY", `model-disabled ${label}`, from);
    replyJson(response, 503, { error: "model gateway is disabled" });
    return;
  }
  if (!tokenMatches(request.headers.authorization)) {
    log("DENY", `model-auth ${label}`, from);
    replyJson(response, 401, { error: "unauthorized" });
    return;
  }
  const upstreamPath = modelRoutes.get(label);
  if (!upstreamPath) {
    log("DENY", `model-path ${label}`, from);
    replyJson(response, 404, { error: "not found" });
    return;
  }

  const target = new URL(upstreamPath, modelUpstream);
  const headers = { ...request.headers };
  for (const name of hopByHop) delete headers[name];
  headers.host = target.host;
  headers.authorization = `Bearer ${modelKey}`;

  const upstream = https.request(target, { method: request.method, headers }, (upstreamResponse) => {
    const responseHeaders = { ...upstreamResponse.headers };
    const responseHopByHop = [
      "connection",
      "keep-alive",
      "proxy-authenticate",
      "te",
      "trailer",
      "transfer-encoding",
      "upgrade",
    ];
    for (const name of responseHopByHop) delete responseHeaders[name];
    response.writeHead(upstreamResponse.statusCode, responseHeaders);
    upstreamResponse.pipe(response);
  });
  upstream.setTimeout(15 * 60 * 1000, () => upstream.destroy(new Error("upstream timeout")));
  upstream.on("error", () => {
    if (response.headersSent) response.destroy();
    else replyJson(response, 502, { error: "model upstream failed" });
  });
  request.pipe(upstream);
  response.on("close", () => {
    if (!upstream.destroyed) upstream.destroy();
  });
  log("ALLOW", `model ${label}`, from);
};

const server = http.createServer((req, res) => {
  if (isModelRequest(req.url)) {
    handleModel(req, res);
    return;
  }

  const from = req.socket.remoteAddress;
  let target;
  try {
    target = new URL(req.url);
  } catch {
    res.writeHead(400).end();
    return;
  }

  const targetPort = Number(target.port || 80);
  if (target.protocol !== "http:" || !isAllowedHost(target.hostname) || !isAllowedPort(targetPort)) {
    log("DENY", `${target.hostname}:${targetPort}`, from);
    res.writeHead(403).end();
    return;
  }

  log("ALLOW", `${target.hostname}:${targetPort}`, from);
  const upstream = http.request(
    {
      host: target.hostname,
      port: targetPort,
      method: req.method,
      path: `${target.pathname}${target.search}`,
      headers: req.headers,
    },
    (upstreamResponse) => {
      res.writeHead(upstreamResponse.statusCode, upstreamResponse.headers);
      upstreamResponse.pipe(res);
    },
  );
  upstream.on("error", () => res.writeHead(502).end());
  req.pipe(upstream);
});

server.on("connect", (req, socket, head) => {
  const from = req.socket.remoteAddress;
  const target = splitTarget(req.url);
  if (!target || !isAllowedHost(target.hostname) || !isAllowedPort(target.port)) {
    deny(socket, "DENY", req.url, from);
    return;
  }

  log("ALLOW", `${target.hostname}:${target.port}`, from);
  const upstream = net.connect(target.port, target.hostname, () => {
    socket.write("HTTP/1.1 200 Connection Established\r\n\r\n");
    upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });
  upstream.on("error", () => socket.destroy());
  socket.on("error", () => upstream.destroy());
});

server.listen(port, "127.0.0.1", () => {
  const model = modelReady ? `on ${modelUpstream}` : "disabled (no key or token)";
  console.error(
    `crew-proxy: listening on 127.0.0.1:${port} with ${rules.length} allowed hosts; model gateway ${model}`,
  );
});
