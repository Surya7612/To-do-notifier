# Third-party assets

The **source code** of this project is MIT-licensed (see [LICENSE](../LICENSE)).

## Pet and tutor artwork

This is confined to the Electron app. The native companion (`TodoCompanion/`) ships no third-party art at all.

Sprite sheets under `src/assets/goku/` and images such as `src/assets/duckgoku.png` depict a well-known copyrighted character. They are included only as **personal / portfolio demo art**.

- **Not** covered by the MIT license
- **Not** an official or endorsed product of the rights holders
- Do **not** redistribute those files commercially or as a standalone asset pack

If you fork this repo for production use, replace the pet and tutor art with your own original assets. The sprites are loaded by `src/PetApp.tsx` and `src/components/TutoringPanel.tsx`, so those are the two files to point at new ones.

## Screenshots

`docs/screenshots/` shows a local build of the app for portfolio context. Task titles in screenshots are sample study items, not production user data.
