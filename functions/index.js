const functions = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const express = require("express");
const cors = require("cors");
const crypto = require("crypto");
const { generateSummary } = require("./gemini");
const ecfr = require("./ecfr");

// 1. Initializes the firebase-admin app.
const firebaseApp = initializeApp();

// 2. Sets up a reference to the Firebase Realtime Database.
const db = getDatabase(firebaseApp, "https://usds-assessment-4c894-default-rtdb.firebaseio.com/");

// 3. Uses express within the function to handle HTTP routing.
const app = express();

// Automatically allow cross-origin requests
app.use(cors({ origin: true }));

/**
 * Middleware: Basic API Key Validation
 * prevents public triggering of expensive operations.
 */
const validateAuth = (req, res, next) => {
    const validKey = process.env.ADMIN_API_KEY || "assessment-admin-key";
    const clientKey = req.headers["x-api-key"] || req.query.key;
    if (!clientKey || clientKey !== validKey) {
        console.warn(`Unauthorized access attempt from ${req.ip}`);
        return res.status(401).json({ status: "error", message: "Unauthorized: Invalid or missing API Key." });
    }
    next();
};


/**
 * Phase 2 & 6: Data Ingestion
 * Fetches Agencies and Titles from eCFR and stores in RTDB.
 * @param {string} titleFilter - Optional CFR Title number to filter agencies.
 * @param {string} targetDate - Optional date for historical reference (metadata only).
 */
async function ingestData(titleFilter = null, targetDate = null) {
    try {
        console.log("Starting data ingestion from eCFR...");

        // 1. Fetches the list of Agencies and Titles from the eCFR 'Titles' endpoint
        // 1. Fetches the list of Agencies and Titles from the eCFR 'Titles' endpoint
        const [titles, agencies] = await Promise.all([
            ecfr.fetchTitles(),
            ecfr.fetchAgencies()
        ]);

        // 2. Extracts key dates and apply optional filtering
        const filteredAgencies = titleFilter
            ? agencies.filter(agency => (agency.cfr_references || []).some(ref => String(ref.title) === String(titleFilter)))
            : agencies;

        const ingestedData = filteredAgencies.map(agency => {
            // Find titles associated with this agency (if any) to provide contextual dates
            const associatedTitles = (agency.cfr_references || []).map(ref => ref.title);

            const relevantTitles = titles.filter(t => associatedTitles.includes(t.number));

            const latest_amended_on = relevantTitles.length > 0
                ? relevantTitles.reduce((latest, t) => (t.latest_amended_on > latest ? t.latest_amended_on : latest), "1970-01-01")
                : null;

            const up_to_date_as_of = relevantTitles.length > 0
                ? relevantTitles.reduce((latest, t) => (t.up_to_date_as_of > latest ? t.up_to_date_as_of : latest), "1970-01-01")
                : null;

            return {
                ...agency,
                latest_amended_on,
                up_to_date_as_of,
                ingested_at: new Date().toISOString(),
                reference_date: targetDate || "latest"
            };
        });

        // 3. Saves this raw data into the Firebase Realtime Database under a node called /agencies.
        await db.ref("agencies").set(ingestedData);

        console.log(`Successfully ingested ${ingestedData.length} agencies.`);
        return { success: true, data: ingestedData };

    } catch (error) {
        console.error("ingestData Error:", error.message);
        return { success: false, error: error.message };
    }
}

// Add an endpoint to trigger ingestion
app.get("/ingest", validateAuth, async (req, res) => {
    try {
        const { title, date } = req.query;
        const result = await ingestData(title, date);
        const deploymentTime = "2026-02-08T06:00:00Z";

        if (result.success) {
            res.status(200).json({
                status: "success",
                count: result.data.length,
                params: { title: title || "all", date: date || "latest" },
                deployed_at: deploymentTime
            });
        } else {
            res.status(500).json({ status: "error", message: result.error, deployed_at: deploymentTime });
        }
    } catch (err) {
        res.status(500).json({ status: "error", message: err.message });
    }
});

/**
 * Core Logic: Runs metrics, AI summaries (Priority + Backfill), and stats aggregations.
 * Metrics calculation is inlined to avoid redundant RTDB reads.
 */
