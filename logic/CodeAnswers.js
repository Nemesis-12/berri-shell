.pragma library

/** True for JSON objects, excluding null and arrays. */
function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** True when every weekly model row has the fields shown in Code. */
function isModelList(value) {
    return Array.isArray(value) && value.every(model => isObject(model)
        && typeof model.name === "string" && typeof model.tokens === "number");
}

/** True when both agents have token and cost values for each period. */
function isUsage(value) {
    if (!isObject(value)) return false;
    return ["claude", "codex"].every(agent => isObject(value[agent])
        && ["today", "week", "month"].every(period => {
            var bucket = value[agent][period];
            return isObject(bucket) && typeof bucket.tokens === "number"
                && (typeof bucket.cost === "number" || bucket.cost === null);
        }));
}

/** The Code statistics fields used by its days, model, and cost views. */
function stats(data) {
    return isObject(data) && typeof data.generatedAt === "string" && data.generatedAt.length > 0
        && Array.isArray(data.days) && data.days.every(day => isObject(day)
            && typeof day.date === "string" && typeof day.claude === "number" && typeof day.codex === "number")
        && isObject(data.models) && isModelList(data.models.claude) && isModelList(data.models.codex)
        && isUsage(data.usage);
}

/** True when each heatmap day has a date and contribution count. */
function isContributionDays(value) {
    return Array.isArray(value) && value.every(day => Array.isArray(day)
        && typeof day[0] === "string" && typeof day[1] === "number");
}

/** The contribution data used by the current and historical heatmaps. */
function github(data) {
    return isObject(data) && typeof data.fetchedAt === "string" && data.fetchedAt.length > 0
        && typeof data.total === "number" && isContributionDays(data.days)
        && Array.isArray(data.years) && data.years.every(year => isObject(year)
            && typeof year.year === "number" && typeof year.total === "number"
            && isContributionDays(year.days));
}

/** The versioned commit list used by the recent commits view. */
function commits(data) {
    return isObject(data) && Array.isArray(data.commits) && data.commits.every(commit => isObject(commit)
        && typeof commit.sha === "string" && typeof commit.message === "string"
        && typeof commit.repo === "string" && typeof commit.date === "string");
}
