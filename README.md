# Smart Collection Sync

A Lightroom Classic plugin that mirrors smart collections to regular collections, enabling synchronization with Lightroom CC/Mobile/Web.

## The Problem

Smart collections in Lightroom Classic cannot be synced to Adobe's cloud. Only regular collections can be synced. This means your carefully curated smart collections (like "5 Star Photos" or "Portfolio Candidates") aren't available on your mobile devices or the web.

## The Solution

This plugin automatically creates and maintains "mirror" collections that stay in sync with your smart collections. When photos are added to or removed from a smart collection, the mirror collection is updated accordingly.

## Features

- **Automatic background sync** - Optional, runs at a configurable interval (10-300 seconds); skips smart collections over 10,000 photos
- **Manual sync** - Trigger immediate sync of every selected collection via menu command
- **Two-way mirror** - Both additions and removals are synced
- **Develop module awareness** - Option to pause sync while editing photos
- **Clean organization** - All mirror collections placed in a dedicated collection set
- **Persistent settings** - Configuration survives Lightroom restarts

## Installation

1. Download or clone this repository
2. Place the `lrc-smart-collection-sync.lrplugin` folder wherever you like (e.g., your Lightroom catalog directory or Pictures folder)
3. In Lightroom Classic, go to **File > Plug-in Manager**
4. Click **Add** and navigate to the `lrc-smart-collection-sync.lrplugin` folder
5. Click **Done**

## Usage

### Configuration

1. Go to **File > Plug-in Extras > Smart Collection Sync...**
2. Select which smart collections you want to mirror
3. Configure the destination collection set name (default: "Smart Collection Sync")
4. Set the auto-sync interval
5. Enable auto-sync if desired
6. Click **Save** or **Sync Now**

### Menu Commands

| Command | Location | Description |
|---------|----------|-------------|
| Smart Collection Sync... | File > Plug-in Extras | Opens configuration dialog |
| Sync Now | File > Plug-in Extras | Triggers immediate sync |

### Options

- **Enable auto-sync** - Automatically sync at the configured interval
- **No sync while in Develop** - Pause syncing while editing photos to avoid disruption

### Large collections

The Lightroom SDK has no cheap way to count a smart collection or tell whether it has changed, so every sync loads every photo in the smart collection and its mirror. That is fine for small collections but too slow to repeat every few seconds on large ones.

Each sync records how many photos each smart collection has. Auto-sync skips any collection last seen with more than 10,000 photos, without loading it, and the configuration dialog marks those collections. **Sync Now** always syncs every selected collection and refreshes the recorded sizes, so a collection that shrinks below the limit goes back to auto-sync.

Splitting a large smart collection into several smaller ones doesn't help: each pass would still load all of their photos.

## How It Works

1. The plugin scans all smart collections in your catalog
2. For each selected smart collection, it creates a regular collection with the same name inside the destination collection set
3. Photos are added to/removed from the mirror collection to match the smart collection
4. The mirror collections can then be synced to Adobe's cloud using Lightroom's built-in sync feature

## Requirements

- Lightroom Classic

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Author

Donncha O Caoimh https://inphotos.org/

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

If you encounter any issues or have feature requests, please [open an issue](https://github.com/donnchawp/lrc-smart-collection-sync/issues) on GitHub.
