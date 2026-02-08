const ecfr = require("./ecfr");

async function run() {
    const slug = "transportation-department"; // Correct slug

    // Test 1: Recent Amendments
    console.log(`\n--- Fetching Amendments for ${slug} ---`);
    try {
        const amendments = await ecfr.fetchRecentAmendments(slug);
        console.log(`Amendments Found: ${amendments.length}`);
        if (amendments.length > 0) {
            console.log("Sample Amendment:", JSON.stringify(amendments[0], null, 2));
        } else {
            console.warn("⚠️ No amendments found - Search API might be empty or failing silently.");
        }
    } catch (e) {
        console.error("❌ Amendments Fetch Failed:", e.message);
    }
}

run();
