import { adminCorsHeaders, constantTimeEmailEquals, requireAdmin, signAdminToken, verifyPassword } from "./auth";
import {
  adminCreateWallpaper,
  adminDeleteCategoryCover,
  adminDeleteWallpaper,
  adminListWallpapers,
  adminSetCategoryCover,
  adminUpdateWallpaper,
  listCategoryCovers,
  listPublishedCatalog,
} from "./catalog";
import { handleAdReward, handleGenerate } from "./generate";
import { HttpError, json, readJsonBody } from "./http";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path.startsWith("/admin")) {
      const cors = adminCorsHeaders(request, env.ADMIN_ORIGINS);
      if (request.method === "OPTIONS") {
        return new Response(null, { status: cors ? 204 : 403, headers: cors ?? {} });
      }
      const response = await handleAdminRoute(request, env, path).catch(errorToResponse);
      if (cors) {
        for (const [k, v] of Object.entries(cors)) response.headers.set(k, v);
      }
      return response;
    }

    try {
      if (request.method === "GET" && path === "/catalog") {
        const rows = await listPublishedCatalog(env.DB);
        return json(rows, 200, { "Cache-Control": "public, max-age=60" });
      }
      if (request.method === "GET" && path === "/category-covers") {
        const rows = await listCategoryCovers(env.DB);
        return json(rows, 200, { "Cache-Control": "public, max-age=60" });
      }
      if (request.method === "GET" && path === "/ad-reward") {
        return await handleAdReward(request, env);
      }
      if (request.method === "POST" && path === "/generate") {
        return await handleGenerate(request, env);
      }
      if (request.method === "GET" && path === "/health") {
        return json({ ok: true });
      }
      return json({ error: "Not found." }, 404);
    } catch (error) {
      return errorToResponse(error);
    }
  },
} satisfies ExportedHandler<Env>;

async function handleAdminRoute(request: Request, env: Env, path: string): Promise<Response> {
  if (request.method === "POST" && path === "/admin/login") {
    const body = await readJsonBody(request);
    const email = typeof body.email === "string" ? body.email : "";
    const password = typeof body.password === "string" ? body.password : "";
    if (!env.ADMIN_EMAIL || !env.ADMIN_PASSWORD_HASH || !env.ADMIN_JWT_SECRET) {
      throw new HttpError("Admin auth is not configured.", 500);
    }
    const [emailOk, passwordOk] = await Promise.all([
      constantTimeEmailEquals(email, env.ADMIN_EMAIL),
      verifyPassword(password, env.ADMIN_PASSWORD_HASH),
    ]);
    if (!emailOk || !passwordOk) {
      throw new HttpError("Invalid email or password.", 401);
    }
    const { token, expiresAt } = await signAdminToken(env.ADMIN_EMAIL, env.ADMIN_JWT_SECRET);
    return json({ token, email: env.ADMIN_EMAIL, expiresAt });
  }

  const claims = await requireAdmin(request, env.ADMIN_JWT_SECRET);

  if (request.method === "GET" && path === "/admin/me") {
    return json({ ok: true, email: claims.sub });
  }
  if (request.method === "GET" && path === "/admin/wallpapers") {
    return json(await adminListWallpapers(env.DB));
  }
  if (request.method === "POST" && path === "/admin/wallpapers") {
    return json(await adminCreateWallpaper(env.DB, await readJsonBody(request)), 201);
  }
  if (path.startsWith("/admin/wallpapers/")) {
    const id = decodeURIComponent(path.slice("/admin/wallpapers/".length));
    if (!id) throw new HttpError("Missing wallpaper ID.", 400);
    if (request.method === "PATCH") {
      return json(await adminUpdateWallpaper(env.DB, id, await readJsonBody(request)));
    }
    if (request.method === "DELETE") {
      return json(await adminDeleteWallpaper(env.DB, id));
    }
  }
  if (request.method === "GET" && path === "/admin/category-covers") {
    return json(await listCategoryCovers(env.DB));
  }
  if (path.startsWith("/admin/category-covers/")) {
    const category = decodeURIComponent(path.slice("/admin/category-covers/".length));
    if (!category) throw new HttpError("Missing category.", 400);
    if (request.method === "PUT") {
      const body = await readJsonBody(request);
      const imagePath = typeof body.image_path === "string" ? body.image_path : "";
      return json(await adminSetCategoryCover(env.DB, category, imagePath));
    }
    if (request.method === "DELETE") {
      return json(await adminDeleteCategoryCover(env.DB, category));
    }
  }

  throw new HttpError("Not found.", 404);
}

function errorToResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return json({ error: error.message }, error.status);
  }
  console.error(
    JSON.stringify({
      event: "unhandled_error",
      error: error instanceof Error ? error.message : String(error),
    }),
  );
  return json({ error: "Generation is unavailable right now. Try again in a moment." }, 502);
}
