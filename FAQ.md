# Scrappy FAQ

### Credentials & API Keys
Why needed? ScreenScraper has strict request limits for guest accounts (causing rate-limits/blocks), while IGDB and TheGamesDB require personal API keys to authorize data retrieval.

How to configure? Press SELECT while on the Home screen to open Settings. In the Settings menu:
- **ScreenScraper**: Enter Username and Password directly using the on-screen virtual keyboard, then select Save.
- **TheGamesDB & IGDB**: Select the web server option under either section to start the built-in server. Open the displayed IP address in a browser on your PC or phone (connected to the same network) to enter and save your keys.

### Scraper Modules
- **ScreenScraper**: The absolute gold standard for retro games. Delivers superior ROM matching, richer media, and complete metadata. However, it is usually slower because its servers handle massive traffic, placing free users in a waiting line. Donators get higher download speeds, multi-threaded scraping, and queue priority to bypass the wait.
- **TheGamesDB**: Fast and reliable, but lacks comprehensive database coverage for retro/niche titles.
- **IGDB**: Powered by Twitch. Extremely fast and excellent for modern titles, but less retro-focused.

### Scraping Phases
Scraping consists of two sequential phases:
1. Fetching (Online): Downloads raw assets from the selected scraper module to your local cache. This depends on network speeds and how busy the scraper's servers are. ScreenScraper is usually the slowest because it is shared by thousands of users, meaning free accounts have limited speeds and get put in a waiting line (queue) when traffic is high.
2. Generating (Local): Combines raw downloaded media using your active XML template to build the final artwork images. Runs entirely on your device and its speed scales up with the 'Concurrent Artwork Generation' thread count (1-8) in Settings.

Concurrent Artwork Generation:
Scrappy leverages multi-threaded generation to build artwork faster. Setting this to 4 means the app will spin up 4 parallel threads to generate 4 game artworks simultaneously. For quad-core handhelds, a setting of 4 is highly recommended. While Scrappy runs background scraping tasks at a low CPU priority to keep the app perfectly smooth at any thread count, setting it higher than your hardware core count can add context-switching overhead and slow down generation.

### Scraping Modes
- **Single Scrape**: Scrapes a single game at a time. Ideal for individual ROMs.
- **Scrape All**: Processes the entire platform's game list, fetching and generating artwork for every ROM in sequence.
- **Scrape Only Missing Artwork**: Scrapes only games that do not have existing artwork yet, saving massive amounts of bandwidth and time.
- **Refined Search**: Available under Single Scrape. If auto-matching fails, this lets you manually type the exact game title to get a correct match.

### Web Tools
Enable these tools via Advanced Tools, then open the displayed IP address in a browser on any phone/PC connected to the same Wi-Fi network:
- **Template Maker**: A visual, interactive playground to design, preview, and customize your XML artwork templates.
- **Artwork Manager**: An interactive portal to view, manage, and verify your scraped media and ROM lists.

### Custom Import Process
Importing your custom resources is supported by Scrappy, but you have to follow a specific process in order to get it working:

1. Name your resource with the exact base name of the ROM you wish to connect it to. Example: 'Goodboy Galaxy.gba' will import images with a filename of 'Goodboy Galaxy.png' (or other supported image formats).
2. Create a folder for your platform in '/mnt/mmc/MUOS/application/Scrappy/.scrappy/static/.skyscraper/import'. If you're importing GBA resources, the folder path must be: '/mnt/mmc/MUOS/application/Scrappy/.scrappy/static/.skyscraper/import/gba'.
3. Place all of your images in the path you've just created, inside their corresponding subfolders: 'screenshots', 'covers', 'marquees', 'textures', and 'wheels'.
4. Open Advanced Tools in Scrappy and run the 'Run Custom Import' task.
5. Generate your artwork by running Scrape All on that platform, or use Artwork Manager in Advanced Tools to generate individually.

