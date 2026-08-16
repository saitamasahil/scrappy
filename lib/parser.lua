require("globals")

local parser = {}
local line_patterns = {"found!", "Skipping game", "not found", "match too low", "No entries to scrape...", "Processing", "completed", "generated", "Saved"}
local game_title_patterns = {
    FOUND = "Game '(.-)' found!",
    NOT_FOUND = "Game '(.-)' not found",
    MATCH_TOO_LOW = "Game '(.-)' match too low",
    SKIPPED = "Skipping game '(.-)' since",
    PROCESSING = "Processing '(.-)'",
    COMPLETED = "Game '(.-)' completed",
    GENERATED = "Generated artwork for '(.-)'",
    SAVED = "Saved artwork for '(.-)'"
}
local log_patterns = {"Running Skyscraper v", "Fetching limits for user", "Starting scraping run",
                      "Resource gathering run", "Artwork generation run", "Processing platform",
                      "Loading artwork template"}
local return_types = {
    GAME = "game",
    LOG = "log"
}

--[[
  Parse a line of Skyscraper output, returning:
  - A line to be logged, or a game title if found
  - An error message if the line is an error
  - A boolean indicating whether the game is skipped or not
  - A string indicating the return type
--]]
function parser.parse(line)
    local game_pattern = "'([^']*'.-)'"
    local line_match = nil

    for _, pattern in ipairs(log_patterns) do
        if line:find(pattern) then
            return line, nil, false, return_types.LOG
        end
    end

    -- Check specific game title patterns directly to handle apostrophes correctly
    local found_title = string.match(line, game_title_patterns.FOUND)
    if found_title then
        return found_title, nil, false, return_types.GAME
    end

    local not_found_title = string.match(line, game_title_patterns.NOT_FOUND)
    if not_found_title then
        return not_found_title, nil, true, return_types.GAME
    end

    local match_low_title = string.match(line, game_title_patterns.MATCH_TOO_LOW)
    if match_low_title then
        return match_low_title, nil, true, return_types.GAME
    end

    local skipped_title = string.match(line, game_title_patterns.SKIPPED)
    if skipped_title then
        return skipped_title, nil, true, return_types.GAME
    end

    local proc_title = string.match(line, game_title_patterns.PROCESSING)
    if proc_title then
        return proc_title, nil, false, return_types.GAME
    end

    local completed_title = string.match(line, game_title_patterns.COMPLETED)
    if completed_title then
        return completed_title, nil, false, return_types.GAME
    end

    local gen_title = string.match(line, game_title_patterns.GENERATED) or string.match(line, game_title_patterns.SAVED)
    if gen_title then
        return gen_title, nil, false, return_types.GAME
    end
    -- Check explicit error patterns
    for _, err_pattern in ipairs(SKYSCRAPER_ERRORS) do
        if line:find(err_pattern, 1, true) then
            return nil, line, true, return_types.LOG
        end
    end

    -- Check generic error indicators
    if line:find("qt.qpa.plugin") or line:lower():find("could not find") or line:find("Error:") or line:find("Fatal:") then
        return nil, line, true, return_types.LOG
    end

    return nil, nil, nil
end

return parser
