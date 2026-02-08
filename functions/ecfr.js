/*
 * eCFR Client Service
 * Centralizes all data fetching from eCFR V1 API.
 * Docs: https://www.ecfr.gov/developers/documentation/api/v1
 */

const { XMLParser } = require("fast-xml-parser");
const xmlParser = new XMLParser();

const BASE_URL = "https://www.ecfr.gov";

/**
 * Generic fetch helper with error handling
 */
async function fetchFromEcfr(endpoint) {
    const url = `${BASE_URL}${endpoint}`;
    // console.log(`Fetching: ${url}`); // Debug logging (optional)
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`eCFR API Error (${response.status}) for ${endpoint}`);
    }
    return response;
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
async function fetchRecentAmendments(slug, limit = 5) {
    const endpoint = `/api/search/v1/results?agency_slugs[]=${slug}&per_page=${limit}&order=newest_first`;
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
