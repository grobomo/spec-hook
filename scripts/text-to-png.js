#!/usr/bin/env node
// Convert text file to PNG screenshot using canvas
// Usage: node text-to-png.js input.txt output.png [title]

const fs = require('fs');
const path = require('path');

// Try to use canvas if available, otherwise generate an HTML file for screenshot
const inputFile = process.argv[2];
const outputFile = process.argv[3];
const title = process.argv[4] || path.basename(inputFile, '.txt');

if (!inputFile || !outputFile) {
  console.error('Usage: node text-to-png.js input.txt output.png [title]');
  process.exit(1);
}

const text = fs.readFileSync(inputFile, 'utf-8')
  .replace(/\x1b\[[0-9;]*m/g, '') // Strip ANSI codes
  .replace(/\r/g, '');

// Generate HTML that looks like a terminal
const html = `<!DOCTYPE html>
<html><head><style>
  body { margin: 0; padding: 0; background: #1e1e2e; }
  .terminal {
    font-family: 'Cascadia Code', 'Fira Code', 'Consolas', monospace;
    font-size: 13px;
    line-height: 1.5;
    color: #cdd6f4;
    background: #1e1e2e;
    padding: 20px 24px;
    white-space: pre;
    min-width: 800px;
  }
  .title-bar {
    background: #313244;
    color: #a6adc8;
    padding: 8px 16px;
    font-family: 'Segoe UI', sans-serif;
    font-size: 13px;
    border-radius: 8px 8px 0 0;
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .dots { display: flex; gap: 6px; }
  .dot { width: 12px; height: 12px; border-radius: 50%; }
  .dot-r { background: #f38ba8; }
  .dot-y { background: #f9e2af; }
  .dot-g { background: #a6e3a1; }
  .content { border-radius: 0 0 8px 8px; overflow: hidden; }
</style></head><body>
<div style="padding: 16px; background: #11111b;">
  <div class="title-bar">
    <div class="dots"><div class="dot dot-r"></div><div class="dot dot-y"></div><div class="dot dot-g"></div></div>
    <span>${title}</span>
  </div>
  <div class="content">
    <div class="terminal">${text
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/\[OK\]/g, '<span style="color:#a6e3a1">[OK]</span>')
      .replace(/PASS:/g, '<span style="color:#a6e3a1">PASS:</span>')
      .replace(/FAIL:/g, '<span style="color:#f38ba8">FAIL:</span>')
      .replace(/ALL PASSED/g, '<span style="color:#a6e3a1;font-weight:bold">ALL PASSED</span>')
      .replace(/=== (.*?) ===/g, '<span style="color:#89b4fa;font-weight:bold">=== $1 ===</span>')
    }</div>
  </div>
</div>
</body></html>`;

// Write HTML, then use playwright/puppeteer to screenshot, or just save HTML
const htmlPath = outputFile.replace(/\.png$/, '.html');
fs.writeFileSync(htmlPath, html);
console.log(`HTML: ${htmlPath}`);

// Try puppeteer/playwright for PNG
(async () => {
  try {
    // Try playwright first
    const { chromium } = require('playwright');
    const browser = await chromium.launch();
    const page = await browser.newPage();
    await page.setViewportSize({ width: 900, height: 100 });
    await page.setContent(html);
    const body = await page.$('body');
    await body.screenshot({ path: outputFile });
    await browser.close();
    console.log(`PNG: ${outputFile}`);
  } catch(e1) {
    try {
      // Try puppeteer
      const puppeteer = require('puppeteer');
      const browser = await puppeteer.launch({ headless: true });
      const page = await browser.newPage();
      await page.setViewport({ width: 900, height: 100 });
      await page.setContent(html);
      const body = await page.$('body');
      await body.screenshot({ path: outputFile });
      await browser.close();
      console.log(`PNG: ${outputFile}`);
    } catch(e2) {
      console.log('No browser engine available. Use HTML files for screenshots.');
      console.log('Install: npm i -g playwright && npx playwright install chromium');
    }
  }
})();
