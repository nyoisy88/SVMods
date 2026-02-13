import { writeFileSync } from 'fs';
import { createAuthenticatedPage } from './auth.js';

const NEXUS_ORIGIN = 'https://www.nexusmods.com';
const TIMEOUT_MS = 15000;
const SELECTORS = {
    slowDownloadButton: 'button:has-text("Slow download")',
    nxmLink: '.donation-wrapper a[href^="nxm://"]'
};


function buildDownloadUrl(gameDomain, modId, fileId) {
    return (
        `${NEXUS_ORIGIN}/${gameDomain}/mods/${modId}` +
        `?tab=files&file_id=${fileId}&nmm=1`
    );
}

async function getKeyAndExpire(gameDomain, modId, fileId) {
    let { browser, page } = await createAuthenticatedPage();
    try {
        const url = buildDownloadUrl(gameDomain, modId, fileId);
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: TIMEOUT_MS });

        // const usedcookies = await context.cookies();
        // fs.writeFileSync("./usedcookies.json", JSON.stringify(usedcookies, null, 2));

        // Check if Cloudflare is presenting a CAPTCHA challenge
        const title = await page.title();

        if (title.includes('Just a moment')) {
            throw new Error('Cloudflare challenge detected');
        }

        try {
            await page.waitForSelector(
                SELECTORS.slowDownloadButton,
                { timeout: TIMEOUT_MS }
            );
            await page.click(SELECTORS.slowDownloadButton);

            await page.waitForSelector(
                SELECTORS.nxmLink,
                { timeout: TIMEOUT_MS }
            );
        } catch (err) {
            await page.screenshot({ path: './debug-failure.png', fullPage: true });
            const html = await page.content();
            writeFileSync('./debug-failure.html', html, 'utf8');
            throw err;
        }

        const result = await page.evaluate(() => {
            const link = document.querySelector(
                '.donation-wrapper a[href^="nxm://"]'
            );
            if (!link) return null;

            const u = new URL(link.href);
            return {
                key: u.searchParams.get('key'),
                expires: u.searchParams.get('expires'),
                downloadUrl: link.href
            };
        });

        return result;
    } finally {
        await browser.close();
    }
}

(async () => {
    const [gameDomain, modId, fileId] = process.argv.slice(2);
    if (!gameDomain || !modId || !fileId) {
        console.error('Usage: node getNxmKey.js <gameDomain> <modId> <fileId>');
        process.exit(1);
    }

    const data = await getKeyAndExpire(gameDomain, modId, fileId);
    if (!data) {
        console.error('Extraction failed');
        process.exit(1);
    }

    console.log(JSON.stringify(data));
})();
