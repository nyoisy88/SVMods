import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';

const COOKIES_PATH = './cookies.json';

function coerceSameSite(value) {
    if (typeof value !== 'string') return undefined;

    const normalized = value.toLowerCase();
    if (normalized === 'lax') return 'Lax';
    if (normalized === 'strict') return 'Strict';
    if (['none', 'no_restriction', 'no-restriction'].includes(normalized)) return 'None';

    return undefined;
}

function normalizeCookies(cookiesJson) {
    if (!cookiesJson) return [];

    const rawCookies = Array.isArray(cookiesJson)
        ? cookiesJson
        : (cookiesJson.cookies || []);

    if (!Array.isArray(rawCookies)) return [];

    const nowEpoch = Math.floor(Date.now() / 1000);

    return rawCookies
        .filter(cookie => cookie && cookie.name && cookie.value && cookie.domain)
        .map(cookie => {
            const expires = typeof cookie.expirationDate === 'number'
                ? Math.floor(cookie.expirationDate)
                : typeof cookie.expires === 'number'
                    ? Math.floor(cookie.expires)
                    : undefined;

            return {
                name: String(cookie.name).trim(),
                value: String(cookie.value),
                domain: String(cookie.domain).trim(),
                path: cookie.path || '/',
                expires,
                httpOnly: Boolean(cookie.httpOnly),
                secure: Boolean(cookie.secure),
                sameSite: coerceSameSite(cookie.sameSite),
            };
        })
        .filter(cookie => cookie.name && cookie.value && cookie.domain)
        .filter(cookie => {
            // Keep session cookies and unexpired cookies only.
            if (typeof cookie.expires !== 'number' || cookie.expires <= 0) return true;
            return cookie.expires > nowEpoch;
        });
}

function loadCookiesFromFile(cookiesPath = COOKIES_PATH) {
    const resolvedPath = path.resolve(cookiesPath);

    if (!fs.existsSync(resolvedPath)) {
        throw new Error(`Cookies file not found: ${resolvedPath}`);
    }

    let parsed;
    try {
        parsed = JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(`Failed to parse cookies JSON (${resolvedPath}): ${message}`);
    }

    const cookies = normalizeCookies(parsed);

    if (cookies.length === 0) {
        throw new Error(`No usable cookies found in ${resolvedPath}.`);
    }

    const hasNexusCookie = cookies.some(cookie =>
        cookie.domain === 'nexusmods.com' || cookie.domain.endsWith('.nexusmods.com')
    );

    if (!hasNexusCookie) {
        throw new Error(`Cookies file does not contain nexusmods.com cookies: ${resolvedPath}`);
    }

    return cookies;
}

export async function createAuthenticatedPage() {
    const cookies = loadCookiesFromFile();

    const browser = await chromium.launch({
        headless: false,
    });

    try {
        const context = await browser.newContext({
            // Randomize viewport slightly to avoid stable fingerprint artifacts.
            viewport: {
                width: 1280 + Math.floor(Math.random() * 100),
                height: 720 + Math.floor(Math.random() * 100),
            },
            userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36',
            locale: 'en',
            timezoneId: 'Asia/Bangkok',
        });

        await context.addCookies(cookies);
        const page = await context.newPage();

        return { browser, context, page };
    } catch (error) {
        await browser.close().catch(() => {});
        throw error;
    }
}
