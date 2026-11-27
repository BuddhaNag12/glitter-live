import { verifierKeysURL, verifyRewardCallback, type AdMobKey } from "./admob";
import { HttpError, json, readJsonBody } from "./http";

const visionModel = "@cf/meta/llama-3.2-11b-vision-instruct";
const reportReasons = new Set(["sexual", "violent", "hateful", "other"]);
const maximumPromptLength = 600;
const maximumImageBytes = 4_000_000;

let cachedAdMobKeys: AdMobKey[] = [];

export async function handleAdReward(request: Request, env: Env): Promise<Response> {
  const query = new URL(request.url).search.slice(1);
  try {
    const params = new URLSearchParams(query);
    const nonce = params.get("custom_data") ?? "";
    const install = params.get("user_id") ?? "";
    const transaction = params.get("transaction_id") ?? "";
    // Convert's ads carry no nonce and AdMob's "Verify URL" test may carry no IDs: nothing to record, still 200.
    if (!nonce || !install || !transaction) return new Response("OK");
    if (!(await verified(query))) return new Response("Invalid signature.", { status: 400 });
    const expectedUnit = env.ADMOB_REWARDED_AD_UNIT ?? "";
    if (expectedUnit && params.get("ad_unit") !== expectedUnit) return new Response("OK");
    if (nonce.length > 64 || install.length > 64) return new Response("Unexpected IDs.", { status: 400 });

    await env.DB.prepare(
      `INSERT OR IGNORE INTO ad_rewards (transaction_id, install_id, nonce) VALUES (?1, ?2, ?3)`,
    )
      .bind(transaction, install, nonce)
      .run();
    return new Response("OK");
  } catch (error) {
    console.error(JSON.stringify({ event: "ad_reward_error", error: error instanceof Error ? error.message : String(error) }));
    return new Response("Try again.", { status: 500 });
  }
}

async function verified(query: string): Promise<boolean> {
  const keyId = new URLSearchParams(query).get("key_id");
  if (!cachedAdMobKeys.some((key) => String(key.keyId) === keyId)) {
    const response = await fetch(verifierKeysURL);
    if (!response.ok) throw new Error(`Google's verifier keys returned ${response.status}`);
    const data = (await response.json()) as { keys?: AdMobKey[] };
    cachedAdMobKeys = data.keys ?? [];
  }
  return verifyRewardCallback(query, cachedAdMobKeys);
}

export async function handleGenerate(request: Request, env: Env): Promise<Response> {
  const body = await readJsonBody(request);
  const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
  if (!prompt || prompt.length > maximumPromptLength) {
    throw new HttpError("Describe the wallpaper in up to 280 characters.", 400);
  }

  const dailyLimitPerInstall = Number(env.DAILY_GENERATIONS_PER_INSTALL ?? "3");
  const dailyLimitTotal = Number(env.DAILY_GENERATIONS_TOTAL ?? "60");
  const requiresReward = String(env.REQUIRE_AD_REWARD ?? "true") !== "false";
  const allowsVideo = String(env.ALLOW_VIDEO ?? "false") === "true";

  switch (body.action) {
    case "image": {
      const install = shortText(body.install);
      const reward = shortText(body.reward);
      await checkPrompt(prompt, env);
      if (requiresReward) await redeemWithWait(env.DB, reward, install, dailyLimitPerInstall, dailyLimitTotal);
      try {
        const image = await makeImage(prompt, env);
        await checkImage(image, env);
        return json({ image });
      } catch (error) {
        const isServerFailure = !(error instanceof HttpError) || error.status >= 500;
        if (requiresReward && isServerFailure) {
          await refundAdReward(env.DB, reward, install).catch((err) =>
            console.error(JSON.stringify({ event: "refund_failed", error: String(err) })),
          );
        }
        throw error;
      }
    }
    case "report": {
      const install = shortText(body.install);
      const reason = shortText(body.reason);
      if (!install || !reportReasons.has(reason)) {
        throw new HttpError("The report is missing its reason.", 400);
      }
      await env.DB.prepare(`INSERT INTO generation_reports (install_id, prompt, reason) VALUES (?1, ?2, ?3)`)
        .bind(install, prompt, reason)
        .run();
      return json({ reported: true });
    }
    case "video": {
      if (!allowsVideo) throw new HttpError("Unknown action.", 400);
      const image = typeof body.image === "string" ? body.image : "";
      if (!image || image.length > (maximumImageBytes * 4) / 3) {
        throw new HttpError("The image to animate is missing.", 400);
      }
      await checkPrompt(prompt, env);
      return json({ videoUrl: await animate(prompt, image, env.FAL_KEY ?? "") });
    }
    default:
      throw new HttpError("Unknown action.", 400);
  }
}

function shortText(value: unknown): string {
  return typeof value === "string" && value.length <= 64 ? value : "";
}

/**
 * Atomically redeems one unspent ad reward (within 1 hour of creation) while enforcing
 * both the UTC-day global cap and per-install daily cap.
 */
