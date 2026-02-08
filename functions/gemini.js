const { GoogleGenerativeAI } = require("@google/generative-ai");

/**
 * Gemini Utility Module
 * Handles AI summarization of regulatory content.
 */

// Initialize the Gemini API client lazily to ensure it has access to secrets at runtime
let genAI = null;
let model = null;

function getAiModel() {
    const apiKey = process.env.GOOGLE_AI_API_KEY;
    if (!apiKey) return null;

    if (!model) {
        genAI = new GoogleGenerativeAI(apiKey);
        model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
    }
    return model;
}

/**
 * Generates a focused summary based on regulatory text and a specific context.
 * @param {string} content - The raw regulatory text (cleaned XML).
 * @param {string} context - The specific request (e.g., "baseline", "changes-since-2023").
 * @returns {Promise<string>}
 */
async function generateSummary(content, context, historicalContent = null) {
    const aiModel = getAiModel();
    if (!aiModel) {
        return "Error: GOOGLE_AI_API_KEY is not set. Please provide an API key to enable AI summaries.";
    }

    if (!content || content.length < 50) {
        return "Error: No substantial content available for summarization.";
    }

    // Truncate content if it's extremely large to fit token limits
    const truncatedContent = content.substring(0, 30000);
    const truncatedHistorical = historicalContent ? historicalContent.substring(0, 30000) : "";

    let prompt = "";

    switch (context) {
        case "baseline-2023":
            prompt = `Summarize the regulatory footprint and primary focus of this agency as of December 31, 2023, based on the following text. Highlight key mandates and categories of regulation: \n\n${truncatedContent}`;
            break;
        case "changes-since-2023":
            prompt = `Compare the following two regulatory texts (Historical from Dec 2023 vs Current). Identify and summarize the major changes, additions, or removals that have occurred. Focus on policy shifts and new requirements: 

            --- HISTORICAL TEXT (Dec 31, 2023) ---
            ${truncatedHistorical}

            --- CURRENT TEXT ---
            ${truncatedContent}`;
            break;
        case "recent-batch":
            prompt = `Summarize the most recent batch of changes in this regulatory text. What was the intent behind the latest updates?: \n\n${truncatedContent}`;
            break;
        case "title-level-change":
            prompt = `Summarize the very last significant change recorded in the Title hierarchy associated with this agency. What was the specific section affected and why?: \n\n${truncatedContent}`;
            break;
        default:
            prompt = `Provide a concise summary of the following regulatory text: \n\n${truncatedContent}`;
    }

    try {
        const result = await aiModel.generateContent(prompt);
        const response = await result.response;
        return response.text();
    } catch (error) {
        console.error("Gemini AI Error:", error);
        return `Error generating summary: ${error.message}`;
    }
}

module.exports = { generateSummary };
