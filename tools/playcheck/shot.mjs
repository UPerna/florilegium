// Take the README's screenshot of the playground (gallery/playground.png): the page at 1200 x 750
// once its garden has grown. Serve the repository first (make playground), then:
//   cd tools/playcheck && npm install && node shot.mjs [url] [out.png]
// The default is seed 12 in autumn on a last page; CHROME=/path/to/chrome if it is not
// /usr/bin/chromium. The README's copy is then optimized: optipng -o2 out.png
// Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
import puppeteer from 'puppeteer-core'
const url = process.argv[2] || 'http://localhost:8000/web/#seed=12&season=autumn&last=1'
const out = process.argv[3] || 'playground.png'
const browser = await puppeteer.launch({ executablePath: process.env.CHROME || '/usr/bin/chromium', headless: 'new', args: ['--no-sandbox'] })
const page = await browser.newPage()
await page.setViewport({ width: 1200, height: 750, deviceScaleFactor: 1 })
await page.goto(url, { waitUntil: 'networkidle0' })
// the garden has grown when the proof is no longer marked growing and its image has loaded
await page.waitForFunction(() => {
  const proof = document.querySelector('#proof'), img = document.querySelector('#garden')
  return proof && !proof.classList.contains('growing') && img && img.complete && img.naturalWidth > 0
}, { timeout: 120000, polling: 500 })
await new Promise((resolve) => setTimeout(resolve, 1500))   // the page text fades in
await page.screenshot({ path: out })
console.log(`${out}: ${await page.evaluate(() => document.querySelector('#grown').textContent)}`)
await browser.close()
