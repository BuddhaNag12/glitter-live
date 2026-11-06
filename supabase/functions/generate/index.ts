// Turns a prompt into a wallpaper image, then animates that image into a short clip.
// Two steps, so the app can show the image while its motion is being made.
//
//   POST { "action": "image", "prompt": "…", "install": "<id>", "reward": "<nonce>" } → { "image": "<base64 JPEG>" }
//   POST { "action": "video", "prompt": "…", "image": "<b64>" }                        → { "videoUrl": "https://…" }
//   POST { "action": "report", "prompt": "…", "install": "<id>", "reason": "sexual" } → { "reported": true }
//
// Every image spends one rewarded ad that Google confirmed to `ad-reward`, within a daily limit per install
// and across everyone, so nothing the app (or anyone else) sends can generate for free.
// Provider keys live in Supabase secrets and never reach the app.

import { database } from "../_shared/database.ts";

const cloudflareAccount = Deno.env.get("CLOUDFLARE_ACCOUNT_ID") ?? "";
const cloudflareToken = Deno.env.get("CLOUDFLARE_AI_TOKEN") ?? "";
const falKey = Deno.env.get("FAL_KEY") ?? "";
const dailyLimitPerInstall = Number(Deno.env.get("DAILY_GENERATIONS_PER_INSTALL") ?? "3");
// About what Cloudflare's free tier covers; raise it with Workers Paid.
const dailyLimitTotal = Number(Deno.env.get("DAILY_GENERATIONS_TOTAL") ?? "60");
// Development only: "false" generates without a verified ad, for debug builds that show Google's sample ads.
const requiresReward = Deno.env.get("REQUIRE_AD_REWARD") !== "false";
// AI video is off in the app; it stays off here too until it gets its own limits, since fal bills per clip.
const allowsVideo = Deno.env.get("ALLOW_VIDEO") === "true";
const visionModel = "@cf/meta/llama-3.2-11b-vision-instruct";
const reportReasons = ["sexual", "violent", "hateful", "other"];

const maximumPromptLength = 600;
// A 720p frame is far smaller than this; anything larger isn't one of our images.
const maximumImageBytes = 4_000_000;

class RequestError extends Error {
  constructor(message: string, readonly status = 400) {
    super(message);
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "Use POST." }, 405);
  try {
    const body = await request.json().catch(() => {
      throw new RequestError("The request isn't valid JSON.");
    });
    const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
    if (!prompt || prompt.length > maximumPromptLength) throw new RequestError("Describe the wallpaper in up to 280 characters.");

    switch (body.action) {
      case "image": {
        const install = text(body.install);
        const reward = text(body.reward);
        await checkPrompt(prompt);
        if (requiresReward) await redeem(reward, install);
        try {
          const image = await makeImage(prompt);
          await checkImage(image);
          return reply({ image });
        } catch (error) {
          // The server or a provider failed, not the description: the ad can be used again.
          const isServerFailure = !(error instanceof RequestError) || error.status >= 500;
          if (requiresReward && isServerFailure) await refund(reward, install);
          throw error;
        }
      }
      case "report": {
        const install = text(body.install);
        const reason = text(body.reason);
        if (!install || !reportReasons.includes(reason)) throw new RequestError("The report is missing its reason.");
        await database("generation_reports", { install_id: install, prompt, reason }, "return=minimal");
        return reply({ reported: true });
      }
      case "video": {
        if (!allowsVideo) throw new RequestError("Unknown action.");
        const image = typeof body.image === "string" ? body.image : "";
        if (!image || image.length > maximumImageBytes * 4 / 3) throw new RequestError("The image to animate is missing.");
        await checkPrompt(prompt);
        return reply({ videoUrl: await animate(prompt, image) });
      }
      default:
        throw new RequestError("Unknown action.");
    }
  } catch (error) {
    if (error instanceof RequestError) return reply({ error: error.message }, error.status);
    console.error(error);
    return reply({ error: "Generation is unavailable right now. Try again in a moment." }, 502);
  }
});

/** A short ID from the request, or "" when it's missing or not one. */
function text(value: unknown) {
  return typeof value === "string" && value.length <= 64 ? value : "";
}

