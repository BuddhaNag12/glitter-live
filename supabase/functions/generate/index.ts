// Turns a prompt into a wallpaper image, then animates that image into a short clip.
// Two steps, so the app can show the image while its motion is being made.
//
//   POST { "action": "image", "prompt": "…" }                 → { "image": "<base64 JPEG>" }
//   POST { "action": "video", "prompt": "…", "image": "<b64>" } → { "videoUrl": "https://…" }
//
// Provider keys live in Supabase secrets and never reach the app.

const cloudflareAccount = Deno.env.get("CLOUDFLARE_ACCOUNT_ID") ?? "";
const cloudflareToken = Deno.env.get("CLOUDFLARE_AI_TOKEN") ?? "";
const falKey = Deno.env.get("FAL_KEY") ?? "";

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
        await checkPrompt(prompt);
        return reply({ image: await makeImage(prompt) });
      }
      case "video": {
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
