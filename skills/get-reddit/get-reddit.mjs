#!/usr/bin/env node
// get-reddit.mjs — fetch a single public Reddit post + top comments through a REAL browser
// session, because Reddit (a) 403s all non-browser fetches from any IP and (b) disabled
// self-serve API-app creation in Nov 2025 (Responsible Builder Policy), closing the OAuth path.
//
// Technique (same approach that reaches other bot-protected sites): launch Chromium,
// PARK the page on the reddit.com post URL first so the context is "warm" (session cookie set,
// real sec-ch-ua / sec-fetch-* headers stamped), THEN do an in-page same-origin
// `fetch('<post>.json')`. The browser carries cookies + headers that Node's fetch/undici cannot
// replicate, so Reddit returns real JSON instead of the anti-bot HTML page.
//
// Usage:   node get-reddit.mjs <reddit-url-or-post-id> [comment_limit]
// Env:     GET_REDDIT_HEADLESS=0   show the browser window (use if a fetch gets challenged)
//          GET_REDDIT_PROFILE=<dir> override the persisted browser-profile dir
//
// Output: markdown to stdout (title, meta, body, top comments). Non-zero exit on failure.

import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { mkdirSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ---- args -----------------------------------------------------------------------------------
const input = process.argv[2];
const limit = Number.parseInt(process.argv[3] ?? '25', 10) || 25;
if (!input) {
  console.error('usage: node get-reddit.mjs <reddit-url-or-post-id> [comment_limit]');
  process.exit(2);
}

// Parse a base-36 post id out of a URL / redd.it link / bare id.
let postId = null;
let m;
if ((m = input.match(/\/comments\/([a-z0-9]+)/i))) postId = m[1];
else if ((m = input.match(/redd\.it\/([a-z0-9]+)/i))) postId = m[1];
else if (/^[a-z0-9]+$/i.test(input)) postId = input;
if (!postId) {
  console.error(`error: could not parse a post id from: ${input}`);
  process.exit(4);
}

const headless = process.env.GET_REDDIT_HEADLESS !== '0';
const profileDir = process.env.GET_REDDIT_PROFILE || join(__dirname, '.profile');
mkdirSync(profileDir, { recursive: true });

const UA =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

// ---- fetch via a warm browser context -------------------------------------------------------
async function fetchPostJson() {
  const ctx = await chromium.launchPersistentContext(profileDir, {
    headless,
    args: ['--disable-blink-features=AutomationControlled'],
    userAgent: UA,
    locale: 'en-US',
    viewport: { width: 1440, height: 900 },
  });
  try {
    const page = ctx.pages()[0] || (await ctx.newPage());

    // 1) Park on the post's HTML page so the in-page fetch inherits cookies + a real origin.
    //    If the direct landing is challenged, bounce through DuckDuckGo first (referral cookie
    //    trick) and retry — this is the documented unlock for Reddit's anti-bot gate.
    const landingUrl = `https://www.reddit.com/comments/${postId}/`;
    const landed = await tryLanding(page, landingUrl);
    if (!landed) {
      await page.goto('https://duckduckgo.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForTimeout(800);
      await tryLanding(page, landingUrl); // best-effort; the fetch below is the real test
    }

    // 2) Same-origin in-page fetch of the JSON API. Carries the browser's session + headers.
    const jsonUrl =
      `https://www.reddit.com/comments/${postId}.json?raw_json=1&limit=${limit}&sort=top`;
    const res = await page.evaluate(async (url) => {
      try {
        const r = await fetch(url, { headers: { Accept: 'application/json' }, credentials: 'include' });
        const text = await r.text();
        return { status: r.status, text };
      } catch (e) {
        return { status: -1, text: String(e) };
      }
    }, jsonUrl);

    return res;
  } finally {
    await ctx.close();
  }
}

async function tryLanding(page, url) {
  try {
    const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(500);
    const status = resp ? resp.status() : 0;
    // 200 with real reddit chrome = good; 403/429 or a "blocked" body = challenged.
    if (status >= 200 && status < 400) return true;
    return false;
  } catch {
    return false;
  }
}

// ---- render ----------------------------------------------------------------------------------
function renderMarkdown(json) {
  const post = json?.[0]?.data?.children?.[0]?.data;
  if (!post || !post.title) throw new Error('no post in response');

  const out = [];
  out.push(`# ${post.title}\n`);
  const pct = Math.floor((post.upvote_ratio ?? 0) * 100);
  out.push(
    `\n**r/${post.subreddit}** · u/${post.author} · score ${post.score} · ${pct}% up · ${post.num_comments} comments`,
  );
  out.push(`\nhttps://www.reddit.com${post.permalink}\n`);
  if (post.selftext && post.selftext.trim()) out.push(`\n---\n\n${post.selftext}\n`);
  else if (post.url && /^https?:\/\//.test(post.url) && !/reddit\.com|redd\.it/.test(post.url))
    out.push(`\nLink: ${post.url}\n`);

  const comments = (json?.[1]?.data?.children ?? [])
    .filter((c) => c.kind === 't1' && c.data && c.data.body)
    .map((c) => c.data)
    .sort((a, b) => (b.score ?? 0) - (a.score ?? 0))
    .slice(0, limit);

  if (comments.length) {
    out.push('\n---\n## Top comments\n');
    for (const c of comments) out.push(`\n**u/${c.author}** (score ${c.score}):\n${c.body}`);
  } else {
    out.push('\n_(no comments)_');
  }
  return out.join('\n');
}

// ---- main ------------------------------------------------------------------------------------
try {
  const res = await fetchPostJson();
  if (res.status === 429) {
    console.error('error: Reddit rate-limited (HTTP 429) — wait ~15s and retry. Run sequentially.');
    process.exit(8);
  }
  if (res.status !== 200) {
    console.error(`error: fetch failed (status ${res.status}) for post ${postId}.`);
    if (headless) console.error('hint: retry with GET_REDDIT_HEADLESS=0 to solve a one-time challenge.');
    console.error(String(res.text).slice(0, 300));
    process.exit(7);
  }
  let json;
  try {
    json = JSON.parse(res.text);
  } catch {
    console.error('error: response was not JSON (likely the anti-bot HTML page).');
    if (headless) console.error('hint: retry with GET_REDDIT_HEADLESS=0 once to warm the session.');
    process.exit(7);
  }
  console.log(renderMarkdown(json));
} catch (e) {
  console.error(`error: ${e.message || e}`);
  process.exit(1);
}
