local scenes    = require("lib.scenes")
local configs   = require("helpers.config")
local sound     = require("lib.sound")

local component        = require 'lib.gui.badr'
local label            = require 'lib.gui.label'
local scroll_container = require 'lib.gui.scroll_container'

local theme = configs.theme
local w_width, w_height = love.window.getMode()

local about = {}
local menu, footer, scroller
local section_ids = { "section_info", "section_credits", "section_tech", "section_support" }

-- Load the QR code image once
local qr_image = love.graphics.newImage("assets/kofi_qr.png")

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
    focusable = true,
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

function about:load()
  menu = component:root { column = true, gap = 0 }

  local item_width = w_width - 20 * _G.scale
  local qr_size = math.min(w_height * 0.35, 180 * _G.scale)

  local content = component { column = true, gap = 6 * _G.scale }

  -- Section 1: App info
  content = content + section_card("Scrappy", {
    "Version: " .. _G.version,
    "Artwork scraper for muOS",
  }, { id = "section_info" })

  -- Section 2: Credits
  content = content + section_card("Credits", {
    "Maintained by saitamasahil",
    "Original author: gabrielfvale",
    "License: MIT",
  }, { id = "section_credits" })

  -- Section 3: Tech
  content = content + section_card("Built With", {
    "LÖVE framework & Skyscraper backend",
    "github.com/saitamasahil/scrappy",
  }, { id = "section_tech" })

  -- Section 4: Support with QR
  local font = love.graphics.getFont()
  local header_h = font:getHeight() + 8 * _G.scale
  local caption_h = font:getHeight() + 8 * _G.scale
  local qr_section_h = header_h + qr_size + 12 * _G.scale + caption_h + 20 * _G.scale

  content = content + component {
    id = "section_support",
    width = item_width,
    height = qr_section_h,
    focusable = true,
    draw = function(self)
      if not self.visible then return end
      local f = love.graphics.getFont()
      love.graphics.setFont(f)

      -- Header
      local accent = theme:read_color("button", "BUTTON_FOCUS", "#cbaa0f")
      love.graphics.setColor(accent)
      love.graphics.print("Support", self.x + 4, self.y + 4)

      if not qr_image then return end

      local iw, ih = qr_image:getDimensions()
      local scale = qr_size / math.max(iw, ih)
      local scaled_w = iw * scale
      local scaled_h = ih * scale

      local qr_x = self.x + (self.width - scaled_w) / 2
      local qr_y = self.y + header_h

      -- White background behind QR
      local bg_pad = 6 * _G.scale
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", qr_x - bg_pad, qr_y - bg_pad,
        scaled_w + bg_pad * 2, scaled_h + bg_pad * 2, 4 * _G.scale, 4 * _G.scale)

      -- Draw QR image
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(qr_image, qr_x, qr_y, 0, scale, scale)

      -- Caption below QR
      local text_color = theme:read_color("label", "LABEL_TEXT", "#dfe6e9")
      love.graphics.setColor(text_color)
      love.graphics.printf("Scan to support on Ko-fi", self.x, qr_y + scaled_h + 24 * _G.scale, self.width, "center")
    end
  }

  -- Wrap in scroll container
  scroller = scroll_container {
    width = w_width,
    height = w_height - (70 * _G.scale),
    scroll_speed = 30,
  } + content

  menu = menu + scroller
  menu:updatePosition(10, 10)
  menu:focusFirstElement()

  -- Footer
  footer = component { row = true, gap = 15 * _G.scale }
    + label { id = "footer_b", text = "Back", icon = "button_b" }
    + label { id = "footer_dpad", text = "Scroll", icon = "dpad" }
  footer:updatePosition(w_width * 0.5 - footer.width * 0.5, w_height - footer.height - (15 * _G.scale))
end

function about:update(dt)
  if footer then footer:update(dt) end
  menu:update(dt)

  -- Drive scroll position by focused section index
  if scroller then
    local focused = menu:getRoot() and menu:getRoot().focusedElement
    if focused and focused.id then
      for i, sid in ipairs(section_ids) do
        if focused.id == sid then
          local content_h = scroller:getContentHeight()
          local view_h = scroller.height
          local max_scroll = math.max(0, content_h - view_h)
          local t = (i - 1) / math.max(1, #section_ids - 1)
          scroller.targetScrollY = t * max_scroll
          break
        end
      end
    end
  end
end

function about:draw()
  love.graphics.clear(theme:read_color("main", "BACKGROUND", "#000000"))
  menu:draw()
  if footer then
    footer:draw()
  end
end

function about:keypressed(key)
  menu:keypressed(key)
  if key == "escape" or key == "lalt" then
    sound.play("nav_back")
    scenes:pop()
  end
end

function about:gamepadpressed(joystick, button)
  if button == "b" then
    sound.play("nav_back")
    scenes:pop()
    return true
  end
  if menu.gamepadpressed then
    return menu:gamepadpressed(joystick, button)
  end
  return false
end

return about
