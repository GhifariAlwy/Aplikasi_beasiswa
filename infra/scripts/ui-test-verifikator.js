#!/usr/bin/env node
/**
 * Browser E2E verifikator: login internal → antrian /verifikasi → buka detail
 * DEMO-DIAJUKAN → tandai semua dokumen "Sesuai" → keputusan DISETUJUI →
 * "Simpan Keputusan" (accept window.confirm) → baris hilang dari antrian.
 *
 * Usage: node infra/scripts/ui-test-verifikator.js [kode_pendaftaran]
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
const KODE = process.argv[2] || 'DEMO-DIAJUKAN';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pptr-'));
  const browser = await puppeteer.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: false,
    defaultViewport: null,
    args: ['--window-size=1366,950'],
    userDataDir: tmp,
  });
  const page = await browser.newPage();
  page.setDefaultTimeout(20_000);
  // window.confirm di VerificationModal HARUS di-accept, kalau tidak keputusan batal.
  page.on('dialog', (dialog) => {
    console.log('OK   dialog:', dialog.message());
    void dialog.accept();
  });

  const fail = async (msg) => {
    console.error('FAIL:', msg);
    await page.screenshot({ path: '/tmp/ui-verifikator-fail.png' }).catch(() => {});
    await browser.close();
    process.exit(1);
  };

  try {
    // ---------- login internal sebagai verifikator ----------
    await page.goto(`${BASE}/login-internal`, { waitUntil: 'networkidle0' });
    await page.type('input.form-control', 'verifikator', { delay: 10 });
    await page.type('input[type=password]', 'Password123!', { delay: 10 });
    await page.click('button.btn-primary');
    try {
      await page.waitForFunction(() => location.pathname === '/verifikasi', { timeout: 15_000 });
    } catch {
      console.error(
        'DEBUG setelah login:',
        await page.evaluate(() => location.pathname),
        (await page.evaluate(() => document.body.innerText)).slice(0, 250),
      );
      await fail('login internal tidak berpindah ke /verifikasi');
    }
    console.log('OK   login verifikator → /verifikasi');

    // ---------- cari baris DEMO-DIAJUKAN di antrian ----------
    try {
      await page.waitForFunction(
        (kode) => [...document.querySelectorAll('td')].some((td) => td.innerText.trim() === kode),
        { timeout: 15_000 },
        KODE,
      );
    } catch {
      await fail(`baris ${KODE} tidak muncul di antrian (status bukan DIAJUKAN?)`);
    }
    console.log(`OK   ${KODE} tampil di antrian`);

    // ---------- buka modal Periksa ----------
    await page.evaluate((kode) => {
      const row = [...document.querySelectorAll('tbody tr')].find((tr) =>
        [...tr.querySelectorAll('td')].some((td) => td.innerText.trim() === kode),
      );
      const button = row?.querySelector('button.btn-primary');
      if (button) button.click();
    }, KODE);
    try {
      await page.waitForFunction(
        (kode) => document.body.innerText.includes(`Detail Verifikasi — ${kode}`),
        { timeout: 10_000 },
        KODE,
      );
    } catch {
      await fail('modal verifikasi tidak terbuka');
    }
    console.log('OK   modal detail terbuka');

    // ---------- tandai semua dokumen "Sesuai" (radio pertama tiap kartu) ----------
    const cards = await page.$$('.modal-body .border.rounded');
    if (cards.length < 4) await fail(`butuh 4 kartu dokumen, ditemukan ${cards.length}`);
    for (const card of cards) {
      const radios = await card.$$('input[type=radio]');
      if (radios.length < 2) await fail('radio Sesuai/Tidak Sesuai tidak lengkap');
      await radios[0].click(); // "Sesuai"
    }
    await sleep(300);
    const sesuaiCount = await page.evaluate(
      () =>
        [...document.querySelectorAll('.modal-body .border.rounded')].filter((card) => {
          const radio = card.querySelector('input[type=radio]');
          return radio && radio.checked;
        }).length,
    );
    console.log(`OK   ${sesuaiCount}/4 dokumen ditandai Sesuai`);

    // ---------- keputusan DISETUJUI (sudah default, klik eksplisit) ----------
    await page.evaluate(() => {
      const label = [...document.querySelectorAll('.modal-body label.form-check')].find((el) =>
        el.innerText.trim().startsWith('Disetujui'),
      );
      const radio = label?.querySelector('input[type=radio]');
      if (radio) radio.click();
    });

    // ---------- Simpan Keputusan ----------
    await page.evaluate(() => {
      const button = [...document.querySelectorAll('.modal-footer button')].find((el) =>
        el.innerText.includes('Simpan Keputusan'),
      );
      if (!button) throw new Error('tombol Simpan Keputusan tidak ada');
      if (button.disabled) throw new Error('tombol Simpan Keputusan masih disabled');
      button.click();
    });
    // modal tertutup setelah sukses + invalidate query
    try {
      await page.waitForFunction(
        (kode) => !document.body.innerText.includes(`Detail Verifikasi — ${kode}`),
        { timeout: 15_000 },
        KODE,
      );
    } catch {
      const alert = await page.evaluate(
        () => document.querySelector('.modal-body .alert-danger')?.innerText ?? null,
      );
      await fail('modal tidak tertutup setelah simpan' + (alert ? `: ${alert}` : ''));
    }
    console.log('OK   keputusan DISETUJUI tersimpan, modal tertutup');

    // ---------- baris hilang dari antrian (status bukan lagi DIAJUKAN) ----------
    try {
      await page.waitForFunction(
        (kode) =>
          ![...document.querySelectorAll('td')].some((td) => td.innerText.trim() === kode),
        { timeout: 15_000 },
        KODE,
      );
    } catch {
      await fail(`${KODE} masih tampil di antrian (queue tidak ter-refresh)`);
    }
    console.log(`OK   ${KODE} keluar dari antrian verifikasi`);
    await page.screenshot({ path: '/tmp/ui-verifikator.png' });
    console.log('PASS verifikator DISETUJUI via UI');
    await browser.close();
  } catch (err) {
    await fail(err && err.stack ? err.stack : String(err));
  }
}

main().catch((err) => {
  console.error('FATAL:', err);
  process.exit(1);
});
