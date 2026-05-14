#!/usr/bin/env node
/**
 * Sync apps/ios/screens/NN-*.png into the Notion "DripAdvisor — iOS Screens"
 * page. For each PNG, uploads the file via Notion's native file_uploads API
 * and inserts an image block right after the matching heading.
 *
 * Idempotent — re-runs replace any previously-synced image block instead of
 * appending a duplicate. Detects prior runs by the marker caption written
 * onto each image block (e.g. "auto:01-avatar-setup.png").
 *
 * Usage:
 *   cd scripts && npm install
 *   NOTION_API_KEY=ntn_… node sync-screens-to-notion.mjs
 *
 * Environment:
 *   NOTION_API_KEY  required. Settings → Integrations → New integration,
 *                   then invite the integration to the screens page.
 *   NOTION_PAGE_ID  optional. Defaults to the page created on 2026-05-13.
 *   SCREENS_DIR     optional. Defaults to ../apps/ios/screens.
 */

import { Client, APIResponseError } from "@notionhq/client";
import { readFile, readdir } from "node:fs/promises";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const NOTION_API_KEY = process.env.NOTION_API_KEY;
const NOTION_PAGE_ID =
  process.env.NOTION_PAGE_ID || "35fb438d-4d56-8151-8557-c5c1d6a66e03";
const SCREENS_DIR =
  process.env.SCREENS_DIR || resolve(__dirname, "../apps/ios/screens");

if (!NOTION_API_KEY) {
  console.error(
    "Missing NOTION_API_KEY. Settings → Integrations → New integration, " +
      "invite it to the screens page, then re-run with NOTION_API_KEY=ntn_…"
  );
  process.exit(1);
}

const notion = new Client({ auth: NOTION_API_KEY });

const MARKER_PREFIX = "auto:";

main().catch((err) => {
  if (APIResponseError.isAPIResponseError(err)) {
    console.error(`Notion API ${err.code}: ${err.message}`);
  } else {
    console.error(err);
  }
  process.exit(1);
});

async function main() {
  const files = await listScreenshots();
  console.log(`Found ${files.length} screenshots in ${SCREENS_DIR}`);

  const blocks = await listAllChildren(NOTION_PAGE_ID);
  console.log(`Page has ${blocks.length} top-level blocks`);

  const headingIdByNumber = indexHeadingsByScreenNumber(blocks);
  const existingImageByMarker = indexAutoImagesByMarker(blocks);

  for (const file of files) {
    const number = parseScreenNumber(file);
    if (number == null) {
      console.warn(`Skipping ${file}: filename does not match NN-*.png`);
      continue;
    }
    const headingId = headingIdByNumber.get(number);
    if (!headingId) {
      console.warn(`Skipping ${file}: no heading "## ${number} —" on page`);
      continue;
    }
    await syncOne(file, headingId, existingImageByMarker);
  }

  console.log("Done.");
}

async function syncOne(file, headingId, existingByMarker) {
  const marker = MARKER_PREFIX + file;
  const path = join(SCREENS_DIR, file);

  console.log(`→ ${file}`);

  // 1. Upload file bytes to Notion.
  const fileUploadId = await uploadPng(path, file);

  // 2. Build the image block payload.
  const newBlock = {
    object: "block",
    type: "image",
    image: {
      type: "file_upload",
      file_upload: { id: fileUploadId },
      caption: [{ type: "text", text: { content: marker } }],
    },
  };

  // 3. If a prior run already inserted an image with this marker, replace it
  //    in place; otherwise append after the heading.
  const existing = existingByMarker.get(marker);
  if (existing) {
    await notion.blocks.delete({ block_id: existing });
    existingByMarker.delete(marker);
  }
  await notion.blocks.children.append({
    block_id: headingId,
    children: [newBlock],
  });
}

async function uploadPng(path, filename) {
  const buf = await readFile(path);
  const sizeMB = (buf.length / 1024 / 1024).toFixed(2);
  console.log(`   uploading ${sizeMB} MB`);

  if (buf.length > 20 * 1024 * 1024) {
    throw new Error(
      `${filename} is ${sizeMB} MB. Multi-part upload not implemented; ` +
        `keep screens under 20MB or extend this script.`
    );
  }

  const created = await notion.fileUploads.create({
    mode: "single_part",
    filename,
    content_type: "image/png",
  });

  await notion.fileUploads.send({
    file_upload_id: created.id,
    file: {
      filename,
      data: new Blob([buf], { type: "image/png" }),
    },
  });

  return created.id;
}

async function listScreenshots() {
  const entries = await readdir(SCREENS_DIR);
  const pngs = entries
    .filter((f) => f.toLowerCase().endsWith(".png"))
    .filter((f) => /^\d+-/.test(f))
    .sort();
  return pngs;
}

async function listAllChildren(pageId) {
  const out = [];
  let cursor;
  do {
    const r = await notion.blocks.children.list({
      block_id: pageId,
      start_cursor: cursor,
      page_size: 100,
    });
    out.push(...r.results);
    cursor = r.has_more ? r.next_cursor : undefined;
  } while (cursor);
  return out;
}

function indexHeadingsByScreenNumber(blocks) {
  const map = new Map();
  for (const b of blocks) {
    if (b.type !== "heading_2") continue;
    const text = plainText(b.heading_2?.rich_text);
    const m = /^(\d{1,3})\s*[—\-]/.exec(text);
    if (m) map.set(Number(m[1]), b.id);
  }
  return map;
}

function indexAutoImagesByMarker(blocks) {
  const map = new Map();
  for (const b of blocks) {
    if (b.type !== "image") continue;
    const cap = plainText(b.image?.caption);
    if (cap.startsWith(MARKER_PREFIX)) map.set(cap, b.id);
  }
  return map;
}

function plainText(richText) {
  if (!Array.isArray(richText)) return "";
  return richText.map((r) => r.plain_text || r.text?.content || "").join("").trim();
}

function parseScreenNumber(filename) {
  const m = /^(\d{1,3})-/.exec(filename);
  return m ? Number(m[1]) : null;
}
