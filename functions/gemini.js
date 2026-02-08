const { GoogleGenerativeAI } = require("@google/generative-ai");

/**
 * Gemini Utility Module
 * Handles AI summarization of regulatory content.
 */

// Initialize the Gemini API client lazily to ensure it has access to secrets at runtime
let genAI = null;
let model = null;

/**
 * Fetches available models from the API to determine the best match.
 * @param {string} apiKey
 * @returns {Promise<string>} The model name to use.
 */
async function getBestModelName(apiKey) {
    try {
        const url = `https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}`;
        const response = await fetch(url);
        if (!response.ok) {
            console.warn(`Failed to list models: ${response.statusText}`);
            return "gemini-1.5-flash"; // Default assumption
        }

        const data = await response.json();
        const models = data.models || [];

        console.log("Available Models:", models.map(m => m.name));

        // Prioritize models
        // Dynamic selection: Find best available model supporting content generation
        // Criteria: 1.5-Flash > 1.5-Pro > Pro
        const contentModels = models.filter(m => m.supportedGenerationMethods && m.supportedGenerationMethods.includes("generateContent"));

        // 1. Look for any Gemini 1.5 Flash variant
        let bestMatch = contentModels.find(m => m.name.includes("gemini-1.5-flash"));

        // 2. Fallback to Gemini 1.5 Pro
        if (!bestMatch) {
            bestMatch = contentModels.find(m => m.name.includes("gemini-1.5-pro"));
        }

        // 3. Fallback to any Gemini Pro
        if (!bestMatch) {
            bestMatch = contentModels.find(m => m.name.includes("gemini-pro"));
        }

        // 4. Last resort: ANY model that supports generateContent
        if (!bestMatch) {
            bestMatch = contentModels[0];
        }

        if (bestMatch) {
            console.log(`Selected model from API list: ${bestMatch.name}`);
            // SDK expects model name WITHOUT 'models/' prefix
            return bestMatch.name.replace(/^models\//, "");
        }

        return "gemini-1.5-flash";
    } catch (e) {
        console.warn("Error listing models, falling back to default:", e);
        return "gemini-1.5-flash";
    }
}

async function getAiModel(apiKey) {
    if (!apiKey) return null;

    if (!model) {
        genAI = new GoogleGenerativeAI(apiKey);

        // Dynamically pick the best model
        const modelName = await getBestModelName(apiKey);

        // Gemini 1.5 models require v1beta, gemini-pro works on v1 but v1beta is safe for all
        const apiVersion = "v1beta";

        console.log(`Initializing Gemini with model: ${modelName} (apiVersion: ${apiVersion})`);

        model = genAI.getGenerativeModel({ model: modelName }, { apiVersion: apiVersion });
    }
    return model;
}

/**
 * Generates a focused summary based on regulatory text and a specific context.
 * @param {string} content - The raw regulatory text (cleaned XML).
 * @param {string} context - The specific request (e.g., "baseline", "changes-since-2023").
 * @returns {Promise<string>}
 */
async function generateSummary(content, context, historicalContent = null, apiKey = null) {
    const aiModel = await getAiModel(apiKey || process.env.GOOGLE_AI_API_KEY);
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
            prompt = `Analyze the "RECENT AMENDMENTS" section provided in the text below (if available). Summarize the most recent batch of changes. What was the intent behind the latest updates? If no recent amendments are listed, summarize the most significant recent policy shift found in the text: \n\n${truncatedContent}`;
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