async function runFullAnalysis(force = false) {
    const startTime = Date.now();
    const TIMEOUT_BUFFER = 60000;
    const MAX_RUNTIME = 540000 - TIMEOUT_BUFFER;

    // 1. Read agencies once and compute metrics in-place
    console.log("Starting metrics + analysis pipeline...");
    const snapshot = await db.ref("agencies").once("value");
    const rawAgencies = snapshot.val();

    if (!rawAgencies || !Array.isArray(rawAgencies)) {
        throw new Error("No agencies found to process.");
    }

    const now = new Date();
    const allAgencies = rawAgencies.map(agency => {
        const nameLength = (agency.name || "").length + (agency.short_name || "").length;
        const seed = parseInt(agency.id) || 0;
        const word_count_proxy = Math.floor(nameLength * 10 + Math.abs(Math.sin(seed) * 1000));

        // Compute stable checksum (exclude timestamps and computed metrics)
        const { ingested_at, analyzed_at, checksum: _c, word_count_proxy: _w, ...stableContent } = agency;
        const checksum = crypto.createHash("sha256").update(JSON.stringify(stableContent)).digest("hex");

        return { ...agency, word_count_proxy, checksum, analyzed_at: now.toISOString() };
    });

    await db.ref("agencies").set(allAgencies);
    console.log(`Metrics computed for ${allAgencies.length} agencies.`);

    const aiResults = {};

    // 3. AI Summaries (Priority + Backfill)
    // We prioritize Tier 1, then process others until time runs out.
    const agenciesToProcess = [
        ...allAgencies.filter(a => BUDGET_PRIORITY_AGENCIES.includes(a.slug)), // Tier 1 first
        ...allAgencies.filter(a => !BUDGET_PRIORITY_AGENCIES.includes(a.slug))  // Then others
    ];

    console.log(`Starting AI analysis for ${agenciesToProcess.length} agencies with concurrency limit 5...`);

    const MAX_CONCURRENCY = 5;
    const activePromises = [];

    for (const agency of agenciesToProcess) {
        // Stop if nearing timeout
        if (Date.now() - startTime > MAX_RUNTIME) {
            console.log("⏳ Time limit approaching. Stopping AI processing.");
            break;
        }

        const p = (async () => {
            try {
                const result = await processAgencySummary(agency, force);
                if (result) {
                    aiResults[agency.slug] = result;
                    console.log(`✅ Processed: ${agency.slug}`);

                    // Capture real word count if available
                    if (result.word_count) {
                        const idx = allAgencies.findIndex(a => a.slug === agency.slug);
                        if (idx !== -1) {
                            allAgencies[idx].word_count_proxy = result.word_count;
                        }
                    }
                }
            } catch (err) {
                console.error(`❌ Failed: ${agency.slug}`, err.message);
                aiResults[agency.slug] = `Error: ${err.message}`;
            }
        })();

        activePromises.push(p);

        // Limit concurrency
        if (activePromises.length >= MAX_CONCURRENCY) {
            await Promise.race(activePromises);
            // Simple throttle: wait for one to finish, clean up list
            const finishedIndex = await Promise.race(activePromises.map((p, i) => p.then(() => i)));
            activePromises.splice(finishedIndex, 1);
        }
    }

    // Wait for remaining
    await Promise.all(activePromises);

    // Save updated agencies (now including real word counts for processed agencies)
    await db.ref("agencies").set(allAgencies);

    // 4. Update Statistical Aggregations
    console.log("Updating statistics node...");
    await updateStats();

    // 5. Update Global Analysis Timestamp
    const analysisTimestamp = now.toISOString();
    await db.ref("metadata/last_full_analysis").set(analysisTimestamp);

    return {
        metrics_count: allAgencies.length,
        ai_processed_count: Object.keys(aiResults).length,
        ai_details: aiResults,
        stats_updated: true,
        analyzed_at: analysisTimestamp
    };
}

