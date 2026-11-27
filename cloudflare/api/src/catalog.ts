import { HttpError } from "./http";

export interface WallpaperRow {
  id: string;
  kind: "live" | "still";
  title: string;
  category: string;
  video_path: string | null;
  image_path: string | null;
  thumbnail_path: string;
  duration_seconds: number | null;
  width: number;
  height: number;
  creator_name: string | null;
  creator_url: string | null;
  is_published: number | boolean;
  is_featured: number | boolean;
  is_category_cover: number | boolean;
  sort_order: number;
  created_at: string;
}

export interface CategoryCoverRow {
  category: string;
  image_path: string;
  updated_at?: string;
}

function toPublicWallpaper(row: WallpaperRow) {
  return {
    id: row.id,
    kind: row.kind,
    title: row.title,
    category: row.category,
    video_path: row.video_path,
    image_path: row.image_path,
    thumbnail_path: row.thumbnail_path,
    duration_seconds: row.duration_seconds,
    width: row.width,
    height: row.height,
    creator_name: row.creator_name,
    creator_url: row.creator_url,
    is_featured: Boolean(row.is_featured),
    is_category_cover: Boolean(row.is_category_cover),
    sort_order: row.sort_order,
    created_at: row.created_at,
  };
}

function toAdminWallpaper(row: WallpaperRow) {
  return {
    ...toPublicWallpaper(row),
    is_published: Boolean(row.is_published),
  };
}

export async function listPublishedCatalog(db: D1Database) {
  const { results } = await db
    .prepare(
      `SELECT id, kind, title, category, video_path, image_path, thumbnail_path, duration_seconds,
              width, height, creator_name, creator_url, is_featured, is_category_cover, sort_order, created_at
       FROM wallpapers
       WHERE is_published = 1
       ORDER BY sort_order ASC, created_at DESC`,
    )
    .all<WallpaperRow>();
  return results.map(toPublicWallpaper);
}

export async function listCategoryCovers(db: D1Database) {
  const { results } = await db
    .prepare(`SELECT category, image_path FROM category_covers ORDER BY category ASC`)
    .all<CategoryCoverRow>();
  return results;
}

export async function adminListWallpapers(db: D1Database) {
  const { results } = await db
    .prepare(
      `SELECT id, kind, title, category, video_path, image_path, thumbnail_path, duration_seconds,
              width, height, creator_name, creator_url, is_published, is_featured, is_category_cover,
              sort_order, created_at
       FROM wallpapers
       ORDER BY sort_order ASC, created_at DESC`,
    )
    .all<WallpaperRow>();
  return results.map(toAdminWallpaper);
}

export async function adminCreateWallpaper(db: D1Database, body: Record<string, unknown>) {
  const id = typeof body.id === "string" && body.id.trim() ? body.id.trim() : crypto.randomUUID();
  const kind = body.kind === "still" ? "still" : body.kind === "live" ? "live" : null;
  const title = typeof body.title === "string" ? body.title.trim() : "";
  const category = typeof body.category === "string" ? body.category.trim() : "";
  const videoPath = typeof body.video_path === "string" ? body.video_path : null;
  const imagePath = typeof body.image_path === "string" ? body.image_path : null;
  const thumbnailPath = typeof body.thumbnail_path === "string" ? body.thumbnail_path : "";
  const durationSeconds = typeof body.duration_seconds === "number" ? body.duration_seconds : null;
  const width = typeof body.width === "number" ? Math.trunc(body.width) : 0;
  const height = typeof body.height === "number" ? Math.trunc(body.height) : 0;
  const creatorName = typeof body.creator_name === "string" && body.creator_name.trim() ? body.creator_name.trim() : null;
  const creatorURL = typeof body.creator_url === "string" && body.creator_url.trim() ? body.creator_url.trim() : null;
  const isPublished = body.is_published === false ? 0 : 1;
  const isFeatured = body.is_featured === true ? 1 : 0;
  const isCategoryCover = body.is_category_cover === true ? 1 : 0;
  const sortOrder = typeof body.sort_order === "number" ? Math.trunc(body.sort_order) : 0;

  if (!kind || !title || title.length > 80 || !category || width <= 0 || height <= 0) {
    throw new HttpError("Invalid wallpaper payload.", 400);
  }

  try {
    const statements: D1PreparedStatement[] = [];
    if (isCategoryCover === 1) {
      statements.push(
        db.prepare(`UPDATE wallpapers SET is_category_cover = 0 WHERE category = ?1 AND is_category_cover = 1`).bind(category),
      );
    }
    statements.push(
      db
        .prepare(
          `INSERT INTO wallpapers (
             id, kind, title, category, video_path, image_path, thumbnail_path,
             duration_seconds, width, height, creator_name, creator_url,
             is_published, is_featured, is_category_cover, sort_order
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)`,
        )
        .bind(
          id,
          kind,
          title,
          category,
          videoPath,
          imagePath,
          thumbnailPath,
          durationSeconds,
          width,
          height,
          creatorName,
          creatorURL,
          isPublished,
          isFeatured,
          isCategoryCover,
          sortOrder,
        ),
    );
    await db.batch(statements);
    const created = await db.prepare(`SELECT * FROM wallpapers WHERE id = ?1`).bind(id).first<WallpaperRow>();
    if (!created) throw new HttpError("Failed to read created wallpaper.", 500);
    return toAdminWallpaper(created);
  } catch (error) {
    if (error instanceof HttpError) throw error;
    mapConstraintError(error);
  }
}