/** Spends the ad watched for this generation. Google's callback can land a few seconds after the ad closes. */
async function redeem(reward: string, install: string) {
  if (!reward || !install) throw new RequestError("Watch the ad to the end to make a wallpaper.", 402);
  for (let attempt = 0; attempt < 10; attempt++) {
    const result = await database("rpc/redeem_ad_reward", {
      p_nonce: reward, p_install: install, p_daily_limit: dailyLimitPerInstall, p_global_limit: dailyLimitTotal,
    });
    switch (result) {
      case "ok": return;
      case "daily_limit": throw new RequestError("You've made today's AI wallpapers. Come back tomorrow for more.", 429);
      case "global_limit": throw new RequestError("AI wallpapers have reached today's limit. Try again tomorrow.", 503);
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new RequestError("The ad couldn't be confirmed. Watch the ad to the end, then try again.", 402);
}

async function refund(reward: string, install: string) {
  await database("rpc/refund_ad_reward", { p_nonce: reward, p_install: install }).catch(console.error);
}

function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function runCloudflare(model: string, input: unknown) {
  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${cloudflareAccount}/ai/run/${model}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${cloudflareToken}`, "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  const json = await response.json().catch(() => ({}));
  // The free tier allows 10,000 neurons a day and resets at midnight UTC; say so rather than "unavailable".
  if (response.status === 429) throw new RequestError("AI wallpapers have reached today's limit. Try again tomorrow.", 503);
  if (!response.ok || json.success === false) {
    throw new Error(`Cloudflare ${model} returned ${response.status}: ${JSON.stringify(json.errors ?? json).slice(0, 500)}`);
  }
  return json.result;
}

/// Llama Guard screens the prompt before anything is generated.
async function checkPrompt(prompt: string) {
  const result = await runCloudflare("@cf/meta/llama-guard-3-8b", { messages: [{ role: "user", content: prompt }] });
  const verdict = result?.response;
  // Workers AI returns either a parsed verdict or the model's raw "safe" / "unsafe\nS1" text.
  const safe = typeof verdict === "string" ? !verdict.trim().toLowerCase().startsWith("unsafe") : verdict?.safe !== false;
  if (!safe) throw new RequestError("This description can't be used. Try describing a different scene.");
}

/// A vision model looks at the finished image, since a harmless-looking description can still produce one that isn't.
async function checkImage(image: string) {
  const input = {
    messages: [{
      role: "user",
      content: "You review images for a phone wallpaper app rated for all ages. Does this image show nudity, " +
        "sexual content, graphic violence or gore, hate symbols, or drug use? Answer with one word: SAFE or UNSAFE.",
    }],
    image: Array.from(Uint8Array.from(atob(image), (c) => c.charCodeAt(0))),
    max_tokens: 4,
  };
  let result;
  try {
    result = await runCloudflare(visionModel, input);
  } catch (error) {
    // Meta's licence has to be accepted once per Cloudflare account by sending "agree".
    if (!String(error).toLowerCase().includes("agree")) throw error;
    await runCloudflare(visionModel, { prompt: "agree" }).catch(() => {});
    result = await runCloudflare(visionModel, input);
  }
  if (String(result?.response ?? "").trim().toUpperCase().startsWith("UNSAFE")) {
    throw new RequestError("This wallpaper can't be shown. Try describing a different scene.");
  }
}

async function makeImage(prompt: string): Promise<string> {
  // FLUX schnell makes a square; the video step crops it to 9:16, so a centered subject survives.
  const result = await runCloudflare("@cf/black-forest-labs/flux-1-schnell", {
    prompt: `${prompt}, centered composition, subject in the middle third`,
    steps: 6,
  });
  if (typeof result?.image !== "string") throw new Error("Cloudflare returned no image.");
  return result.image;
}

async function animate(prompt: string, image: string): Promise<string> {
  const response = await fetch("https://fal.run/fal-ai/ltx-video-13b-distilled/image-to-video", {
    method: "POST",
    headers: { Authorization: `Key ${falKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      prompt: `${prompt}, gentle continuous motion, slow subtle camera drift, smooth and seamless`,
      image_url: `data:image/jpeg;base64,${image}`,
      aspect_ratio: "9:16",
      resolution: "720p",
      // About 3 seconds at 24 fps, the longest clip the Lock Screen plays reliably.
      num_frames: 73,
      frame_rate: 24,
      enable_safety_checker: true,
    }),
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`fal returned ${response.status}: ${JSON.stringify(json).slice(0, 500)}`);
  const url = json?.video?.url;
  if (typeof url !== "string") throw new Error("fal returned no video.");
  return url;
}
