![scrappy](https://github.com/user-attachments/assets/78e48f14-45a8-427d-99ba-80f20ba018dd)
# Scrappy
> Maintained fork by **saitamasahil** · Original author **gabrielfvale** · Original repo: https://github.com/gabrielfvale/scrappy
Scrappy is an art scraper for muOS, with the standout feature of incorporating a fully-fledged **Skyscraper** app under the hood. This integration enables near-complete support for artwork XML layouts, allowing Scrappy to scrape, cache assets, and generate artwork using XML mixes with ease.

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

![image](https://github.com/user-attachments/assets/3f22110f-9df0-4ee6-80f5-e83f42dd1052)

## Caveats
* Screenscraper credentials need to be manually added to `skyscraper_config.ini`
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
- Testers and many other contributors

## Supporting the project
- **Testing and feedback:** The most valuable support for this maintained fork is testing new builds, reporting issues, and submitting improvements via pull requests.
- **Donations to the original author:** Financial contributions via Ko‑fi support the original creator of Scrappy.

[![Ko-Fi](https://img.shields.io/badge/Ko--fi-F16061?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/gabrielfvale)

## Contributing

Contributions to Scrappy are welcome! Please fork the repository, make your changes, and submit a pull request.

## License

This project is licensed under the MIT License. See `LICENSE.md` for more details.
