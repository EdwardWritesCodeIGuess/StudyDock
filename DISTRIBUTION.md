# Mac installation and verified releases

## Fix installation on this Mac

Quit StudyDock, then build and install directly from the source checkout:

```sh
bash Scripts/install-local.sh
```

This puts a fresh local build in `/Applications/StudyDock.app` and opens it. The previous app is backed up under `build/local-backups/`. Your saved data and preferences are preserved. It does not disable Gatekeeper or change system security settings. It requires Swift Command Line Tools; downloaded GitHub builds still need Apple's trust check.

## Make the public download pass Apple's verification

The 1.1.2 release contains source for local installation. Add a downloadable app only after Apple accepts the notarization and Gatekeeper verifies the packaged app. Older preview downloads were ad hoc signed.

Requirements:

- Apple Developer Program membership and a **Developer ID Application** certificate with its private key in the signing Mac's keychain.
- Xcode tools that include `notarytool` and `stapler`.
- A `notarytool` keychain profile. Create one interactively with `xcrun notarytool store-credentials studydock-notary` and follow Apple's prompts. Do not paste passwords, private keys, or certificates into chat or commit them to Git.

Then run:

```sh
export CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE='studydock-notary'
bash Scripts/notarize-release.sh
```

The build enables hardened runtime and secure timestamps for Developer ID signing. The script submits the app to Apple, checks for **Accepted**, staples and validates the ticket, assesses the app with Gatekeeper, creates a signed DMG, notarizes and staples that too, and assesses the final disk image. It stops on any failure. Only the `*-notarized.dmg`, `*-notarized.zip`, and matching checksum file should be uploaded as the verified release. Local ad-hoc builds are never labeled notarized.

Notarization cannot be completed without the certificate and Apple service access. This repository contains no signing credentials.

[Apple: Developer ID](https://developer.apple.com/developer-id/) · [Apple: notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
