# Signing material, encrypted

Nothing is here yet. When the App Store record and its provisioning profile
exist, four encrypted blobs live in this directory:

    dist.p12.enc                 certificate and private key
    profile.mobileprovision.enc  the App Store profile for com.crownparkcomputing.fuji
    asc_key.p8.enc               App Store Connect API key
    signing.env.enc              CERT_PASSWORD, ASC_KEY_ID, ASC_ISSUER_ID

AES-256-CBC, PBKDF2 at 600,000 iterations, all four under one passphrase.

## The one secret

CI needs a single repository secret, `SIGNING_PASSPHRASE`, and decrypts all four
with it. Without it the release job does nothing and the unsigned simulator
build still runs, so a broken tree still fails loudly.

**The passphrase never goes in this repository.** Encrypted files stored beside
their passphrase are plaintext with extra steps.

## What can be reused and what cannot

The distribution certificate (`dist.p12.enc`) and the App Store Connect API key
(`asc_key.p8.enc`) are **account-level** and are the same ones the other apps
use.

`profile.mobileprovision.enc` is **not**. A provisioning profile is bound to one
bundle id, so this app needs its own, created for `com.crownparkcomputing.fuji` after the App Store
record exists. Reusing another app's profile fails at signing with a message
about entitlements that does not mention the bundle id at all.

## Encrypting

    openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
      -in profile.mobileprovision -out signing/profile.mobileprovision.enc \
      -pass env:PASS

`.gitattributes` marks `*.enc` as binary. That is not cosmetic: git guessed
"text" for a 144-byte AES blob that happened to contain no NUL, and a checkout
under `core.autocrlf=true` rewrote its line endings and corrupted it. The damage
showed up in CI at `security import` as a complaint about the password, which
reads like a broken certificate.
