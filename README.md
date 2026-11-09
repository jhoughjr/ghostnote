# Ghostnote

Ghostnote is a free, open source Mac app for notes that follow your work.
A note attaches to the front app, and to the document or web page in it.
When you come back to that app or document, its note shows again.

The project is a rebuild of Ghostnote on a new context engine.
The engine is a Swift library that runs in the app's own process.
It finds the current context with the Accessibility API, and with small JSON manifests for each app or site.

## Status

The project is at its start. No build is available yet.

## Plan for the first release

- An app note always shows. A document note shows when the engine finds a document, a file, or a URL.
- Notes are Markdown files in a folder that you choose. Your sync tool syncs that folder.
- A global hotkey opens a small panel. You can pin the panel, and then it follows the context.
- The editor shows styled Markdown with checkboxes that you can click.
- The app asks for permissions only when a feature needs them. App notes need no permissions.
- The app is a notarized download with Sparkle updates. It is not in the Mac App Store.
- The minimum system is macOS 15.

## License

MIT. See [LICENSE](LICENSE).
