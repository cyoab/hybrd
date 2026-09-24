# Branded authentication email

The email OTP flow for both signup and sign-in uses `server/src/auth/emails/otp-template.ts`. It includes a responsive HTML layout, a plain-text alternative, one selectable six-digit code, the ten-minute expiry and single-use/security guidance. The subject and hidden inbox preview omit the code.

The palette follows the existing iOS brand sheet: Obsidian `#0D0D0E`, Terra `#FF6B3D`, Sand `#F4EDE7`, Stone `#CBD5E1` and Mist `#F8FAFC`. Terra is decorative; body text uses contrasting dark/light neutrals. Inline styles and presentation tables provide the baseline layout; media queries enhance narrow screens and clients supporting dark mode. Essential instructions remain readable when images are blocked.

`server/src/auth/emails/assets/hybrd-mark.png` is an **unchanged copy** of `ios/App/Assets.xcassets/AppIcon.appiconset/Icon.png` (the white h and orange dot on Obsidian). When the app mark changes, replace this copy too. The asset lives under `server/src` so both development and production Docker images include it without depending on the iOS directory. It is sent as a base64 PNG attachment with `content_id`, referenced by `cid:` in the HTML, following [Resend's inline image support](https://resend.com/changelog/embed-images-using-cid). No public asset host is required.

## Local preview

From the repository root:

```sh
bun run email:preview
# Or use the running development container:
docker compose exec api bun run email:preview
```

Open `dist/emails/otp.html` in a browser. The command also writes `dist/emails/otp.txt`. It uses the same template and logo as the real mailer with a fixed, nonfunctional sample code. For browser preview only, the CID reference becomes a data URI, making the HTML self-contained. It does not call Resend, need credentials or create an authentication challenge. Generated previews are gitignored.

Review at desktop and 320–390 px widths, with light/dark appearance and images blocked. Browser previews validate layout, not every mail client's HTML transformations: live acceptance still needs a real OTP requested through the backend and checked in Apple Mail/Gmail/Outlook. Automated tests mock Resend and check the actual PNG/CID payload, selectable leading-zero code, plain-text/security copy, malformed input rejection and identical retry payloads.
