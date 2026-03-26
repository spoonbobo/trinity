/**
 * file-upload – OpenClaw extension plugin
 *
 * Two HTTP endpoints for webchat file handling:
 *
 * 1. POST /__openclaw__/upload
 *    Upload files to the agent workspace (media/inbound/).
 *    Auth: Authorization: Bearer <gateway-token|user-jwt>
 *    Headers: Content-Type, X-File-Name
 *    Body: raw file bytes
 *    Response: { ok, path, name, size, contentType }
 *
 * Note: Media reads are served by nginx at /__openclaw__/media/ in this stack.
 */

import { IncomingMessage, ServerResponse } from "node:http";
import * as fs from "node:fs/promises";
import { createReadStream } from "node:fs";
import * as path from "node:path";
import * as crypto from "node:crypto";

const MAX_BYTES = 5 * 1024 * 1024; // 5 MB per file
const MAX_SERVE_BYTES = 50 * 1024 * 1024; // 50 MB per file serve
const UPLOAD_PATH = "/__openclaw__/upload";
const MEDIA_PREFIX = "/__openclaw__/media/";
const BROWSER_MEDIA_PREFIX = "/__openclaw__/browser-media/";

// Windows reserved device names to reject in filenames
const WINDOWS_RESERVED = /^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)/i;

const MIME_MAP: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".svg": "image/svg+xml",
  ".bmp": "image/bmp",
  ".tiff": "image/tiff",
  ".tif": "image/tiff",
  ".txt": "text/plain",
  ".json": "application/json",
  ".pdf": "application/pdf",
};

function resolveMime(filePath: string): string {
  const ext = path.extname(filePath).toLowerCase();
  return MIME_MAP[ext] ?? "application/octet-stream";
}

// ─── Shared helpers ────────────────────────────────────────────────────

/** Sanitize a filename: strip directory separators, dangerous chars, limit length, fallback. */
function sanitizeFilename(raw: string): string {
  // Strip slashes, backslash, colon, null bytes, and Unicode bidi overrides
  let name = raw.replace(/[/\\:\x00\u202E\u200F\u200E\u202A-\u202D]/g, "").trim();
  // Collapse whitespace
  name = name.replace(/\s+/g, " ");
  // Strip leading/trailing dots (hidden files, traversal)
  name = name.replace(/^\.+|\.+$/g, "");
  // Reject Windows reserved device names
  if (WINDOWS_RESERVED.test(name)) {
    name = `_${name}`;
  }
  if (name.length > 200) {
    const ext = path.extname(name);
    const base = path.basename(name, ext).slice(0, 200 - ext.length);
    name = base + ext;
  }
  return name || "upload";
}

/** Read the full request body into a Buffer, enforcing a byte limit. */
function readBody(req: IncomingMessage, maxBytes: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let total = 0;
    let settled = false;

    function onData(chunk: Buffer) {
      total += chunk.length;
      if (total > maxBytes) {
        settled = true;
        cleanup();
        req.destroy();
        reject(
          new Error(
            `File exceeds ${(maxBytes / 1024 / 1024).toFixed(0)}MB limit`
          )
        );
        return;
      }
      chunks.push(chunk);
    }

    function onEnd() {
      if (!settled) {
        settled = true;
        cleanup();
        resolve(Buffer.concat(chunks));
      }
    }

    function onError(err: Error) {
      if (!settled) {
        settled = true;
        cleanup();
        reject(err);
      }
    }

    function cleanup() {
      req.removeListener("data", onData);
      req.removeListener("end", onEnd);
      req.removeListener("error", onError);
    }

    req.on("data", onData);
    req.on("end", onEnd);
    req.on("error", onError);
  });
}

/** Send a JSON response with CORS headers. */
function jsonResponse(
  res: ServerResponse,
  status: number,
  body: Record<string, unknown>
) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  // Use restrictive CORS -- the nginx proxy handles same-origin
  res.setHeader("Access-Control-Allow-Origin", res.getHeader("X-Allowed-Origin") || "*");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type, X-File-Name"
  );
  res.setHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  res.end(JSON.stringify(body));
}

/** Resolve the workspace root directory. */
function resolveWorkspace(api: any): string {
  const workspace =
    api.config?.agents?.defaults?.workspace ??
    path.join(process.env.HOME ?? "/home/node", ".openclaw", "workspace");
  return api.resolvePath
    ? api.resolvePath(workspace)
    : workspace.replace(/^~/, process.env.HOME ?? "/home/node");
}

