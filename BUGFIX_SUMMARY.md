# Scrappy Bug Fix Summary

## Overview
This document summarizes critical fixes made to resolve scraping reliability issues, including hanging games, artwork not appearing, batch processing failures, as well as new features added.

---

## Critical Fixes (In Order of Importance)

### 1. Thread Synchronization - Batch Scraping Hangs After First Few Games
**Impact:** High - Prevented batch scraping from completing
**Location:** `lib/backend/skyscraper_generate_backend.lua`, `scenes/main.lua`

**Problem:**
- Generate backend thread didn't send completion signals when errors occurred
- Main thread waited indefinitely for signals that never arrived
- After first error, all subsequent games in queue were blocked

**Solution:**
- Backend now always sends finished signal, even on errors or aborts
- Main thread properly clears stale signals before processing new games
- Queue processing no longer gets stuck waiting

---

### 2. Single Scrape Timeout - Games Hanging Indefinitely
**Impact:** High - Required force-quit when problematic games encountered
**Location:** `lib/backend/skyscraper_backend.lua`, `lib/backend/skyscraper_generate_backend.lua`

**Problem:**
- Certain games consistently caused Skyscraper to hang
- No timeout mechanism existed
- Abort button didn't work during hangs

**Solution:**
- Added 120-second timeout for fetching game data
- Removed timeout for generating artwork (allows complex games to complete)
- Abort signal now checked on every output line
- Hung processes forcefully terminated

---

### 3. Artwork Not Appearing in muOS
**Impact:** Medium - Artwork scraped but not visible in frontend
**Location:** `helpers/artwork.lua`

**Problem:**
- Race condition: files read before fully written to disk
- No verification after file writes
- Insufficient error logging

**Solution:**
- Implemented retry mechanism (5 attempts, 200ms delays)
- Added verification to confirm files exist after writing
- Enhanced logging with full source and destination paths

---

### 4. SD2 Path Handling - Silent Failures on External SD Card
**Impact:** Medium - Games on SD2 card silently failed to process
**Location:** `scenes/main.lua`

**Problem:**
- SD2 paths (`/mnt/sdcard`) had access errors
- Missing games in file map didn't send completion signals
- No diagnostic logging for path issues

**Solution:**
- Added proper error handling for inaccessible paths
- Send completion signals when games not found
- Enhanced logging shows why paths fail

---

### 5. Concurrent Artwork Generation Feature
**Impact:** Medium - Performance enhancement for batch scraping
**Location:** Settings scene, backend processing logic

**What Was Added:**
- New setting to control number of concurrent artwork generation threads
- Allows multiple games to have artwork generated simultaneously
- Configurable from 1-8 concurrent processes in settings
- Significantly speeds up batch scraping operations

**UI Implementation:**
- Added selector control in settings screen for easy adjustment
- Fixed clipping calculations in `lib/gui/select.lua` to ensure selector value remains visible when focused
- Properly handles scroll container transforms for correct display

**Task Matching Improvements:**
- Fixed race condition where concurrent tasks completing out-of-order could remove wrong task
- Backend now includes game and platform identifiers in completion signals
- Each finished task is precisely matched and removed from queue
- Ensures reliable operation at high concurrency levels (6-8 tasks)

**Benefits:**
- Faster batch processing when scraping multiple games
- User control over system resource usage
- Better utilization of multi-core systems

---

### 6. ROM File Renaming to Official Names
**Impact:** Medium - Quality of life enhancement for ROM organization
**Location:** `scenes/main.lua`, `scenes/settings.lua`, `lib/backend/skyscraper_generate_backend.lua`

**What Was Added:**
- Optional feature to automatically rename ROM files to match official game titles
- Toggle in Settings under "Files" section: "Rename ROM files to official name"
- Renames happen after successful scraping with official name from ScreenScraper

**Implementation:**
- Sanitizes filenames by removing invalid filesystem characters
- Preserves original file extensions
- Checks for file conflicts before renaming
- Updates internal game_file_map and cached_game_ids for cache consistency
- Backend passes original_filename and input_folder for proper path resolution

**Safety Features:**
- Only renames when setting is enabled
- Skips rename if files have matching names
- Prevents overwriting existing files
- Falls back to original name if rename fails
- Comprehensive logging of all rename operations

