import { documentation, documentationImages } from "./docs-generated.mjs";
import { docsStyles } from "./docs-styles.mjs";
import { docsScript } from "./docs-client.mjs";
import { home as page, setups, packPage, submit, editor } from "./studio-pages.mjs";
import { styles } from "./studio-styles.mjs";
import { catalog } from "./releases.mjs";
import { installPage } from "./install-page.mjs";
import { studioAssets } from "./studio-generated.mjs";

const SECURITY = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
  "Strict-Transport-Security": "max-age=31536000",
};

function respond(body, status = 200, type = "application/json; charset=utf-8", extra = {}) {
  return new Response(body, { status, headers: { ...SECURITY,
    "Content-Type": type, "Cache-Control": "public, max-age=60", ...extra } });
}

function json(value, status = 200) {
  return respond(JSON.stringify(value), status, "application/json; charset=utf-8",
    status >= 500 ? { "Cache-Control": "no-store" } : {});
}

export function byteRange(header, size) {
  if (!header) return null;
  const match = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!match || (!match[1] && !match[2])) throw new RangeError("Invalid range");
  let start = match[1] ? Number(match[1]) : Math.max(0, size - Number(match[2]));
  let end = match[1] && match[2] ? Number(match[2]) : size - 1;
  if (![start, end].every(Number.isSafeInteger) || start < 0 || start >= size || end < start)
    throw new RangeError("Unsatisfiable range");
  end = Math.min(end, size - 1);
  return { offset: start, length: end - start + 1 };
}

function approvedArtifact(path) {
  return catalog.releases.flatMap(release => release.artifacts).find(item => item.path === path);
}

async function download(request, env, path) {
  const artifact = approvedArtifact(path);
  if (!artifact) return json({ error: "Download not found" }, 404);
  const object = await env.RELEASES.head(artifact.key);
  if (!object || object.size !== artifact.bytes || object.customMetadata?.sha256 !== artifact.sha256)
    return json({ error: "Download temporarily unavailable" }, 503);
  const headers = { ETag: '"' + artifact.sha256 + '"', "Accept-Ranges": "bytes",
    "Content-Disposition": 'attachment; filename="' + artifact.filename + '"',
    "Cache-Control": "public, max-age=31536000, immutable" };
  const tags = request.headers.get("If-None-Match")?.split(",").map(v => v.trim().replace(/^W\//, "")) || [];
  if (tags.includes("*") || tags.includes(headers.ETag))
    return respond(null, 304, artifact.contentType, headers);
  let range;
  try {
    const ifRange = request.headers.get("If-Range");
    range = request.method === "HEAD" || (ifRange && ifRange !== headers.ETag)
      ? null : byteRange(request.headers.get("Range"), object.size);
  } catch {
    return respond(null, 416, artifact.contentType, { ...headers, "Content-Range": "bytes */" + object.size });
  }
  headers["Content-Length"] = String(range?.length ?? object.size);
  if (range) headers["Content-Range"] = "bytes " + range.offset + "-" +
    (range.offset + range.length - 1) + "/" + object.size;
  if (request.method === "HEAD") return respond(null, 200, artifact.contentType, headers);
  const content = await env.RELEASES.get(artifact.key, { onlyIf: { etagMatches: object.etag }, ...(range ? { range } : {}) });
  if (!content || !("body" in content)) return json({ error: "Download changed; retry" }, 503);
  return respond(content.body, range ? 206 : 200, artifact.contentType, headers);
}

async function worldAsset(request, env) {
  const asset = await env.ASSETS.fetch(request);
  const headers = new Headers(asset.headers);
  for (const [name, value] of Object.entries(SECURITY)) headers.set(name, value);
  headers.set("Cache-Control", asset.ok || asset.status === 304
    ? "public, max-age=31536000, immutable" : "no-store");
  return new Response(asset.body, { status: asset.status, headers });
}

async function route(request, env) {
  if (!["GET", "HEAD"].includes(request.method))
    return respond(null, 405, "text/plain", { Allow: "GET, HEAD", "Cache-Control": "no-store" });
  const url = new URL(request.url);
  if (url.hostname === "www.rikwow.com")
    return Response.redirect("https://rikwow.com" + url.pathname + url.search, 308);
  if (url.pathname === "/") return respond(page, 200, "text/html; charset=utf-8",
    { "Cache-Control": "public, max-age=60, no-transform" });
  if (url.pathname === "/install") return respond(installPage(),200,"text/html; charset=utf-8");
  if (url.pathname === "/install/") return Response.redirect(url.origin+"/install",308);
  const preview = (env.STUDIO_PREVIEW === true || env.STUDIO_PREVIEW === "true") && ["localhost","127.0.0.1","[::1]"].includes(url.hostname);
  if (!preview && (url.pathname === "/studio" || url.pathname === "/studio/" || url.pathname === "/setups" || url.pathname.startsWith("/setups/") || url.pathname.replace(/\/$/,"") === "/docs/setup-studio"))
    return Response.redirect(url.origin+"/docs/options",302);
  if (url.pathname === "/studio") return respond(editor,200,"text/html; charset=utf-8");
  if (url.pathname === "/setups") return respond(setups,200,"text/html; charset=utf-8");
  if (url.pathname === "/setups/submit") return respond(submit,200,"text/html; charset=utf-8");
  if (url.pathname.startsWith("/setups/")) { const html=packPage(url.pathname.slice(8));if(html)return respond(html,200,"text/html; charset=utf-8"); }
  if (new Set([...studioAssets,...documentationImages]).has(url.pathname)) return worldAsset(request, env);
  if (url.pathname.endsWith("/") && documentation[url.pathname.slice(0,-1)]) return Response.redirect(url.origin+url.pathname.slice(0,-1),308);
  if (Object.hasOwn(documentation,url.pathname)) {
    const source=new URL(documentation[url.pathname],url.origin);
    const asset=await env.ASSETS.fetch(new Request(source,request));
    if(!asset.ok && asset.status!==304)return json({error:"Documentation temporarily unavailable"},503);
    return respond(asset.body,asset.status,"text/html; charset=utf-8",{"Cache-Control":"public, max-age=60, no-transform",...(asset.headers.has("ETag")?{ETag:asset.headers.get("ETag")}:{})});
  }
  if (url.pathname === "/docs.css") return respond(docsStyles,200,"text/css; charset=utf-8");
  if (url.pathname === "/docs.js") return respond(docsScript,200,"text/javascript; charset=utf-8");
  if (url.pathname === "/site.css") return respond(styles, 200, "text/css; charset=utf-8");
  if (url.pathname === "/healthz") return json({ status: "ok", service: "rik-wow-site" });
  if (url.pathname === "/api/v1/releases") return json(catalog);
  if (url.pathname.startsWith("/downloads/")) return download(request, env, url.pathname);
  if (url.pathname === "/robots.txt") return respond("User-agent: *\nAllow: /\n", 200, "text/plain");
  return json({ error: "Not found" }, 404);
}

export default {
  async fetch(request, env) {
    try {
      const response = await route(request, env);
      return request.method === "HEAD"
        ? new Response(null, { status: response.status, headers: response.headers }) : response;
    } catch (error) {
      console.error(JSON.stringify({ event: "request_failed", name: error?.name || "Error" }));
      return respond(request.method === "HEAD" ? null : '{"error":"Service temporarily unavailable"}',
        503, "application/json", { "Cache-Control": "no-store" });
    }
  },
};
