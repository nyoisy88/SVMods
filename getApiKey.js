import { createAuthenticatedPage } from './auth.js';

const API_KEY_URL = 'https://www.nexusmods.com/settings/api-keys';
const TIMEOUT_MS = 15000;

function normalizeApiKey(rawValue) {
    return String(rawValue ?? '').trim();
}

function isLikelyApiKey(apiKey) {
    return apiKey.length >= 16 && !/\s/.test(apiKey);
}

let browser;

try {
    const session = await createAuthenticatedPage();
    browser = session.browser;
    const page = session.page;

    await page.goto(API_KEY_URL, {
        waitUntil: 'domcontentloaded',
        timeout: TIMEOUT_MS,
    });

    const title = await page.title();
    if (title.includes('Just a moment')) {
        throw new Error('Cloudflare challenge detected. Complete challenge manually and retry.');
    }

    const apiKeyInput = page.locator('input[readonly]').first();
    await apiKeyInput.waitFor({ state: 'visible', timeout: TIMEOUT_MS });

    const apiKey = normalizeApiKey(await apiKeyInput.inputValue());

    if (!apiKey) {
        throw new Error('API key field is empty. Confirm account access and key generation status.');
    }

    if (!isLikelyApiKey(apiKey)) {
        throw new Error(`API key has unexpected format (length=${apiKey.length}).`);
    }

    // stdout is intentionally only the raw key for automation callers.
    console.log(apiKey);
} catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[getApiKey] ${message}`);
    process.exitCode = 1;
} finally {
    if (browser) {
        await browser.close().catch(() => {});
    }
}