const PATCHABLE_STRING_OR_NULL = new Set(["creator_name", "creator_url"]);
const PATCHABLE_NONEMPTY_STRING = new Set(["title", "category", "thumbnail_path"]);
const PATCHABLE_BOOL = new Set(["is_published", "is_featured", "is_category_cover"]);

export async function adminUpdateWallpaper(db: D1Database, id: string, body: Record<string, unknown>) {
  const existing = await db.prepare(`SELECT * FROM wallpapers WHERE id = ?1`).bind(id).first<WallpaperRow>();
  if (!existing) {
    throw new HttpError("Not saved: the wallpaper is gone, or this account can't edit it. Reload and try again.", 404);
  }

  const sets: string[] = [];
  const params: unknown[] = [];
  let nextCategory = existing.category;
  let setsCategoryCoverTrue = false;

  for (const [key, value] of Object.entries(body)) {
    if (PATCHABLE_NONEMPTY_STRING.has(key)) {
      if (typeof value !== "string" || !value.trim()) throw new HttpError(`Invalid ${key}.`, 400);
      if (key === "category") nextCategory = value.trim();
      params.push(value.trim());
      sets.push(`${key} = ?${params.length}`);
    } else if (PATCHABLE_STRING_OR_NULL.has(key)) {
      if (value !== null && typeof value !== "string") throw new HttpError(`Invalid ${key}.`, 400);
      const cleaned = typeof value === "string" && value.trim() ? value.trim() : null;
      params.push(cleaned);
      sets.push(`${key} = ?${params.length}`);
    } else if (PATCHABLE_BOOL.has(key)) {
      if (typeof value !== "boolean") throw new HttpError(`Invalid ${key}.`, 400);
      if (key === "is_category_cover" && value) setsCategoryCoverTrue = true;
      params.push(value ? 1 : 0);
      sets.push(`${key} = ?${params.length}`);
    } else if (key === "sort_order") {
      if (typeof value !== "number" || !Number.isFinite(value)) throw new HttpError("Invalid sort_order.", 400);
      params.push(Math.trunc(value));
      sets.push(`sort_order = ?${params.length}`);
    }
  }

  if (sets.length === 0) return { id };

  try {
    const statements: D1PreparedStatement[] = [];
    if (setsCategoryCoverTrue) {
      statements.push(
        db
          .prepare(`UPDATE wallpapers SET is_category_cover = 0 WHERE category = ?1 AND id != ?2 AND is_category_cover = 1`)
          .bind(nextCategory, id),
      );
    }
    params.push(id);
    statements.push(db.prepare(`UPDATE wallpapers SET ${sets.join(", ")} WHERE id = ?${params.length}`).bind(...params));
    await db.batch(statements);
    return { id };
  } catch (error) {
    mapConstraintError(error);
  }
}

export async function adminDeleteWallpaper(db: D1Database, id: string) {
  const row = await db.prepare(`DELETE FROM wallpapers WHERE id = ?1 RETURNING id`).bind(id).first<{ id: string }>();
  if (!row) {
    throw new HttpError("Not deleted: the wallpaper is gone, or this account can't delete it. Reload and try again.", 404);
  }
  return row;
}

export async function adminSetCategoryCover(db: D1Database, category: string, imagePath: string) {
  const trimmedCategory = category.trim();
  const trimmedPath = imagePath.trim();
  if (!trimmedCategory || !trimmedPath.startsWith("covers/")) {
    throw new HttpError("Invalid category cover.", 400);
  }
  const now = new Date().toISOString();
  await db
    .prepare(
      `INSERT INTO category_covers (category, image_path, updated_at)
       VALUES (?1, ?2, ?3)
       ON CONFLICT(category) DO UPDATE SET image_path = excluded.image_path, updated_at = excluded.updated_at`,
    )
    .bind(trimmedCategory, trimmedPath, now)
    .run();
  return { category: trimmedCategory, image_path: trimmedPath, updated_at: now };
}

export async function adminDeleteCategoryCover(db: D1Database, category: string) {
  const row = await db
    .prepare(`DELETE FROM category_covers WHERE category = ?1 RETURNING category`)
    .bind(category)
    .first<{ category: string }>();
  if (!row) {
    throw new HttpError("Not removed: the cover is gone, or this account can't change it. Reload and try again.", 404);
  }
  return row;
}

function mapConstraintError(error: unknown): never {
  const msg = error instanceof Error ? error.message : String(error);
  if (msg.includes("CONSTRAINT") || msg.includes("CHECK") || msg.includes("UNIQUE")) {
    throw new HttpError(msg, 400);
  }
  throw error;
}