async function serveFileFromRoots(
  req: IncomingMessage,
  res: ServerResponse,
  api: any,
  log: any,
  prefix: string,
  roots: string[],
  options: { stripLeadingMediaPath?: boolean; logLabel?: string } = {}
): Promise<boolean> {
  if (req.method === "OPTIONS") {
    res.statusCode = 204;
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
    res.setHeader("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS");
    res.end();
    return true;
  }

  if (req.method !== "GET" && req.method !== "HEAD") {
    res.statusCode = 405;
    res.end("Method Not Allowed");
    return true;
  }

  if (!validateAuth(req, api)) {
    jsonResponse(res, 401, { ok: false, error: "Unauthorized" });
    return true;
  }

  const url = new URL(req.url ?? "/", "http://localhost");
  if (!url.pathname.startsWith(prefix)) {
    return false;
  }

  const rawRelative = url.pathname.slice(prefix.length);
  if (!rawRelative || rawRelative === "/") {
    res.statusCode = 400;
    res.end("Missing file path");
    return true;
  }

  let relative = rawRelative.replace(/^\/+/, "");
  if (options.stripLeadingMediaPath && relative.startsWith("media/")) {
    relative = relative.substring("media/".length);
  }
  if (
    !relative ||
    relative.includes("\x00") ||
    path.isAbsolute(relative) ||
    relative.split("/").some((segment) => segment === "." || segment === "..")
  ) {
    res.statusCode = 400;
    res.end("Invalid path");
    return true;
  }

  let resolvedPath = "";
  for (const root of roots) {
    const candidate = path.resolve(root, relative);
    const prefixWithSep = `${root}${path.sep}`;
    if (candidate !== root && !candidate.startsWith(prefixWithSep)) {
      continue;
    }

    try {
      const lstat = await fs.lstat(candidate);
      if (lstat.isSymbolicLink()) {
        res.statusCode = 403;
        res.end("Forbidden");
        return true;
      }
      if (!lstat.isFile()) {
        res.statusCode = 404;
        res.end("Not found");
        return true;
      }
      if (lstat.size > MAX_SERVE_BYTES) {
        res.statusCode = 413;
        res.end("File too large");
        return true;
      }

      resolvedPath = candidate;
      res.statusCode = 200;
      res.setHeader("Content-Type", resolveMime(candidate));
      res.setHeader("Content-Length", String(lstat.size));
      res.setHeader("Cache-Control", "no-cache");
      res.setHeader("Access-Control-Allow-Origin", "*");

      if (req.method === "HEAD") {
        res.end();
        return true;
      }

      const stream = createReadStream(candidate);
      stream.on("error", (err) => {
        log.error(
          `file-upload: ${options.logLabel ?? "media"} stream error ${relative}: ${err.message}`
        );
        if (!res.headersSent) {
          res.statusCode = 500;
          res.end("Internal error");
        } else {
          res.end();
        }
      });
      stream.pipe(res);
      return true;
    } catch (err: any) {
      if (err.code === "ENOENT") {
        continue;
      }
      log.error(
        `file-upload: ${options.logLabel ?? "media"} serve failed ${relative}: ${err.message}`
      );
      res.statusCode = 500;
      res.end("Internal error");
      return true;
    }
  }

  if (!resolvedPath) {
    res.statusCode = 404;
    res.end("Not found");
  }
  return true;
}

function extractBearerToken(req: IncomingMessage): string {
  const authHeader = req.headers["authorization"] ?? "";
  return authHeader.startsWith("Bearer ")
    ? authHeader.slice(7).trim()
    : "";
}