export async function redeemAdRewardOnce(
  db: D1Database,
  nonce: string,
  install: string,
  dailyLimit: number,
  globalLimit: number,
): Promise<"ok" | "daily_limit" | "global_limit" | "no_reward"> {
  const now = new Date();
  const todayStart = `${now.toISOString().slice(0, 10)}T00:00:00.000Z`;
  const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000).toISOString();
  const redeemedAt = now.toISOString();

  const updated = await db
    .prepare(
      `UPDATE ad_rewards
       SET redeemed_at = ?1
       WHERE transaction_id = (
         SELECT transaction_id FROM ad_rewards
         WHERE nonce = ?2 AND install_id = ?3 AND redeemed_at IS NULL AND created_at > ?4
         LIMIT 1
       )
       AND (SELECT COUNT(*) FROM ad_rewards WHERE redeemed_at >= ?5) < ?6
       AND (SELECT COUNT(*) FROM ad_rewards WHERE redeemed_at >= ?5 AND install_id = ?3) < ?7
       RETURNING transaction_id`,
    )
    .bind(redeemedAt, nonce, install, oneHourAgo, todayStart, globalLimit, dailyLimit)
    .first<{ transaction_id: string }>();

  if (updated) return "ok";

  const counts = await db
    .prepare(
      `SELECT
         (SELECT COUNT(*) FROM ad_rewards WHERE redeemed_at >= ?1) AS global_count,
         (SELECT COUNT(*) FROM ad_rewards WHERE redeemed_at >= ?1 AND install_id = ?2) AS daily_count`,
    )
    .bind(todayStart, install)
    .first<{ global_count: number; daily_count: number }>();

  if ((counts?.global_count ?? 0) >= globalLimit) return "global_limit";
  if ((counts?.daily_count ?? 0) >= dailyLimit) return "daily_limit";
  return "no_reward";
}

export async function refundAdReward(db: D1Database, nonce: string, install: string): Promise<void> {
  await db.prepare(`UPDATE ad_rewards SET redeemed_at = NULL WHERE nonce = ?1 AND install_id = ?2`).bind(nonce, install).run();
}

async function redeemWithWait(
  db: D1Database,
  reward: string,
  install: string,
  dailyLimit: number,
  globalLimit: number,
): Promise<void> {
  if (!reward || !install) throw new HttpError("Watch the ad to the end to make a wallpaper.", 402);
  for (let attempt = 0; attempt < 10; attempt++) {
    const result = await redeemAdRewardOnce(db, reward, install, dailyLimit, globalLimit);
    switch (result) {
      case "ok":
        return;
      case "daily_limit":
        throw new HttpError("You've made today's AI wallpapers. Come back tomorrow for more.", 429);
      case "global_limit":
        throw new HttpError("AI wallpapers have reached today's limit. Try again tomorrow.", 503);
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new HttpError("The ad couldn't be confirmed. Watch the ad to the end, then try again.", 402);
}

async function runAI<T = unknown>(env: Env, model: string, input: Record<string, unknown>): Promise<T> {
  try {
    return (await env.AI.run(model as keyof AiModels, input as never)) as T;
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    if (msg.includes("429") || msg.toLowerCase().includes("quota") || msg.toLowerCase().includes("limit")) {
      throw new HttpError("AI wallpapers have reached today's limit. Try again tomorrow.", 503);
    }
    throw error;
  }
}

async function checkPrompt(prompt: string, env: Env): Promise<void> {
  const result = await runAI<{ response?: string | { safe?: boolean } }>(env, "@cf/meta/llama-guard-3-8b", {
    messages: [{ role: "user", content: prompt }],
  });
  const verdict = result?.response;
  const safe = typeof verdict === "string" ? !verdict.trim().toLowerCase().startsWith("unsafe") : verdict?.safe !== false;
  if (!safe) throw new HttpError("This description can't be used. Try describing a different scene.", 400);
}

async function makeImage(prompt: string, env: Env): Promise<string> {
  const result = await runAI<{ image?: string }>(env, "@cf/black-forest-labs/flux-1-schnell", {
    prompt: `${prompt}, centered composition, subject in the middle third`,
    steps: 6,
  });
  if (typeof result?.image !== "string") throw new Error("Cloudflare returned no image.");
  return result.image;
}

async function checkImage(image: string, env: Env): Promise<void> {
  const bin = atob(image);
  const bytes = new Array<number>(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  const input = {
    prompt:
      "You review images for a phone wallpaper app rated for all ages. Does this image show nudity, " +
      "sexual content, graphic violence or gore, hate symbols, or drug use? Answer with one word: SAFE or UNSAFE.",
    image: bytes,
    max_tokens: 4,
  };
  let result: { response?: string };
  try {
    result = await runAI<{ response?: string }>(env, visionModel, input);
  } catch (error) {
    if (!String(error).toLowerCase().includes("agree")) throw error;
    await runAI(env, visionModel, { prompt: "agree" }).catch(() => {});
    result = await runAI<{ response?: string }>(env, visionModel, input);
  }
  if (String(result?.response ?? "").trim().toUpperCase().startsWith("UNSAFE")) {
    throw new HttpError("This wallpaper can't be shown. Try describing a different scene.", 400);
  }
}

async function animate(prompt: string, image: string, falKey: string): Promise<string> {
  const response = await fetch("https://fal.run/fal-ai/ltx-video-13b-distilled/image-to-video", {
    method: "POST",
    headers: { Authorization: `Key ${falKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      prompt: `${prompt}, gentle continuous motion, slow subtle camera drift, smooth and seamless`,
      image_url: `data:image/jpeg;base64,${image}`,
      aspect_ratio: "9:16",
      resolution: "720p",
      num_frames: 73,
      frame_rate: 24,
      enable_safety_checker: true,
    }),
  });
  const payload = (await response.json().catch(() => ({}))) as { video?: { url?: string } };
  if (!response.ok) throw new Error(`fal returned ${response.status}: ${JSON.stringify(payload).slice(0, 500)}`);
  const url = payload?.video?.url;
  if (typeof url !== "string") throw new Error("fal returned no video.");
  return url;
}
