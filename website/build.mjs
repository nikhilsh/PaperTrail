#!/usr/bin/env node
// build.mjs — static-site generator for the PaperTrail install page.
//
// Pulls the latest GitHub release that carries PaperTrail.ipa, generates the
// iOS OTA manifest.plist, and renders index.template.html with the real
// version / size / install URLs baked in (correct even with JS disabled).
// A runtime version.json lets the page freshen itself without a rebuild.
//
// Output: out/{index.html, version.json, ios/manifest.plist, assets/*, .deploy.yaml}
// `fyra push` from out/ ships it.

import { mkdir, writeFile, copyFile, readFile, readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.join(__dirname, "out");
const assetsSrc = path.join(__dirname, "public", "assets");
const templatePath = path.join(__dirname, "index.template.html");
const privacyPath = path.join(__dirname, "privacy.html");
const deployYaml = path.join(__dirname, ".deploy.yaml");

const repo = process.env.GITHUB_REPO || "nikhilsh/PaperTrail";
const siteOrigin = process.env.SITE_ORIGIN || "https://papertrail.kaopeh.com";
const IPA_NAME = "PaperTrail.ipa";
const BUNDLE_ID = "nikhilsh.PaperTrail";
const APP_TITLE = "PaperTrail";

const headers = { "User-Agent": "papertrail-website-build", Accept: "application/vnd.github+json" };
const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
if (token) headers.Authorization = `Bearer ${token}`;

async function fetchRelease() {
    const res = await fetch(`https://api.github.com/repos/${repo}/releases?per_page=30`, { headers });
    if (!res.ok) throw new Error(`github releases fetch: ${res.status}`);
    const releases = await res.json();
    if (!Array.isArray(releases) || releases.length === 0) throw new Error("no releases");

    const hasIpa = (r) => (r.assets || []).some((a) => a.name === IPA_NAME);
    // Prefer the rolling adhoc-latest tag, then any release that carries an IPA.
    const r =
        releases.find((x) => x.tag_name === "adhoc-latest" && hasIpa(x)) ||
        releases.find(hasIpa) ||
        releases[0];

    const assets = r.assets || [];
    const ipa = assets.find((a) => a.name === IPA_NAME);

    // The release build publishes app-version.json carrying the real marketing
    // version + build number (the tag itself is just "adhoc-latest").
    let appVersion = null;
    const versionAsset = assets.find((a) => a.name === "app-version.json");
    if (versionAsset) {
        try {
            const vr = await fetch(versionAsset.browser_download_url, { headers });
            if (vr.ok) appVersion = await vr.json();
        } catch { /* fall back to tag-derived label */ }
    }

    return { tagName: r.tag_name, releaseUrl: r.html_url, publishedAt: r.published_at, ipa, appVersion };
}

function manifestPlist(ipaUrl, tag) {
    return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key>
          <string>software-package</string>
          <key>url</key>
          <string>${ipaUrl}</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key>
        <string>${BUNDLE_ID}</string>
        <key>bundle-version</key>
        <string>${tag}</string>
        <key>kind</key>
        <string>software</string>
        <key>title</key>
        <string>${APP_TITLE}</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
`;
}

const mb = (bytes) => (bytes ? (bytes / 1048576).toFixed(1) + " MB" : "");

async function build() {
    const r = await fetchRelease();
    if (!r.ipa) throw new Error(`no ${IPA_NAME} found in releases for ${repo}`);
    const version = (r.tagName || "").replace(/^v/, "");
    const updated = (r.publishedAt || "").slice(0, 10);
    const size = mb(r.ipa.size);
    const ipaUrl = r.ipa.browser_download_url;
    const manifestUrl = `itms-services://?action=download-manifest&url=${siteOrigin}/ios/manifest.plist`;

    // Prefer the real marketing version + build from app-version.json; fall back
    // to the tag, then "Beta" for a rolling tag like "adhoc-latest".
    const av = r.appVersion;
    const versionLabel = av?.shortVersion
        ? `v${av.shortVersion} (build ${av.build})`
        : (/^v?\d/.test(version) ? `v${version.replace(/^v/, "")}` : "Beta");
    const label = av?.shortVersion ? `v${av.shortVersion} (${av.build})` : versionLabel;

    const iosMeta = [versionLabel, "iOS 16+", size, updated && `updated ${updated}`]
        .filter(Boolean).join(" · ");

    const releaseData = {
        version: av?.shortVersion || version,
        build: av?.build || null,
        label,
        versionLabel,
        channel: "beta",
        updated,
        releaseUrl: r.releaseUrl,
        ios: { manifestUrl, ipaUrl, minOS: "iOS 16+", size },
    };
    const json = JSON.stringify(releaseData, null, 2);

    let html = await readFile(templatePath, "utf8");
    html = html
        .replaceAll("{{INSTALL_HREF}}", manifestUrl)
        .replaceAll("{{IPA_HREF}}", ipaUrl)
        .replaceAll("{{RELEASE_HREF}}", r.releaseUrl)
        .replaceAll("{{IOS_META}}", iosMeta)
        .replace(
            /(<script type="application\/json" id="release-data">)[\s\S]*?(<\/script>)/,
            `$1\n${json}\n$2`,
        );
    html = html.replace(/(<span data-version[^>]*>)[^<]*(<\/span>)/g, `$1${label}$2`);

    await mkdir(outDir, { recursive: true });
    await mkdir(path.join(outDir, "ios"), { recursive: true });
    await mkdir(path.join(outDir, "assets"), { recursive: true });

    await writeFile(path.join(outDir, "index.html"), html);
    await writeFile(path.join(outDir, "version.json"), json + "\n");
    await writeFile(path.join(outDir, "ios", "manifest.plist"), manifestPlist(ipaUrl, r.tagName));

    // Static privacy policy page — no templating needed. Written both as
    // privacy.html and privacy/index.html so it resolves whether or not the
    // host strips the .html extension from clean URLs.
    if (existsSync(privacyPath)) {
        const privacyHtml = await readFile(privacyPath, "utf8");
        await mkdir(path.join(outDir, "privacy"), { recursive: true });
        await writeFile(path.join(outDir, "privacy.html"), privacyHtml);
        await writeFile(path.join(outDir, "privacy", "index.html"), privacyHtml);
    }

    for (const name of await readdir(assetsSrc)) {
        await copyFile(path.join(assetsSrc, name), path.join(outDir, "assets", name));
    }
    if (existsSync(deployYaml)) await copyFile(deployYaml, path.join(outDir, ".deploy.yaml"));

    console.log(`wrote out/index.html · release ${r.tagName} · iOS ${size || "—"}`);
}

build().catch((e) => { console.error(e); process.exit(1); });