function timingSafeEqualString(a: string, b: string): boolean {
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  if (bufA.length !== bufB.length) {
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

function base64UrlToBuffer(input: string): Buffer {
  const normalized = input.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  return Buffer.from(padded, "base64");
}

function base64ToBase64Url(input: string): string {
  return input.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function validateGatewayToken(token: string, api: any): boolean {
  const expectedToken =
    api.config?.gateway?.auth?.token ??
    process.env.OPENCLAW_GATEWAY_TOKEN ??
    "";
  if (!token || !expectedToken) return false;
  return timingSafeEqualString(token, expectedToken);
}

function validateSupabaseJwt(token: string): boolean {
  const secret =
    process.env.SUPABASE_JWT_SECRET ??
    process.env.JWT_SECRET ??
    "";
  if (!token || !secret) return false;

  const parts = token.split(".");
  if (parts.length !== 3) return false;

  const [headerB64, payloadB64, signatureB64] = parts;

  try {
    const header = JSON.parse(base64UrlToBuffer(headerB64).toString("utf8")) as {
      alg?: string;
      typ?: string;
    };
    if (header.alg !== "HS256") return false;

    const payload = JSON.parse(base64UrlToBuffer(payloadB64).toString("utf8")) as {
      exp?: number;
    };
    if (typeof payload.exp !== "number") return false;
    if (Math.floor(Date.now() / 1000) >= payload.exp) return false;

    const signingInput = `${headerB64}.${payloadB64}`;
    const expectedSig = base64ToBase64Url(
      crypto.createHmac("sha256", secret).update(signingInput).digest("base64")
    );

    return timingSafeEqualString(signatureB64, expectedSig);
  } catch {
    return false;
  }
}

/**
 * Validate Authorization Bearer token.
 * Accepts either:
 * - gateway token (internal/system calls)
 * - user JWT signed by Supabase JWT secret (browser uploads)
 */
function validateAuth(req: IncomingMessage, api: any): boolean {
  const token = extractBearerToken(req);
  if (!token) return false;
  return validateGatewayToken(token, api) || validateSupabaseJwt(token);
}

// ─── Plugin registration ───────────────────────────────────────────────

export default function register(api: any) {
  const log = api.logger;

  // ── 1. POST /__openclaw__/upload  (file upload) ───────────────────

  api.registerHttpRoute({
    path: UPLOAD_PATH,
    auth: "plugin",
    match: "exact",
    handler: async (req: IncomingMessage, res: ServerResponse) => {
      // CORS preflight
      if (req.method === "OPTIONS") {
        res.statusCode = 204;
        res.setHeader("Access-Control-Allow-Origin", "*");
        res.setHeader(
          "Access-Control-Allow-Headers",
          "Authorization, Content-Type, X-File-Name"
        );
        res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
        res.end();
        return true;
      }

      if (req.method !== "POST") {
        jsonResponse(res, 405, { ok: false, error: "Method not allowed" });
        return true;
      }

      if (!validateAuth(req, api)) {
        jsonResponse(res, 401, { ok: false, error: "Unauthorized" });
        return true;
      }

      // Parse metadata from headers (single decode only)
      const rawFileName =
        (req.headers["x-file-name"] as string) ??
        (req.headers["x-filename"] as string) ??
        "upload";
      const fileName = sanitizeFilename(decodeURIComponent(rawFileName));
      const contentType =
        (req.headers["content-type"] as string) ?? "application/octet-stream";

      // Read body
      let body: Buffer;
      try {
        body = await readBody(req, MAX_BYTES);
      } catch (err: any) {
        jsonResponse(res, 413, {
          ok: false,
          error: err.message ?? "File too large",
        });
        return true;
      }

      if (body.length === 0) {
        jsonResponse(res, 400, { ok: false, error: "Empty body" });
        return true;
      }

      // Write to workspace/media/inbound/
      const resolvedWorkspace = resolveWorkspace(api);
      const inboundDir = path.join(resolvedWorkspace, "media", "inbound");

      try {
        await fs.mkdir(inboundDir, { recursive: true, mode: 0o700 });
      } catch (err: any) {
        log.error(`file-upload: failed to create inbound dir: ${err.message}`);
        jsonResponse(res, 500, {
          ok: false,
          error: "Failed to create upload directory",
        });
        return true;
      }

      // Use full UUID for better collision resistance
      const uuid = crypto.randomUUID();
      const ext = path.extname(fileName);
      const base = path.basename(fileName, ext);
      const safeId = `${base}---${uuid}${ext}`;
      const destPath = path.join(inboundDir, safeId);

      // Path traversal guard
      if (!destPath.startsWith(inboundDir)) {
        jsonResponse(res, 400, { ok: false, error: "Invalid filename" });
        return true;
      }

      try {
        await fs.writeFile(destPath, body, { mode: 0o600 });
      } catch (err: any) {
        log.error(`file-upload: write failed: ${err.message}`);
        jsonResponse(res, 500, {
          ok: false,
          error: "Failed to write file",
        });
        return true;
      }

      const relativePath = `media/inbound/${safeId}`;
      log.info(
        `file-upload: ${fileName} (${contentType}) -> ${relativePath} (${body.length} bytes)`
      );
      jsonResponse(res, 200, {
        ok: true,
        path: relativePath,
        name: fileName,
        size: body.length,
        contentType,
      });
      return true;
    },
  });

  api.registerHttpRoute({
    path: MEDIA_PREFIX,
    auth: "plugin",
    match: "prefix",
    handler: async (req: IncomingMessage, res: ServerResponse) => {
      const resolvedWorkspace = resolveWorkspace(api);
      const mediaRoot = path.join(resolvedWorkspace, "media");

      return serveFileFromRoots(req, res, api, log, MEDIA_PREFIX, [mediaRoot, resolvedWorkspace], {
        stripLeadingMediaPath: true,
        logLabel: "media",
      });
    },
  });

  api.registerHttpRoute({
    path: BROWSER_MEDIA_PREFIX,
    auth: "plugin",
    match: "prefix",
    handler: async (req: IncomingMessage, res: ServerResponse) => {
      const browserMediaRoot = path.join(
        process.env.HOME ?? "/home/node",
        ".openclaw",
        "media",
        "browser"
      );

      return serveFileFromRoots(req, res, api, log, BROWSER_MEDIA_PREFIX, [browserMediaRoot], {
        logLabel: "browser-media",
      });
    },
  });

  log.info(
    "file-upload: registered /__openclaw__/upload + /__openclaw__/media/ + /__openclaw__/browser-media/ endpoints"
  );
}