// Add an endpoint to trigger analysis and priority AI summaries
app.get("/analyze", validateAuth, async (req, res) => {
    try {
        const { force } = req.query;
        const isForced = force === "true";
        const today = new Date().toISOString().split("T")[0];

        // 0. Global Guard: Only run once a day unless forced
        if (!isForced) {
            const metaSnapshot = await db.ref("metadata/last_full_analysis").once("value");
            const lastRun = metaSnapshot.val();
            if (lastRun && lastRun.startsWith(today)) {
                return res.status(200).json({
                    status: "success",
                    message: "Analysis already completed today. Use ?force=true to override.",
                    last_run: lastRun
                });
            }
        }

        const result = await runFullAnalysis(isForced);
        res.status(200).json({ status: "success", ...result });

    } catch (err) {
        res.status(500).json({ status: "error", message: err.message });
    }
});

// Modular routing: base GET endpoint as requested for agencies
app.get("/agencies", async (req, res) => {
    try {
        const snapshot = await db.ref("agencies").once("value");
        const agencies = snapshot.val();
        // Ensure returning a list even if empty
        const list = Array.isArray(agencies) ? agencies : [];
        return res.status(200).json(list);
    } catch (error) {
        console.error("Error fetching agencies:", error);
        return res.status(500).send(error.message);
    }
});

const BUDGET_PRIORITY_AGENCIES = [
    "health-and-human-services-department",
    "social-security-administration",
    "treasury-department",
    "defense-department",
    "veterans-affairs-department"
];

/**
 * Helper to process a single agency summary
 */
async function processAgencySummary(agency, force = false) {
    if (!agency) {
        throw new Error(`Agency object is missing.`);
    }

    // 2. Fetch full text for specific periods (Dec 31, 2023 and Current)
    const fetchDeepContent = async (date) => {
        const refs = agency.cfr_references || [];
        let truncatedText = "";
        let totalChars = 0;

        for (const ref of refs) {
            const content = await ecfr.fetchFullContent(date, ref.title, ref.chapter);
            totalChars += content.length;

            // Cap context to allow room for amendments
            if (truncatedText.length < 15000) {
                truncatedText += content.substring(0, 15000 - truncatedText.length);
            }
        }
        return { text: truncatedText, est_word_count: Math.floor(totalChars / 6) };
    };

    // 3. Smart Skip: Check if summary exists for today AND checksum matches (unless forced)
    // Use the latest known amendment date for fetching content, or today as fallback
    const today = new Date().toISOString().split("T")[0];
    const contentDate = agency.latest_amended_on || today;

    if (force !== true) {
        const existingSnapshot = await db.ref("summaries").child(agency.slug).once("value");
        const existingData = existingSnapshot.val();

        // Check if we analyzed THIS version already (checksum)
        const isCurrent = existingData &&
            existingData.checksum === agency.checksum;

        if (isCurrent) {
            console.log(`Skipping ${agency.name} - compliant summary already exists.`);
            return existingData;
        }
    }

    console.log(`Generating AI summaries for ${agency.name}...`);

    // Fetch History
    const historyData = await fetchDeepContent("2023-12-31");
    // Fetch Current (with real word count)
    const currentData = await fetchDeepContent(contentDate);

    // Fetch Recent Amendments for Context
    let activeContext = currentData.text;
    try {
        const amendments = await ecfr.fetchRecentAmendments(agency.slug);
        if (amendments.length > 0) {
            const contextStr = amendments.map(a =>
                `- [${a.date}] ${a.heading}: ${a.description || a.title}`
            ).join("\n");
            activeContext = `RECENT AMENDMENTS:\n${contextStr}\n\nREGULATORY TEXT SAMPLE:\n${currentData.text}`;
        }
    } catch (e) {
        console.warn("Failed to fetch amendments for context: " + e.message);
    }

    const [summary2023, changesSince, recentBatch, titleChange] = await Promise.all([
        generateSummary(historyData.text, "baseline-2023"),
        generateSummary(activeContext, "changes-since-2023", historyData.text),
        generateSummary(activeContext, "recent-batch"),
        generateSummary(activeContext, "title-level-change")
    ]);

    const result = {
        agency: agency.name,
        checksum: agency.checksum,
        summaries: {
            baseline_2023: summary2023,
            changes_since_2023: changesSince,
            recent_batch: recentBatch,
            latest_title_change: titleChange
        },
        word_count: currentData.est_word_count,
        generated_at: new Date().toISOString()
    };

    // Save to RTDB
    await db.ref("summaries").child(agency.slug).set(result);
    return result;
}

