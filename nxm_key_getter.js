const { chromium } = require('playwright');
const fs = require('fs');

const COOKIES_PATH = './cookies.json';
const NEXUS_ORIGIN = 'https://www.nexusmods.com';
const TIMEOUT_MS = 15000;
const SELECTORS = {
    slowDownloadButton: 'button:has-text("Slow download")',
    nxmLink: '.donation-wrapper a[href^="nxm://"]'
};

function normalizeCookies(cookiesJson) {
    if (!cookiesJson) return [];
    const rawCookies = Array.isArray(cookiesJson)
        ? cookiesJson
        : (cookiesJson.cookies || []);
    if (!Array.isArray(rawCookies)) return [];

    return rawCookies
        .filter(c => c && c.name && c.value && c.domain)
        .map(c => ({
            name: c.name,
            value: c.value,
            domain: c.domain,
            path: c.path || '/',
            expires: typeof c.expirationDate === 'number'
                ? Math.floor(c.expirationDate)
                : typeof c.expires === 'number'
                    ? Math.floor(c.expires)
                    : undefined,
            httpOnly: Boolean(c.httpOnly),
            secure: Boolean(c.secure),
            sameSite:
                typeof c.sameSite === 'string'
                    ? (
                        c.sameSite.toLowerCase() === 'lax'
                            ? 'Lax'
                            : c.sameSite.toLowerCase() === 'strict'
                                ? 'Strict'
                                : ['none', 'no_restriction', 'no-restriction']
                                    .includes(c.sameSite.toLowerCase())
                                    ? 'None'
                                    : undefined
                    )
                    : undefined
        }));
}

function loadCookiesFromFile() {
    if (!fs.existsSync(COOKIES_PATH)) return [];
    try {
        const cookiesJson = JSON.parse(
            fs.readFileSync(COOKIES_PATH, 'utf8')
        );
        return normalizeCookies(cookiesJson);
    } catch {
        return [];
    }
}

function buildDownloadUrl(gameDomain, modId, fileId) {
    return (
        `${NEXUS_ORIGIN}/${gameDomain}/mods/${modId}` +
        `?tab=files&file_id=${fileId}&nmm=1`
    );
}

async function getKeyAndExpire(gameDomain, modId, fileId) {
    const cookies = loadCookiesFromFile();
    const hasCookies = cookies.length > 0;
    const browser = await chromium.launch({
        headless: false,
        // args: [
        //     '--window-position=-32000,-32000',
        // ]
    });
    let context;
    try {
        context = await browser.newContext({
            // Real users don’t have consistent viewports — this helps avoid fingerprint mismatches
            viewport: {
                width: 1280 + Math.floor(Math.random() * 100), // Randomize a bit
                height: 720 + Math.floor(Math.random() * 100),
            },
            userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36", // Use a real user-agent, ideally from your proxy location
            locale: "en", // Match browser locale to IP region
            timezoneId: "Asia/Bangkok", // Timezone mismatches are a red flag in Cloudflare fingerprinting
        });
        // On future runs, restore session to avoid challenges/login
        // const savedCookies = JSON.parse(fs.readFileSync("./savedcookies.json"));
        // await context.addCookies(savedCookies);

        if (!hasCookies) {
            throw new Error('Required logged-in cookies for mods updater.');
        }
        await context.addCookies(cookies);
        const page = await context.newPage();

        const url = buildDownloadUrl(gameDomain, modId, fileId);
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: TIMEOUT_MS });

        // const usedcookies = await context.cookies();
        // fs.writeFileSync("./usedcookies.json", JSON.stringify(usedcookies, null, 2));

        // Check if Cloudflare is presenting a CAPTCHA challenge
        const isCaptchaPresent = await page.$('iframe[src*="captcha"]');

        if (isCaptchaPresent) {
            throw new Error("CAPTCHA detected – will need to solve or switch proxy");
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
            fs.writeFileSync('./debug-failure.html', html, 'utf8');
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
        console.error('Usage: node nxm_key_getter.js <gameDomain> <modId> <fileId>');
        process.exit(1);
    }

    const data = await getKeyAndExpire(gameDomain, modId, fileId);
    if (!data) {
        console.error('Extraction failed');
        process.exit(1);
    }

    console.log(JSON.stringify(data));
})();
