#!/usr/bin/env node

// Reads one public Reddit thread from the rendered page (DOM), not the `.json` API:
// Reddit answers 403 on `.json` even inside a real browser session, and 403s any
// browser whose user agent says "HeadlessChrome" or names a Chrome version other
// than the one actually running. So: real Chrome, new headless mode, true version.

import { chromium } from 'playwright-core';
import { execFileSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { mkdirSync } from 'node:fs';

const input = process.argv[2];
if (!input) {
  console.error('usage: node get-reddit.mjs <reddit-url-or-post-id> [comment-limit]');
  process.exit(2);
}

const parsedLimit = Number.parseInt(process.argv[3] ?? '25', 10);
const limit = Number.isFinite(parsedLimit) ? Math.min(100, Math.max(1, parsedLimit)) : 25;

// A share link (reddit.com/r/<sub>/s/<token>) carries no post ID; the browser has to
// follow its redirect. Rebuild it from validated parts so nothing else is navigated to.
let postId = null;
let shareUrl = null;
let match;
if ((match = input.match(/\/comments\/([a-z0-9]+)/i))) postId = match[1];
else if ((match = input.match(/redd\.it\/([a-z0-9]+)/i))) postId = match[1];
else if (
  (match = input.match(
    /^https?:\/\/(?:[a-z0-9-]+\.)?reddit\.com\/(r|u|user)\/([A-Za-z0-9_-]+)\/s\/([A-Za-z0-9]+)/i,
  ))
) {
  shareUrl = `https://www.reddit.com/${match[1]}/${match[2]}/s/${match[3]}`;
} else if (/^[a-z0-9]+$/i.test(input)) postId = input;

if (!postId && !shareUrl) {
  console.error(`error: could not parse a Reddit post ID from: ${input}`);
  process.exit(4);
}

const headless = process.env.GET_REDDIT_HEADLESS !== '0';
const executablePath = process.env.GET_REDDIT_CHROME;
if (!executablePath) {
  console.error('error: GET_REDDIT_CHROME must point to a Chrome/Chromium executable');
  process.exit(10);
}
const cacheRoot = process.env.XDG_CACHE_HOME || join(homedir(), '.cache');
const profileDir = process.env.GET_REDDIT_PROFILE || join(cacheRoot, 'codex-get-reddit', 'profile');
mkdirSync(profileDir, { recursive: true });

let chromeMajor;
try {
  chromeMajor = execFileSync(executablePath, ['--version'], { timeout: 15_000 })
    .toString()
    .match(/(\d+)\.\d+\.\d+/)?.[1];
} catch {
  chromeMajor = undefined;
}
if (!chromeMajor) {
  console.error(`error: could not read a version from ${executablePath} --version`);
  process.exit(10);
}
const userAgent =
  `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) ` +
  `Chrome/${chromeMajor}.0.0.0 Safari/537.36`;

function fail(code, message, detail) {
  console.error(`error: ${message}`);
  if (detail) console.error(String(detail).slice(0, 300));
  if (code === 7 && headless) {
    console.error('hint: one headed retry with GET_REDDIT_HEADLESS=0 may clear a challenge.');
  }
  process.exit(code);
}

async function fetchThread() {
  // Playwright's own headless mode is a different binary mode that Reddit blocks, so
  // ask Chrome for its new headless mode directly; "headed" just omits the flag.
  const args = ['--disable-blink-features=AutomationControlled'];
  if (headless) args.push('--headless=new');
  const context = await chromium.launchPersistentContext(profileDir, {
    executablePath,
    headless: false,
    args,
    userAgent,
    locale: 'en-US',
    viewport: { width: 1440, height: 900 },
  });

  try {
    const page = context.pages()[0] || (await context.newPage());
    const open = (url) => page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30_000 });

    if (shareUrl) {
      const response = await open(shareUrl);
      const landed = new URL(page.url());
      const id = landed.pathname.match(/\/comments\/([a-z0-9]+)/i)?.[1];
      if (!/(^|\.)reddit\.com$/.test(landed.hostname) || !id) {
        return { status: response?.status() ?? -1, error: 'share link did not resolve to a post' };
      }
      postId = id;
    }

    const response = await open(`https://www.reddit.com/comments/${postId}/?sort=top`);
    const status = response?.status() ?? -1;
    if (status !== 200) {
      return { status, error: await page.content().catch(() => '') };
    }

    const hasPost = await page
      .waitForSelector('shreddit-post', { timeout: 15_000 })
      .then(() => true, () => false);
    if (!hasPost) return { status, error: 'page loaded without a post element' };
    await page.waitForSelector('shreddit-comment', { timeout: 10_000 }).catch(() => {});

    // More top-level comments come from a "more-comments" partial outside any comment.
    // The first one loads when scrolled into view; later ones need their button clicked.
    for (let round = 0; round < 30; round += 1) {
      const count = await page.locator('shreddit-comment[depth="0"]').count();
      if (count >= limit) break;
      const found = await page.evaluate(() => {
        const more = [...document.querySelectorAll('faceplate-partial[src*="more-comments"]')].find(
          (element) => !element.closest('shreddit-comment'),
        );
        if (!more) return false;
        more.scrollIntoView({ block: 'center' });
        more.querySelector('button')?.click();
        return true;
      });
      if (!found) break;
      await page
        .waitForFunction(
          (before) => document.querySelectorAll('shreddit-comment[depth="0"]').length > before,
          count,
          { timeout: 8_000 },
        )
        .catch(() => {});
      if ((await page.locator('shreddit-comment[depth="0"]').count()) === count) break;
    }

    const thread = await page.evaluate(() => {
      const text = (element) =>
        (element?.innerText || element?.textContent || '').replace(/\n{3,}/g, '\n\n').trim();
      const post = document.querySelector('shreddit-post');
      const comments = [...document.querySelectorAll('shreddit-comment[depth="0"]')].map(
        (comment) => ({
          author: comment.getAttribute('author'),
          score: Number(comment.getAttribute('score')),
          body: text(
            [...comment.querySelectorAll('[slot="comment"]')].find(
              (element) => element.closest('shreddit-comment') === comment,
            ),
          ),
        }),
      );
      return {
        title: post.getAttribute('post-title'),
        subreddit: post.getAttribute('subreddit-name'),
        author: post.getAttribute('author'),
        score: post.getAttribute('score'),
        upvoteRatio: post.getAttribute('upvote-ratio'),
        commentCount: post.getAttribute('comment-count'),
        created: post.getAttribute('created-timestamp'),
        permalink: post.getAttribute('permalink'),
        contentHref: post.getAttribute('content-href'),
        body: text(post.querySelector('[slot="text-body"]')),
        comments,
      };
    });
    return { status, thread };
  } finally {
    await context.close();
  }
}

