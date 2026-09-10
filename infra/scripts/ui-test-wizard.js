#!/usr/bin/env node
/**
 * Browser E2E: login as demo.peserta1 → /pendaftaran wizard → unggah dokumen via
 * <input type=file> asli → lanjut ke Ringkasan → "Kirim Final" → status DIAJUKAN.
 * State-aware: wizard dibuka di step mana pun (resume dari section_terakhir), script
 * hanya menyelesaikan bagian yang belum selesai, seperti pengguna sungguhan.
 *
 * Usage: node infra/scripts/ui-test-wizard.js [step3|fullsubmit]
 */
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

function loadPuppeteer() {
  for (const candidate of ['puppeteer-core', '/opt/homebrew/lib/node_modules/puppeteer-core']) {
    try {
      return require(candidate);
    } catch {
      /* coba jalur berikutnya */
    }
  }
  console.error('puppeteer-core tidak ditemukan. Pasang: npm i -g puppeteer-core');
  process.exit(1);
}
const puppeteer = loadPuppeteer();

const BASE = process.env.UI_TEST_BASE || 'http://localhost:5173';
const MODE = process.argv[2] || 'fullsubmit';
const PASS = 'Password123!';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function writePdf(name, note) {
  const file = `/tmp/wizard-${name}.pdf`;
  fs.writeFileSync(file, `%PDF-1.4\n% ${note}\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n`);
  return file;
}

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pptr-'));
  const browser = await puppeteer.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: false, // terlihat supaya alur bisa diikuti
    defaultViewport: null,
    args: ['--window-size=1280,900'],
    userDataDir: tmp, // profil bersih, tidak menyentuh cookie browser pengguna
  });
  const page = await browser.newPage();
  page.setDefaultTimeout(20_000);

  const fail = async (msg) => {
    console.error('FAIL:', msg);
    await page.screenshot({ path: '/tmp/ui-test-fail.png' }).catch(() => {});
    await browser.close();
    process.exit(1);
  };
  const activeTab = () =>
    page.evaluate(
      () =>
        [...document.querySelectorAll('div.card-header button.col')].findIndex((b) =>
          b.className.includes('fw-bold'),
        ) + 1,
    );
  const clickByText = (text) =>
    page.evaluate((t) => {
      const btn = [...document.querySelectorAll('button')].find((b) => b.innerText.trim() === t);
      if (btn) {
        btn.click();
        return true;
      }
      return false;
    }, text);
  const waitTab = (n, timeout = 8_000) =>
    page
      .waitForFunction((tab) => {
        const buttons = [...document.querySelectorAll('div.card-header button.col')];
        return buttons[tab - 1]?.className.includes('fw-bold');
      }, { timeout }, n)
      .then(() => true)
      .catch(() => false);

  try {
    // ---------- login (channel publik) ----------
    await page.goto(`${BASE}/login`, { waitUntil: 'networkidle0' });
    await page.type('input.form-control', 'demo.peserta1', { delay: 10 });
    await page.type('input[type=password]', PASS, { delay: 10 });
    await page.click('button.btn-primary');
    try {
      await page.waitForFunction(() => location.pathname === '/dashboard', { timeout: 15_000 });
    } catch {
      console.error(
        'DEBUG halaman setelah klik Masuk:',
        await page.evaluate(() => location.pathname),
        (await page.evaluate(() => document.body.innerText)).slice(0, 300),
      );
      await fail('login tidak berpindah ke /dashboard');
    }
    console.log('OK   login demo.peserta1 → /dashboard');

    // ---------- buka wizard ----------
    await page.goto(`${BASE}/pendaftaran`, { waitUntil: 'networkidle0' });
    await page.waitForFunction(() => document.body.innerText.includes('Ringkasan & Persetujuan'));
    await sleep(1_200); // biarkan hydrasi data + reset form selesai
    let step = await activeTab();
    console.log('OK   wizard dibuka di step', step);

    // ---------- step 1: Data Diri (isi field kosong bila ada) ----------
    if (step === 1) {
      const demoText = [
        '3273010101010001', 'Demo Peserta Draft', 'Bandung', '2000-01-01',
        'Jl. Demo 1', 'Jawa Barat', 'Kota Bandung', 'Coblong', 'Dago',
        '081234567890', 'peserta1@demo.beasiswa.local',
      ];
      let di = 0;
      for (const input of await page.$$('.card-body input:not([type=checkbox])')) {
        const type = await input.evaluate((el) => el.type);
        if (type === 'radio' || (await input.evaluate((el) => el.value))) continue;
        const value = demoText[di] ?? 'Demo';
        di += 1;
        if (type === 'date') {
          await input.evaluate((el, val) => {
            const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
            setter?.call(el, val);
            el.dispatchEvent(new Event('input', { bubbles: true }));
          }, value);
        } else {
          await input.type(value, { delay: 5 });
        }
      }
      if (!(await clickByText('Selanjutnya'))) await fail('tombol Selanjutnya (step 1) tidak ada');
      if (!(await waitTab(2))) await fail('gagal maju ke step 2 (validasi step 1?)');
      step = 2;
      console.log('OK   step 1 tersimpan → step 2');
    }

    // ---------- step 2: Pendidikan ----------
    if (step === 2) {
      const select = await page.$('.card-body select');
      if (select && !(await select.evaluate((el) => el.value))) {
        await page.select('.card-body select', 'S1');
      }
      const demo2 = ['Universitas Demo', 'Teknik Informatika', 'Peserta'];
      let d2 = 0;
      for (const input of await page.$$('.card-body input:not([type=checkbox])')) {
        if (await input.evaluate((el) => el.value)) continue;
        await input.type(demo2[d2] ?? 'Demo', { delay: 5 });
        d2 += 1;
      }
      if (!(await clickByText('Selanjutnya'))) await fail('tombol Selanjutnya (step 2) tidak ada');
      if (!(await waitTab(3))) await fail('gagal maju ke step 3 (validasi step 2?)');
      step = 3;
      console.log('OK   step 2 tersimpan → step 3');
    }

    // ---------- step 3: Unggah dokumen (hanya kartu yang belum ada berkas) ----------
    if (step === 3) {
      const docNames = ['ktp', 'kk', 'ijazah', 'rekomendasi'];
      const cardsWithInput = await page.$$('.card-body .border.rounded');
      if (cardsWithInput.length < 4) await fail(`butuh 4 kartu dokumen, ditemukan ${cardsWithInput.length}`);
      let uploaded = 0;
      for (let i = 0; i < cardsWithInput.length; i++) {
        const card = cardsWithInput[i];
        const done = (await card.$('.text-success.small')) !== null;
        if (done) continue;
        const input = await card.$('input[type=file]');
        if (!input) await fail(`input file kartu ${i + 1} tidak ditemukan`);
        await input.uploadFile(writePdf(docNames[i] ?? `doc${i}`, docNames[i] ?? `doc${i}`));
        await page.waitForFunction(
          (idx) =>
            document.querySelectorAll('.card-body .border.rounded')[idx]?.querySelector('.text-success.small') !==
            null,
          { timeout: 25_000 },
          i,
        );
        uploaded += 1;
        console.log(`OK   dokumen ${i + 1} (${docNames[i] ?? i}) terunggah via UI`);
      }
      if (uploaded === 0) console.log('OK   semua dokumen sudah terunggah sebelumnya');
      if (!(await clickByText('Selanjutnya'))) await fail('tombol Selanjutnya (step 3) tidak ada');
      if (!(await waitTab(4))) await fail('gagal maju ke step 4');
      step = 4;
      console.log('OK   section 3 tersimpan → step 4 (Ringkasan)');
    }

    if (MODE === 'step3') {
      await page.screenshot({ path: '/tmp/ui-wizard-step3.png' });
      console.log('PASS dokumen via UI (section 3 tersimpan)');
      await browser.close();
      return;
    }

    // ---------- step 4: Ringkasan + Kirim Final ----------
    const consent = await page.$('#consent');
    if (!consent) await fail('checkbox persetujuan (#consent) tidak ditemukan');
    const checked = await consent.evaluate((el) => el.checked);
    if (!checked) await consent.click();
    await page.click('button.btn-success'); // "Kirim Final"

    const outcome = await page
      .waitForFunction(
        () => {
          if (document.body.innerText.includes('DIAJUKAN')) return 'diajukan';
          const el = document.querySelector('.alert-danger, .alert-warning');
          return el ? el.innerText.trim() : null;
        },
        { timeout: 25_000, polling: 500 },
      )
      .then((h) => h.jsonValue());
    if ((await outcome) !== 'diajukan') {
      await fail('submit gagal: ' + (await outcome));
    }
    console.log('OK   status DIAJUKAN terlihat di dashboard');
    await page.screenshot({ path: '/tmp/ui-wizard-submit.png' });
    console.log('PASS full submit via UI');
    await browser.close();
  } catch (err) {
    await fail(err && err.stack ? err.stack : String(err));
  }
}

main().catch((err) => {
  console.error('FATAL:', err);
  process.exit(1);
});
