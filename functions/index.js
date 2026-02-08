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
 * @param {string|object} agencyOrId - Agency slug or object
 * @param {boolean} force - Whether to force regeneration even if current
 * @param {boolean} generateIfNeeded - Whether to generate a summary if one is missing/stale. 
 *                                     Set to false for "lazy" API checks (returns null if missing).
 */
async function processAgencySummary(agencyOrId, force = false, generateIfNeeded = true) {
    let agency = null;

    if (typeof agencyOrId === 'string') {
        const snapshot = await db.ref("agencies").orderByChild("slug").equalTo(agencyOrId).once("value");
        const val = snapshot.val();
        if (val) {
            agency = Object.values(val)[0];
        } else {
            // Fallback: try by key directly if slug didn't match (less likely but possible)
            const snap2 = await db.ref("agencies").child(agencyOrId).once("value");
            agency = snap2.val();
        }
    } else {
        agency = agencyOrId;
    }

    if (!agency) {
        throw new Error(`Agency not found for ID: ${agencyOrId}`);
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

    // Always fetch existing data for potential fallback usage
    const existingSnapshot = await db.ref("summaries").child(agency.slug).once("value");
    const existingData = existingSnapshot.val();

    if (force !== true) {
        // Check if we analyzed THIS version already (checksum)
        const isCurrent = existingData &&
            existingData.checksum === agency.checksum;

        if (isCurrent) {
            console.log(`Skipping ${agency.name} - compliant summary already exists.`);
            return existingData;
        }

        // If not current, and we are NOT allowed to generate, return what we have (stale) or null
        if (!generateIfNeeded) {
            console.log(`Skipping generation for ${agency.name} (Lazy Mode).`);
            return existingData || null; // Return null if nothing exists
        }
    }

    console.log(`Generating AI summaries for ${agency.name}...`);

    // 1. Fetch Recent Amendments FIRST to determine the true "current" state
    let amendments = [];
    try {
        amendments = await ecfr.fetchRecentAmendments(agency.slug);
    } catch (e) {
        console.warn(`Failed to fetch amendments for ${agency.name}: ${e.message}`);
    }

    // Determine the most recent amendment date from live data
    // fallback to stored date, then today
    let effectiveDate = agency.latest_amended_on || new Date().toISOString().split("T")[0];

    if (amendments.length > 0) {
        // Amendments are ordered newest_first by API
        const latestFromApi = amendments[0].date || amendments[0].publication_date;
        if (latestFromApi && latestFromApi > effectiveDate) {
            console.log(`Found newer amendment for ${agency.name}: ${latestFromApi} (was ${effectiveDate})`);
            effectiveDate = latestFromApi;
        }
    }

    // 2. Fetch Content based on the FRESH effective date
    const historyData = await fetchDeepContent("2023-12-31");
    const currentData = await fetchDeepContent(effectiveDate);

    // Context for AI
    let activeContext = currentData.text;
    if (amendments.length > 0) {
        const contextStr = amendments.map(a => {
            const date = a.starts_on || a.publication_date || "Unknown Date";
            const heading = a.headings?.section || a.headings?.part || "Unknown Section";
            const desc = a.full_text_excerpt || a.headings?.description || a.headings?.part || "No details";
            return `- [${date}] ${heading}: ${desc}`;
        }).join("\n");

        activeContext = `RECENT AMENDMENTS (as of ${effectiveDate}):\n${contextStr}\n\nREGULATORY TEXT SAMPLE:\n${currentData.text}`;
    }


    const apiKey = process.env.GOOGLE_AI_API_KEY || (functions.config().gemini && functions.config().gemini.key);

    if (!apiKey) {
        throw new Error("Missing GOOGLE_AI_API_KEY in environment or config.");
    }

    // Initialize Gemini with key (although gemini.js handles it, we want to fail fast here or ensure it's set)
    process.env.GOOGLE_AI_API_KEY = apiKey;

    try {
        const [summary2023, changesSince, recentBatch, titleChange] = await Promise.all([
            generateSummary(historyData.text, "baseline-2023", null, apiKey),
            generateSummary(activeContext, "changes-since-2023", historyData.text, apiKey),
            generateSummary(activeContext, "recent-batch", null, apiKey),
            generateSummary(activeContext, "title-level-change", null, apiKey)
        ]);

        // Fallback: If new Recent Batch failed (or is empty error), use the cached one if available
        let finalRecentBatch = recentBatch;
        if ((!recentBatch || recentBatch.startsWith("Error")) && existingData && existingData.summaries && existingData.summaries.recent_batch) {
            console.warn(`Fallback: Using cached 'recent_batch' for ${agency.name} due to generation error.`);
            finalRecentBatch = existingData.summaries.recent_batch;
        }

        const result = {
            agency: agency.name,
            checksum: agency.checksum,
            summaries: {
                baseline_2023: summary2023,
                changes_since_2023: changesSince,
                recent_batch: finalRecentBatch,
                latest_title_change: titleChange
            },
            word_count: currentData.est_word_count,
            generated_at: new Date().toISOString()
        };

        // Save to RTDB
        await db.ref("summaries").child(agency.slug).set(result);
        return result;

    } catch (aiError) {
        console.error(`AI Generation failed for ${agency.name}:`, aiError);

        // Fallback: Return existing summary if available
        const fallbackSnapshot = await db.ref("summaries").child(agency.slug).once("value");
        const fallbackData = fallbackSnapshot.val();

        if (fallbackData) {
            console.warn(`Returning existing (stale) summary for ${agency.name} as fallback.`);
            return fallbackData;
        }

        throw aiError; // No fallback possible
    }
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

        // Lazy Mode: Only generate if force=true. Otherwise, return existing/stale or 404.
        const shouldGenerate = (force === "true");
        const result = await processAgencySummary(agency_id, shouldGenerate, shouldGenerate);

        if (!result) {
            return res.status(404).json({ status: "error", message: "Summary not found. Use force=true to generate." });
        }

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

    // 1. Top 10 Footprint (Aggregated by Department)
    const footprintMap = {};
    agencies.forEach(a => {
        if (a.word_count_proxy) {
            const key = a.parent_agency_name || a.name;
            footprintMap[key] = (footprintMap[key] || 0) + a.word_count_proxy;
        }
    });

    const top_agencies = Object.entries(footprintMap)
        .map(([name, value]) => ({ name, value }))
        .sort((a, b) => b.value - a.value)
        .slice(0, 10);

    // 2. CFR Title Stats ("Most Change" - Amended Since 2024)
    const REFERENCE_DATE = "2024-01-01";
    const titleStatsMap = {};

    const CFR_TITLES = {
        1: "General Provisions", 2: "Grants and Agreements", 3: "The President", 4: "Accounts", 5: "Administrative Personnel",
        6: "Domestic Security", 7: "Agriculture", 8: "Aliens and Nationality", 9: "Animals and Animal Products", 10: "Energy",
        11: "Federal Elections", 12: "Banks and Banking", 13: "Business Credit and Assistance", 14: "Aeronautics and Space", 15: "Commerce and Foreign Trade",
        16: "Commercial Practices", 17: "Commodity and Securities Exchanges", 18: "Conservation of Power and Water Resources", 19: "Customs Duties", 20: "Employees' Benefits",
        21: "Food and Drugs", 22: "Foreign Relations", 23: "Highways", 24: "Housing and Urban Development", 25: "Indians",
        26: "Internal Revenue", 27: "Alcohol, Tobacco Products and Firearms", 28: "Judicial Administration", 29: "Labor", 30: "Mineral Resources",
        31: "Money and Finance: Treasury", 32: "National Defense", 33: "Navigation and Navigable Waters", 34: "Education", 35: "Panama Canal",
        36: "Parks, Forests, and Public Property", 37: "Patents, Trademarks, and Copyrights", 38: "Pensions, Bonuses, and Veterans' Relief", 39: "Postal Service", 40: "Protection of Environment",
        41: "Public Contracts and Property Management", 42: "Public Health", 43: "Public Lands: Interior", 44: "Emergency Management and Assistance", 45: "Public Welfare",
        46: "Shipping", 47: "Telecommunication", 48: "Federal Acquisition Regulations System", 49: "Transportation", 50: "Wildlife and Fisheries"
    };

    agencies.forEach(a => {
        if (a.latest_amended_on && a.latest_amended_on >= REFERENCE_DATE) {
            (a.cfr_references || []).forEach(ref => {
                const name = CFR_TITLES[parseInt(ref.title)] || "Unknown";
                const t = `Title ${ref.title}: ${name}`;

                if (!titleStatsMap[t]) {
                    titleStatsMap[t] = { count: 0, agencies: [] };
                }
                // Avoid duplicates if agency references same title multiple times
                if (!titleStatsMap[t].agencies.includes(a.short_name || a.name)) {
                    titleStatsMap[t].count += 1;
                    titleStatsMap[t].agencies.push(a.short_name || a.name);
                }
            });
        }
    });

    const title_stats = Object.entries(titleStatsMap)
        .map(([title, data]) => ({
            title,
            count: data.count,
            agencies: data.agencies.slice(0, 5) // Limit to top 5 names for display
        }))
        .sort((a, b) => b.count - a.count)
        .slice(0, 10);

    // 3. Amendment Activity (Past 12 Months Snapshot)
    const oneYearAgo = new Date();
    oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);
    const cutoffDate = oneYearAgo.toISOString().split("T")[0];

    const timelineRaw = {};
    const orgTotals = {};

    agencies.forEach(a => {
        // Check if agency was amended in the last year
        if (a.latest_amended_on && a.latest_amended_on >= cutoffDate) {
            const org = a.parent_agency_name || a.name;
            const bucket = "Past 12 Months";

            if (!timelineRaw[bucket]) timelineRaw[bucket] = {};
            timelineRaw[bucket][org] = (timelineRaw[bucket][org] || 0) + 1;
            orgTotals[org] = (orgTotals[org] || 0) + 1;
        }
    });

    // Identify Top 10 active organizations (increased from 5 for better distribution)
    const topOrgs = Object.entries(orgTotals)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 10)
        .map(entry => entry[0]);

    // Flatten into TimelinePoints
    const timeline = [];
    Object.entries(timelineRaw).forEach(([year, orgsMap]) => {
        let otherCount = 0;
        Object.entries(orgsMap).forEach(([org, count]) => {
            if (topOrgs.includes(org)) {
                timeline.push({ year, organization: org, count });
            } else {
                otherCount += count;
            }
        });
        if (otherCount > 0) {
            timeline.push({ year, organization: "Other Agencies", count: otherCount });
        }
    });

    const statsData = {
        top_agencies,
        title_stats,
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
        // agency_slug is optional now (returns global recent if null)

        // Build eCFR Search API URL using service
        // Endpoint: https://www.ecfr.gov/api/search/v1/results
        // Parameters: agency_slugs[]={slug}, per_page=5, order=newest_first
        const results = await ecfr.fetchRecentAmendments(agency_slug);

        // Simplify data for client
        const amendments = results.map(r => {
            let url = null;
            if (r.structure_index && r.structure_index.length > 0) {
                url = `https://www.ecfr.gov/current/title-${r.hierarchy.title}/section-${r.structure_index[0]}`;
            } else if (r.hierarchy && r.hierarchy.part) {
                url = `https://www.ecfr.gov/current/title-${r.hierarchy.title}/part-${r.hierarchy.part}`;
            } else if (r.hierarchy && r.hierarchy.title) {
                url = `https://www.ecfr.gov/current/title-${r.hierarchy.title}`;
            }

            return {
                date: r.starts_on || r.publication_date || "Unknown Date",
                heading: r.headings?.section || r.headings?.part || "Unknown Section",
                title: `Title ${r.hierarchy?.title || "?"}`,
                description: r.full_text_excerpt || r.headings?.description || r.headings?.part || r.headings?.subpart || "No additional details available.",
                agency_slug: r.agency_slugs && r.agency_slugs.length > 0 ? r.agency_slugs[0] : null,
                url: url
            };
        });

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
    timeoutSeconds: 300,
    memory: "2GiB",
    secrets: ["GOOGLE_AI_API_KEY"]
}, app);
