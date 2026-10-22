-- Run from the repository root: lua tests/batch_cache_test.lua
-- The cache parser and fetch policy run without LÖVE or network access.
package.loaded['lib.log'] = {write = function() end}
package.loaded['lib.metadata'] = {}
package.loaded['helpers.config'] = {user_config = {}, skyscraper_config = {}}
package.loaded['helpers.muos'] = {}
package.loaded['lib.pprint'] = {}

local files = {
    ['cache/snes/quickid.xml'] = [[
<quickidlist>
<quickid filepath="/roms/SFC/Empty.sfc" id="empty" />
<quickid filepath="/roms/SFC/Partial.sfc" id="partial" />
<quickid filepath="/roms/SFC/Healthy.sfc" id="healthy" />
<quickid filepath="/roms/SFC/Video.sfc" id="video" />
</quickidlist>
]],
    ['cache/snes/db.xml'] = [[
<resources>
<resource id="partial" type="cover" source="screenscraper">covers/partial</resource>
<resource id="healthy" type="title" source="screenscraper">Healthy</resource>
<resource id="healthy" type="cover" source="screenscraper">covers/healthy</resource>
<resource id="video" type="title" source="screenscraper">Video</resource>
<resource id="video" type="video" source="screenscraper">videos/video</resource>
</resources>
]]
}
nativefs = {read = function(path) return files[path] end}

local artwork = require('helpers.artwork')
artwork.process_cached_by_platform('snes', 'cache')
local cache = artwork.cached_game_ids.snes
local count = 0
local function expect(name, entry, videos, offline, fetch, refresh)
    local actual_fetch, actual_refresh = artwork.get_fetch_requirements(entry, videos, offline)
    assert(actual_fetch == fetch, name .. ': unexpected fetch decision')
    assert(actual_refresh == refresh, name .. ': unexpected refresh decision')
    count = count + 1
end

-- These are real parser outputs, including the truthy empty table that caused
-- the batch path to skip fetching after an unsuccessful earlier scrape.
assert(type(cache['empty.sfc']) == 'table' and next(cache['empty.sfc']) == nil)
expect('empty quickid record', cache['empty.sfc'], false, false, true, true)
expect('full-path empty record', cache['/roms/sfc/empty.sfc'], false, false, true, true)
expect('resources without title', cache['partial.sfc'], false, false, true, true)
expect('usable cached game', cache['healthy.sfc'], false, false, false, false)
expect('new game', cache['new.sfc'], false, false, true, false)
expect('missing enabled video', cache['healthy.sfc'], true, false, true, true)
expect('cached enabled video', cache['video.sfc'], true, false, false, false)

for _, name in ipairs({'empty.sfc', 'partial.sfc', 'healthy.sfc', 'video.sfc', 'new.sfc'}) do
    expect('offline ' .. name, cache[name], true, true, false, false)
end

-- A recovered record must stop triggering online fetches on subsequent runs.
files['cache/snes/db.xml'] = files['cache/snes/db.xml']:gsub('</resources>',
    '<resource id="empty" type="title" source="screenscraper">Recovered</resource>\n</resources>')
artwork.process_cached_by_platform('snes', 'cache')
expect('recovered record stays local', artwork.cached_game_ids.snes['empty.sfc'], false, false, false, false)

print(string.format('PASS: %d batch cache recovery cases', count))