function renderMarkdown(post) {
  if (!post?.title) throw new Error('no post in page');

  const output = [];
  output.push(`# ${post.title}\n`);
  const upvotePercent = Math.floor(Number(post.upvoteRatio ?? 0) * 100);
  const date = post.created ? ` · ${String(post.created).slice(0, 10)}` : '';
  output.push(
    `\n**r/${post.subreddit}** · u/${post.author} · score ${post.score} · ` +
      `${upvotePercent}% up · ${post.commentCount} comments${date}`,
  );
  output.push(`\nhttps://www.reddit.com${post.permalink}\n`);

  if (post.body) output.push(`\n---\n\n${post.body}\n`);
  else if (/^https?:\/\//.test(post.contentHref ?? '') && !/reddit\.com|redd\.it/.test(post.contentHref)) {
    output.push(`\nLinked URL: ${post.contentHref}\n`);
  }

  const comments = post.comments
    .filter((comment) => comment.body)
    .sort((left, right) => (right.score || 0) - (left.score || 0))
    .slice(0, limit);

  if (!comments.length) {
    output.push('\n_(no top-level comments returned)_');
    return output.join('\n');
  }

  output.push('\n---\n## Top-level comments\n');
  for (const comment of comments) {
    output.push(`\n**u/${comment.author}** (score ${comment.score}):\n${comment.body}`);
  }
  return output.join('\n');
}

try {
  const result = await fetchThread();
  if (result.status === 429) {
    console.error('error: Reddit rate-limited this fetch (HTTP 429); retry once later.');
    process.exit(8);
  }
  if (!result.thread) {
    fail(7, `Reddit fetch failed with status ${result.status} for ${postId ?? shareUrl}.`, result.error);
  }
  console.log(renderMarkdown(result.thread));
} catch (error) {
  console.error(`error: ${error?.message || error}`);
  process.exit(1);
}