**Benefits:**
- Cleaner ROM library with consistent, readable filenames
- ROM names match what appears in frontends
- Cache remains synchronized with renamed files
- Optional - users can disable if they prefer original filenames

---

## Testing Checklist

### 1. Thread Synchronization
- [ ] Batch scraping completes without hanging after errors
- [ ] Queue continues processing after individual game failures
- [ ] Finished signals sent for all game outcomes (success, error, abort)
- [ ] No stale signals blocking subsequent scraping runs

### 2. Single Scrape Timeout
- [ ] ESC/B button aborts immediately during scraping
- [ ] Problematic games timeout after 120 seconds during fetch phase
- [ ] Generation phase completes without timeout restrictions
- [ ] Abort signal processed on every output line
- [ ] Hung processes forcefully terminated

### 3. Artwork Not Appearing in muOS
- [ ] Artwork appears in muOS frontend after scraping
- [ ] No race conditions when reading newly written files
- [ ] Retry mechanism succeeds after temporary file delays
- [ ] All artwork types copied successfully (box, preview, splash)

### 4. SD2 Path Handling
- [ ] Games on external SD card (/mnt/sdcard) process correctly
- [ ] Clear error messages when paths are inaccessible
- [ ] Completion signals sent even when games not found
- [ ] Proper logging identifies path-related issues

### 5. Concurrent Artwork Generation
- [ ] Concurrent Generation selector (1-8) visible and functional in Settings
- [ ] Can adjust concurrent generation value with left/right keys
- [ ] Multiple games process simultaneously without blocking
- [ ] Higher concurrent values speed up batch scraping
- [ ] System remains stable with multiple concurrent processes (6-8 tasks)
- [ ] Tasks complete out-of-order without queue corruption
- [ ] Correct task removed from queue when completion signal received

### 6. ROM File Renaming
- [ ] Setting toggle appears in Settings under Files section
- [ ] When enabled, ROM files renamed to official names after scraping
- [ ] Original file extensions preserved during rename
- [ ] No conflicts or overwrites of existing files
- [ ] game_file_map updated correctly after rename
- [ ] cached_game_ids updated correctly after rename
- [ ] Feature works correctly when disabled (no renames occur)
- [ ] Invalid filesystem characters sanitized in new filenames
- [ ] Rename failures logged and original name used as fallback

---

## Log Monitoring

### 1. Thread Synchronization
- "[gen] Finished \"[game]\"" - Confirms generation completion
- "Finished task \"[file]\" on platform [platform]" - Task removal from queue
- Look for absence of indefinite waits or stuck queues

### 2. Single Scrape Timeout
- "[fetch] Timeout after [X]s - killing process" - Fetch timeout triggered
- "[fetch] Abort signal received" - User abort processed
- "[gen] Aborted \"[game]\"" - Generation abort processed
- Check for timeout values around 120 seconds for fetch phase

### 3. Artwork Not Appearing in muOS
- "Successfully copied [type] artwork to [path]" - Confirms artwork copying
- "Attempting to copy [type] artwork" - Retry attempts logged
- "Verified file exists at [path]" - File verification after write
- Full source and destination paths for troubleshooting

### 4. SD2 Path Handling
- "Path exists but appears empty or inaccessible: [path]" - SD2 access issues
- "Path does not exist: [path]" - Missing path detection
- "Game file not found in map for [game] on platform [platform]" - Mapping issues

### 5. Concurrent Artwork Generation
- "Concurrent artwork generation tasks: [N]" - Startup configuration
- "Task in progress: [file] (Total concurrent: [N])" - Task queue status
- "Processing queued game: [platform]/[game]" - Generation phase processing
- Monitor for correct task counts matching configured concurrency

### 6. ROM File Renaming
- "Attempting to rename: '[old]' -> '[new]'" - Rename initiation
- "Renaming: [old] -> [new]" - File rename operation
- "Successfully renamed ROM file: [old] -> [new]" - Confirms successful renames
- "Updated cache reference: [old] -> [new]" - Cache synchronization
- "Cannot rename - file already exists" - Conflict prevention
- "Failed to rename file" - Rename failures for troubleshooting
