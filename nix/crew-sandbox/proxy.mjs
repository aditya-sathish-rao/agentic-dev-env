// The guest's only way out. A CONNECT proxy that refuses every destination the
// allowlist does not name, and logs every decision it makes.
//
// It holds no credentials and terminates no TLS: it forwards bytes. That keeps it
// small enough to reason about, and it means a compromised guest gains nothing
// from reaching it beyond the hosts listed in the allowlist.
import fs from "node:fs";
import http from "node:http";
import net from "node:net";

const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const at = argv.indexOf(name);
  return at >= 0 ? argv[at + 1] : fallback;
};

const port = Number(flag("--listen", "3128"));
const allowFile = flag("--allow");
if (!allowFile) {
  console.error("crew-proxy: --allow <file> is required");
  process.exit(2);
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

const server = http.createServer((req, res) => {
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
  console.error(`crew-proxy: listening on 127.0.0.1:${port} with ${rules.length} allowed hosts`);
});