### Backup & Restore
Scrappy integrates with the native muOS Archive Manager, allowing you to back up and restore your settings and cache easily:

- **Backup Cache**: Packages and backs up your entire downloaded media cache to either SD1/ARCHIVE or SD2/ARCHIVE. Because this contains all of your downloaded raw graphics and assets for your games, this process can take a considerable amount of time depending on the size of your cache.
- **Backup Scraper Config**: Backs up all scraper settings and custom API credentials (ScreenScraper, TheGamesDB, IGDB) to 'SD1/ARCHIVE'.
- **IMPORTANT**: Do not share your scraper configuration backup with anyone, as it contains your private API credentials and personal settings.
- **How to restore**: Both cache and configuration backups can be restored at any time using the native muOS Archive Manager.

### ROMs, Platforms & Cache Tools
- **Rescan ROMs Folders**: Scans your storage to detect game directories and updates/overwrites Scrappy's mapped platform list.
- **Edit Platform Mappings**: Maps your ROM directories to their corresponding muOS core/system IDs, ensuring accurate matching databases and scraper profiles.
- **Update Cache**: Runs Skyscraper in multi-threaded fetch-only mode to update the local assets cache for your games without generating final images.

### Offline Scraping & Generation
Offline scraping is the generating phase of the scraping process. Instead of querying online APIs, it utilizes your existing locally downloaded game cache:

- **Fast Generation**: Since it uses already cached assets, generating artwork is instantaneous and does not require an active internet connection.
- **Output Customization**: You can experiment with different themes and visual layout styles by generating artwork using different XML layouts (e.g., 2D box art, 3D boxes, compound mixes) for the available games in your cache.
- **How to run**: Open the 'Generate Artwork' menu, select your platform, choose your preferred XML layout template, and start the generation.

### Common Questions
- **Can this scrape a single title, or just whole folders/systems?**
  Yes! Just choose 'Scrape single rom' from the main menu.

- **Will it overwrite existing box art?**
  Yes, Scrappy will overwrite any existing box art if new artwork is downloaded for a game.

### Advanced Config (peas.json)
The peas.json file is located in static/.skyscraper/peas.json inside the app bundle and is used by Skyscraper to define file extensions available for each platform, as well as supported scraper modules. You can edit this file to add file extensions or adjust scraper modules per platform.

### Region Priorities
In Advanced Tools, you can customize region preference order (e.g., 'us, eu, jp, world'). Skyscraper uses this sequence to select regional artwork, titles, and box covers when a ROM exists across multiple regions.

### Live Dashboard
While scraping is running, Scrappy hosts a real-time web dashboard. Open the displayed IP address in any browser on your Wi-Fi network to monitor live logs, active worker threads, and progress percentage.

### Template Resolution Filter
Under Settings, 'Filter Templates by Resolution' automatically hides XML artwork templates that do not match your device's screen aspect ratio (e.g., 640x480 vs 720x720). Disable this option if you want to preview or use templates designed for other resolutions.

### Video Previews
Video preview downloading can be toggled in Advanced Tools. When enabled, ScreenScraper will download short video clips alongside graphics.

### SD Card Storage (Cache Location)
Scrappy supports storing your media cache on SD1 or SD2 (/mnt/sdcard/scrappy_cache). Moving cache storage to SD2 prevents filling up your primary OS storage when scraping large ROM collections.

### Troubleshooting Unmatched Games
If a ROM fails to scrape or match:
1. Use 'Refined Search' under Single Scrape to manually type the exact game title.
2. Use 'Edit Platform Mappings' in Settings to make sure your ROM folder is mapped to the correct muOS system core ID.
3. Check 'peas.json' to ensure your ROM's file extension (e.g. .7z, .iso, .chd) is registered for that platform.

### Themes & Accent Customization
In Advanced Tools, you can switch visual UI themes and customize accent colors. Accent modes let you match Scrappy directly to your active muOS system accent or set a custom hex color.