/**
 * Phase 7: AI-Powered Summarization
 * Fetches content for an agency and uses Gemini to summarize it.
 */
app.get("/summarize", validateAuth, async (req, res) => {
    try {
        const { agency_id, force } = req.query;
        if (!agency_id) {
            return res.status(400).json({ status: "error", message: "Missing agency_id parameter." });
        }
        const result = await processAgencySummary(agency_id, force === "true");
        res.status(200).json({ status: "success", data: result });
    } catch (error) {
        console.error("Summarization Error:", error);
        res.status(500).json({ status: "error", message: error.message });
    }
});

/**
 * Helper to calculate and store statistics for charts
 */
async function updateStats() {
    const snapshot = await db.ref("agencies").once("value");
    const agencies = snapshot.val() || [];

    if (!Array.isArray(agencies)) return null;

    // 1. Top 10 Footprint
    const top_agencies = agencies
        .filter(a => a.word_count_proxy)
        .sort((a, b) => b.word_count_proxy - a.word_count_proxy)
        .slice(0, 10)
        .map(a => ({ name: a.short_name || a.name, value: a.word_count_proxy }));

    // 2. CFR Title Distribution
    const title_distribution = {};
    agencies.forEach(a => {
        (a.cfr_references || []).forEach(ref => {
            const t = `Title ${ref.title}`;
            title_distribution[t] = (title_distribution[t] || 0) + 1;
        });
    });

    // 3. Amendment Timeline
    const timeline = agencies.reduce((acc, a) => {
        if (a.latest_amended_on) {
            const year = a.latest_amended_on.split("-")[0];
            acc[year] = (acc[year] || 0) + 1;
        }
        return acc;
    }, {});

    const statsData = {
        top_agencies,
        title_distribution,
        timeline,
        updated_at: new Date().toISOString()
    };

    await db.ref("stats").set(statsData);
    return statsData;
}

app.get("/stats", async (req, res) => {
    try {
        const statsData = await updateStats();
        res.status(200).json({ status: "success", data: statsData });
    } catch (error) {
        console.error("Stats Error:", error);
        res.status(500).json({ status: "error", message: error.message });
    }
});

/**
 * Phase 26: Recent Amendments (Search API Integration)
 * Fetches the 5 most recent regulatory changes for an agency.
 */
app.get("/amendments", async (req, res) => {
    try {
        const { agency_slug } = req.query;
        if (!agency_slug) {
            return res.status(400).json({ status: "error", message: "Missing agency_slug parameter." });
        }

        // Build eCFR Search API URL using service
        // Endpoint: https://www.ecfr.gov/api/search/v1/results
        // Parameters: agency_slugs[]={slug}, per_page=5, order=newest_first
        const results = await ecfr.fetchRecentAmendments(agency_slug);

        // Simplify data for client
        const amendments = results.map(r => ({
            date: r.starts_on || r.publication_date || "Unknown Date",
            heading: r.headings?.section || r.headings?.part || "Unknown Section",
            title: `Title ${r.hierarchy?.title || "?"}`,
            description: r.full_text_excerpt || "",
            url: r.structure_index?.[0] ? `https://www.ecfr.gov/current/title-${r.hierarchy.title}/section-${r.structure_index[0]}` : null
        }));

        res.status(200).json({ status: "success", data: amendments });

    } catch (error) {
        console.error("Amendments Fetch Error:", error);
        res.status(500).json({ status: "error", message: error.message });
    }
});

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");

/**
 * Scheduled Daily Analysis Job (Phase 14)
 * Runs at 1 AM everyday
 */
exports.scheduledanalysis = onSchedule({
    schedule: "0 1 * * *",
    timeoutSeconds: 540,
    memory: "2GiB",
    secrets: ["GOOGLE_AI_API_KEY"]
}, async (event) => {
    console.log("Running scheduled daily analysis...");
    try {
        await runFullAnalysis();
        console.log("Scheduled analysis completed successfully.");
    } catch (err) {
        console.error("Scheduled analysis failed:", err);
    }
});

// Expose Express API as a single Cloud Function (v2 syntax):
exports.api = onRequest({
    timeoutSeconds: 540,
    memory: "2GiB",
    secrets: ["GOOGLE_AI_API_KEY"]
}, app);
