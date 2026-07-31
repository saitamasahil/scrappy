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

    -- Match progress lines like #1/10: Game 'xyz' ... or #1/1: Processing 'xyz' ...
    local count_idx, count_tot, extracted_title = line:match("#(%d+)/(%d+).+['\"](.-)['\"]")
    if count_idx and extracted_title then
        local is_not_found = line:find("not found") ~= nil
        local is_skipped = line:find("Skipping") ~= nil or is_not_found
        return extracted_title, nil, is_skipped, return_types.GAME
    end

    for _, pattern in ipairs(line_patterns) do
        if line:find(pattern) then
            line_match = pattern
            break
        end
    end

    if line_match then
        -- Extract game title
        if line_match == line_patterns[1] then -- Found
            local game_title = string.match(line, game_title_patterns.FOUND)
            return game_title or "N/A", nil, false, return_types.GAME
        elseif line_match == line_patterns[2] then -- Skipped
            local game_title = string.match(line, game_title_patterns.SKIPPED)
            return game_title or "N/A", nil, false, return_types.GAME
        elseif line_match == line_patterns[3] then -- Not found
            local game_title = string.match(line, game_title_patterns.NOT_FOUND)
            return game_title or "N/A", nil, true, return_types.GAME
        elseif line_match == line_patterns[4] then -- Match too low
            local game_title = string.match(line, game_title_patterns.MATCH_TOO_LOW)
            return game_title or "N/A", nil, true, return_types.GAME
        elseif line_match == "Processing" then
            local game_title = string.match(line, game_title_patterns.PROCESSING)
            return game_title or "N/A", nil, false, return_types.GAME
        elseif line_match == "completed" then
            local game_title = string.match(line, game_title_patterns.COMPLETED)
            return game_title or "N/A", nil, false, return_types.GAME
        end
        return "N/A", nil, false, return_types.GAME
    else
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
end

return parser
