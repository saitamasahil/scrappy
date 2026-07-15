local scenes    = require("lib.scenes")
local configs   = require("helpers.config")
local sound     = require("lib.sound")

local component        = require 'lib.gui.badr'
local label            = require 'lib.gui.label'
local scroll_container = require 'lib.gui.scroll_container'

local theme = configs.theme
local w_width, w_height = love.window.getMode()

local faq = {}
local menu, footer, scroller

-- Creates a focusable section card with a header and multiple lines.
-- No visual focus highlight — acts like a page section.
local function section_card(header, lines, opts)
  opts = opts or {}
  local font = love.graphics.getFont()
  local line_h = font:getHeight() + (4 * _G.scale)
  local header_h = font:getHeight() + (8 * _G.scale)
  local total_h = header_h + (#lines * line_h) + (12 * _G.scale)

  return component {
    id = opts.id,
    width = opts.width or (w_width - 20 * _G.scale),
    height = opts.height or total_h,
    focusable = false,
    draw = function(self)
      if not self.visible then return end
      love.graphics.setFont(font)

      -- Header in accent color
      local accent = theme:read_color("button", "BUTTON_FOCUS", "#cbaa0f")
      love.graphics.setColor(accent)
      love.graphics.print(header, self.x + 4 * _G.scale, self.y + 4 * _G.scale)

      -- Body lines in label color
      local c = theme:read_color("label", "LABEL_TEXT", "#dfe6e9")
      love.graphics.setColor(c)
      for i, line in ipairs(lines) do
        love.graphics.print(line, self.x + 4 * _G.scale, self.y + header_h + (i - 1) * line_h)
      end

      -- Separator at bottom
      love.graphics.setColor(c[1], c[2], c[3], 0.15)
      love.graphics.rectangle("fill", self.x, self.y + self.height - 2 * _G.scale, self.width, 2 * _G.scale)
    end,
  }
end

-- Helper to break text down into multiple lines based on screen width, respecting newlines
local function wrap_text(text, max_width)
    local font = love.graphics.getFont()
    local all_lines = {}
    -- Split by newline
    for paragraph in string.gmatch(text .. "\n", "([^\n]*)\n") do
        if paragraph == "" then
            table.insert(all_lines, "")
        else
            local _, wrapped_lines = font:getWrap(paragraph, max_width)
            for _, line in ipairs(wrapped_lines) do
                table.insert(all_lines, line)
            end
        end
    end
    return all_lines
end

function faq:load()
  menu = component:root { column = true, gap = 0 }

  local item_width = w_width - 20 * _G.scale
  local text_max_width = item_width - 16 * _G.scale

  local content = component { column = true, gap = 6 * _G.scale }

  -- Dynamically create lines based on screen width
  local function add_section(id, header, text)
      local lines = wrap_text(text, text_max_width)
      return section_card(header, lines, { id = id })
  end

  -- Credentials
  content = content + add_section("section_credentials", "Credentials & API Keys",
    "Why needed? ScreenScraper has strict request limits for guest accounts (causing rate-limits/blocks), while IGDB and TheGamesDB require personal API keys to authorize data retrieval.\n\n" ..
    "How to configure? Press SELECT while on the Home screen to open Settings. In the Settings menu:\n" ..
    "• ScreenScraper: Enter Username and Password directly using the on-screen virtual keyboard, then select Save.\n" ..
    "• TheGamesDB & IGDB: Select the web server option under either section to start the built-in server. Open the displayed IP address in a browser on your PC or phone (connected to the same network) to enter and save your keys.")

  -- Scraper Modules
  content = content + add_section("section_modules", "Scraper Modules",
    "• ScreenScraper: The absolute gold standard for retro games. Delivers superior ROM matching, richer media, and complete metadata. However, it is usually slower because its servers handle massive traffic, placing free users in a waiting line. Donators get higher download speeds, multi-threaded scraping, and queue priority to bypass the wait.\n" ..
    "• TheGamesDB: Fast and reliable, but lacks comprehensive database coverage for retro/niche titles.\n" ..
    "• IGDB: Powered by Twitch. Extremely fast and excellent for modern titles, but less retro-focused.")

  -- Scraping Phases
  content = content + add_section("section_phases", "Scraping Phases",
    "Scraping consists of two sequential phases:\n" ..
    "1. Fetching (Online): Downloads raw assets from the selected scraper module to your local cache. This depends on network speeds and how busy the scraper's servers are. ScreenScraper is usually the slowest because it is shared by thousands of users, meaning free accounts have limited speeds and get put in a waiting line (queue) when traffic is high.\n" ..
    "2. Generating (Local): Combines raw downloaded media using your active XML template to build the final artwork images. Runs entirely on your device and its speed scales up with the 'Concurrent Artwork Generation' thread count (1-8) in Settings.\n\n" ..
    "Concurrent Artwork Generation:\n" ..
    "Scrappy leverages multi-threaded generation to build artwork faster. Setting this to 4 means the app will spin up 4 parallel threads to generate 4 game artworks simultaneously. For quad-core handhelds, a setting of 4 is highly recommended. While Scrappy runs background scraping tasks at a low CPU priority to keep the app perfectly smooth at any thread count, setting it higher than your hardware core count can add context-switching overhead and slow down generation.")

  -- Scraping Modes
  content = content + add_section("section_modes", "Scraping Modes",
    "• Single Scrape: Scrapes a single game at a time. Ideal for individual ROMs.\n" ..
    "• Scrape All: Processes the entire platform's game list, fetching and generating artwork for every ROM in sequence.\n" ..
    "• Scrape Only Missing Artwork: Scrapes only games that do not have existing artwork yet, saving massive amounts of bandwidth and time.\n" ..
    "• Refined Search: Available under Single Scrape. If auto-matching fails, this lets you manually type the exact game title to get a correct match.")

  -- Web Tools
  content = content + add_section("section_web_tools", "Web Tools",
    "Enable these tools via Advanced Tools, then open the displayed IP address in a browser on any phone/PC connected to the same Wi-Fi network:\n" ..
    "• Template Maker: A visual, interactive playground to design, preview, and customize your XML artwork templates.\n" ..
    "• Artwork Manager: An interactive portal to view, manage, and verify your scraped media and ROM lists.")

  -- Custom Import
  content = content + add_section("section_custom_import", "Custom Import Process",
    "Importing your custom resources is supported by Scrappy, but you have to follow a specific process in order to get it working:\n\n" ..
    "1. Name your resource with the exact base name of the ROM you wish to connect it to. Example: 'Goodboy Galaxy.gba' will import images with a filename of 'Goodboy Galaxy.png' (or other supported image formats).\n" ..
    "2. Create a folder for your platform in '/mnt/mmc/MUOS/application/Scrappy/.scrappy/static/.skyscraper/import'. If you're importing GBA resources, the folder path must be: '/mnt/mmc/MUOS/application/Scrappy/.scrappy/static/.skyscraper/import/gba'.\n" ..
    "3. Place all of your images in the path you've just created, inside their corresponding subfolders: 'screenshots', 'covers', 'marquees', 'textures', and 'wheels'.\n" ..
    "4. Open Advanced Tools in Scrappy and run the 'Custom import' task.\n" ..
    "5. Restart Scrappy for changes to take effect.")

  -- Backups FAQ
  content = content + add_section("section_backups", "Backup & Restore",
    "Scrappy integrates with the native muOS Archive Manager, allowing you to back up and restore your settings and cache easily:\n\n" ..
    "• Backup Cache: Packages and backs up your entire downloaded media cache to either SD1/ARCHIVE or SD2/ARCHIVE. Because this contains all of your downloaded raw graphics and assets for your games, this process can take a considerable amount of time depending on the size of your cache.\n" ..
    "• Backup Scraper Config: Backs up all scraper settings and custom API credentials (ScreenScraper, TheGamesDB, IGDB) to 'SD1/ARCHIVE'.\n" ..
    "• IMPORTANT: Do not share your scraper configuration backup with anyone, as it contains your private API credentials and personal settings.\n" ..
    "• How to restore: Both cache and configuration backups can be restored at any time using the native muOS Archive Manager.")

  -- ROMs & Platform Setup
  content = content + add_section("section_rom_setup", "ROMs, Platforms & Cache Tools",
    "• Rescan ROMs Folders: Scans your storage to detect game directories and updates/overwrites Scrappy's mapped platform list.\n" ..
    "• Edit Platform Mappings: Maps your ROM directories to their corresponding muOS core/system IDs, ensuring accurate matching databases and scraper profiles.\n" ..
    "• Update Cache: Runs Skyscraper in multi-threaded fetch-only mode to update the local assets cache for your games without generating final images.")

  -- Offline Scraping FAQ
  content = content + add_section("section_offline_scraping", "Offline Scraping & Generation",
    "Offline scraping is the generating phase of the scraping process. Instead of querying online APIs, it utilizes your existing locally downloaded game cache:\n\n" ..
    "• Fast Generation: Since it uses already cached assets, generating artwork is instantaneous and does not require an active internet connection.\n" ..
    "• Output Customization: You can experiment with different themes and visual layout styles by generating artwork using different XML layouts (e.g., 2D box art, 3D boxes, compound mixes) for the available games in your cache.\n" ..
    "• How to run: Open the 'Generate Artwork' menu, select your platform, choose your preferred XML layout template, and start the generation.")

  -- Wrap in scroll container
  scroller = scroll_container {
    width = w_width,
    height = w_height - (70 * _G.scale),
    scroll_speed = 30,
  } + content

  menu = menu + scroller
  menu:updatePosition(10, 10)

  -- Footer
  footer = component { row = true, gap = 15 * _G.scale }
    + label { id = "footer_b", text = "Back", icon = "button_b" }
    + label { id = "footer_dpad", text = "Scroll", icon = "dpad" }
  footer:updatePosition(w_width * 0.5 - footer.width * 0.5, w_height - footer.height - (15 * _G.scale))
end

function faq:update(dt)
  if footer then footer:update(dt) end
  menu:update(dt)

  -- Continuous smooth scrolling via held D-pad/Direction keys
  local input = require("helpers.input")
  local scroll_speed = 350 * _G.scale * dt
  local content_h = scroller:getContentHeight()
  local view_h = scroller.height
  local max_scroll = math.max(0, content_h - view_h)

  if input.isEventDown("down") then
    scroller.targetScrollY = math.min(max_scroll, scroller.targetScrollY + scroll_speed)
  elseif input.isEventDown("up") then
    scroller.targetScrollY = math.max(0, scroller.targetScrollY - scroll_speed)
  end
end

function faq:draw()
  love.graphics.clear(theme:read_color("main", "BACKGROUND", "#000000"))
  menu:draw()
  if footer then
    footer:draw()
  end
end

function faq:keypressed(key)
  if key == "escape" or key == "lalt" then
    sound.play("nav_back")
    scenes:pop()
  end
end

function faq:gamepadpressed(joystick, button)
  if button == "b" then
    sound.play("nav_back")
    scenes:pop()
    return true
  end
  return false
end

return faq
