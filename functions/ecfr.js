/*
 * eCFR Client Service
 * Centralizes all data fetching from eCFR V1 API.
 * Docs: https://www.ecfr.gov/developers/documentation/api/v1
 */

const { XMLParser } = require("fast-xml-parser");
const xmlParser = new XMLParser();

const BASE_URL = "https://www.ecfr.gov";

/**
 * Generic fetch helper with error handling and retries
 */
async function fetchFromEcfr(endpoint, retries = 3) {
    const url = `${BASE_URL}${endpoint}`;

    for (let i = 0; i < retries; i++) {
        try {
            const response = await fetch(url);

            // Success
            if (response.ok) return response;

            // Retry on 429 (Too Many Requests) or 5xx (Server Errors)
            if (response.status === 429 || response.status >= 500) {
                if (i === retries - 1) throw new Error(`eCFR API Error (${response.status}) for ${endpoint}`);
                // Exponential backoff: 1s, 2s, 4s
                const delay = 1000 * Math.pow(2, i);
                console.warn(`eCFR ${response.status} for ${endpoint}. Retrying in ${delay}ms...`);
                await new Promise(r => setTimeout(r, delay));
                continue;
            }

            throw new Error(`eCFR API Error (${response.status}) for ${endpoint}`);
        } catch (error) {
            if (i === retries - 1) throw error;
            const delay = 1000 * Math.pow(2, i);
            await new Promise(r => setTimeout(r, delay));
        }
    }
}

// 1. Metadata: Titles
// Returns list of all CFR Titles with metadata
async function fetchTitles() {
    const res = await fetchFromEcfr("/api/versioner/v1/titles.json");
    const data = await res.json();
    return data.titles || [];
}

// 2. Metadata: Agencies
// Returns hierarchical list of agencies
async function fetchAgencies() {
    const res = await fetchFromEcfr("/api/admin/v1/agencies.json");
    const data = await res.json();
    return data.agencies || [];
}

// 3. Content: Full XML
// Fetches and parses XML content for a specific Title/Chapter/Date
async function fetchFullContent(date, title, chapter = null) {
    try {
        let endpoint = `/api/versioner/v1/full/${date}/title-${title}.xml`;
        if (chapter) endpoint += `?chapter=${chapter}`;

        const res = await fetchFromEcfr(endpoint);
        const xml = await res.text();
        const jsonObj = xmlParser.parse(xml);

        // Return JSON string representation for AI processing
        // We do truncation at the caller level usually, but here we return full parsed object string
        return JSON.stringify(jsonObj);
    } catch (error) {
        console.warn(`Failed to fetch content for Title ${title} on ${date}: ${error.message}`);
        return ""; // Return empty string on failure to allow partial success
    }
}

// 4. Search: Recent Results
// Fetches recent amendments for an agency
async function fetchRecentAmendments(slug = null, limit = 20) {
    const endpoint = `/api/search/v1/results?per_page=${limit}&order=newest_first` + (slug ? `&agency_slugs[]=${slug}` : "");
    const res = await fetchFromEcfr(endpoint);
    const data = await res.json();
    return data.results || [];
}

module.exports = {
    fetchTitles,
    fetchAgencies,
    fetchFullContent,
    fetchRecentAmendments
};
