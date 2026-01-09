![scrappy](https://github.com/user-attachments/assets/78e48f14-45a8-427d-99ba-80f20ba018dd)
# Scrappy
> Maintained fork by **saitamasahil** · Original author **gabrielfvale** · Original repo: https://github.com/gabrielfvale/scrappy

Scrappy is an artwork scraper for muOS, with the standout feature of incorporating a fully-fledged **Skyscraper** app under the hood. This integration enables near-complete support for artwork XML layouts, allowing Scrappy to scrape, cache assets, and generate artwork using XML mixes with ease. This fork of Scrappy is maintained to improve compatibility with muOS, add new features, provide ongoing updates, and ensure long-term support while staying true to the original vision of the project.

Please read the Wiki for more info on installation and configuration!
* [Getting started](https://github.com/saitamasahil/scrappy/wiki/Getting-Started)

## Features
* Skyscraper backend (artwork XML, cached data, and many other features)
* Auto-detection of storage preferences
* Auto-detection of ROM folders (based on muOS core assignments)
* Configurable app options
* Simple UI & navigation
* Support for user-created artworks (easily drop your XML in `templates/`)
* Support for `box`, `preview` and `splash` outputs
* Support for `arm64` devices with LOVE2d
* OTA updates

![image](https://github.com/user-attachments/assets/ac320ab1-30ed-459c-8b32-d0b201232b34)

## What’s Different in This Fork
1. Supports the latest version of muOS Goose.
2. You can add your ScreenScraper account within the settings using the on-screen keyboard.
3. Concurrent artwork generation which controls how many ROMs are processed at the same time during the artwork generation step. Faster scraping, but uses more CPU/memory.
4. Smooth scrolling - hold navigation buttons to scroll continuously instead of pressing repeatedly.
5. Scrape only missing artwork.
6. Option to show only missing artwork in Scrape single rom.
7. Option to edit region priorities in Advanced tools.
8. Option to clear cache in Advanced tools.
9. Many new templates.

## Installation
To install Scrappy, follow these steps:
1. Download the [latest release](https://github.com/saitamasahil/scrappy/releases) (not the update package - that's for OTA!).
2. Move the downloaded file to the `/mnt/mmc/MUOS/ARCHIVE` folder.
3. Open **Archive Manager** and select the file to install.
4. After installation, you’ll find an entry called "Scrappy" in the **Applications** section.

## Caveats
* Screenscraper credentials need to be added in settings
* First time scraping can be slow (this is expected, but worth noting)

## Resources

- **Skyscraper** - Artwork scraper framework by Gemba [Skyscraper on GitHub](https://github.com/Gemba/skyscraper)
- **ini_parser** - INI file parser by nobytesgiven [GitHub](https://github.com/nobytesgiven/ini_parser)
- **nativefs** - Native filesystem interface by EngineerSmith [GitHub](https://github.com/EngineerSmith/nativefs)
- **timer** - Lightweight timing library by vrld [GitHub](https://github.com/vrld/hump)
- **boxart-buddy** - A curated box art retrieval library [GitHub](https://github.com/boxart-buddy/boxart-buddy)
- **LÖVE** - framework for 2D games in Lua [Website](https://love2d.org/)
- **LÖVE aarch64 binaries** - LOVE2D binary files for aarch64 [Arch Linux Arm](https://archlinuxarm.org/packages/aarch64/love) and [Cebion](https://github.com/Cebion/love2d_aarch64)

## Special thanks

- **Snow (snowram)** - for the huge undertaking of compiling Qt5 and sharing with this project [Kofi](https://ko-fi.com/snowram)
- **Portmaster and their devs** - for great documentation on porting games/software for Linux handhelds [Portmaster](https://portmaster.games/porting.html)
- **Scrappy's original developer [Gabriel Freire](https://github.com/gabrielfvale)** - for creating Scrappy and laying the foundation for this project. Support their work at [Kofi](https://ko-fi.com/gabrielfvale)
- Testers and many other contributors

## Supporting the project
If you find this project useful, please consider leaving a [star on GitHub](https://github.com/saitamasahil/scrappy)

If you would like to support my work & this fork further, you can donate here:

[![Ko-Fi](https://img.shields.io/badge/Ko--fi-F16061?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/saitamasahil)

## Contributing

Contributions to Scrappy are welcome! Please fork the repository, make your changes, and submit a pull request.

## Build from source

Scrappy includes a simple build script for packaging releases.

Requirements:
- bash
- zip (for packaging)

Build:
```bash
./build.sh
```

Troubleshooting:
- On Linux, make the script executable: `chmod +x build.sh`

## License

This project is licensed under the MIT License. See `LICENSE.md` for more details.
