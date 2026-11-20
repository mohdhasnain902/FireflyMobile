import asyncio
from playwright.async_api import async_playwright

URL = "https://rapidnative-app-5sp3w.rapidnative.dev/"
OUT = "/mnt/data/Projects/firefly_III/docs"

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        ctx = await browser.new_context(viewport={"width": 390, "height": 844})
        page = await ctx.new_page()
        await page.goto(URL, wait_until="domcontentloaded", timeout=30000)
        await page.screenshot(path=f"{OUT}/demo_login.png", full_page=True)

        # Fill email
        await page.locator('input').nth(0).fill("test@test.com")
        await page.locator('input').nth(1).fill("password123")
        await page.wait_for_timeout(500)
        await page.screenshot(path=f"{OUT}/demo_filled.png", full_page=True)

        # Try clicking any button
        btns = await page.locator('button').all()
        print("num buttons:", len(btns))
        for b in btns:
            try:
                await b.click(timeout=3000)
                break
            except Exception:
                pass
        await page.wait_for_timeout(4000)
        await page.screenshot(path=f"{OUT}/demo_after_login.png", full_page=True)

        # Scroll and capture
        for i in range(4):
            await page.screenshot(path=f"{OUT}/demo_screen_{i}.png", full_page=False)
            await page.mouse.wheel(0, 700)
            await page.wait_for_timeout(900)

        await browser.close()
        print("done")

asyncio.run(main())
