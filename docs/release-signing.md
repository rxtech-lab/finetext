# Release signing

FineText uses **Rxlab LIMITED**, Apple team **T7GYB573Y6**. `project.yml`
sets the local Xcode team. The release workflow uses the repository variable
`APPLE_TEAM_ID`, defaulting to the same RxLab team, for both archive signing and
notarization.

After importing the certificate, CI selects a valid **Developer ID Application**
identity belonging to that team and uses its fingerprint for the app, Sparkle
helpers, and DMG. It stops if the identity is missing or ambiguous. The legacy
`SIGNING_CERTIFICATE_NAME` secret is no longer read.

Configure these GitHub Actions secrets at repository level or through organization
secrets accessible to this repository:

| Secret | Required value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Base64 PKCS#12 export of the RxLab Developer ID Application certificate **and private key** |
| `P12_PASSWORD` | Password for that PKCS#12 export |
| `APPLE_ID` | Apple account with access to the RxLab team |
| `APPLE_ID_PWD` | App-specific password belonging to that Apple account |
| `SPARKLE_KEY` | Existing Sparkle signing key; preserve it for update continuity |

Keep the existing `SPARKLE_PUBLIC_KEY` repository variable. A certificate belonging
to the individual team `P9KK452K8P` cannot sign an RxLab release.

GitHub does not reveal saved secret values. An absent repository secret may still
be inherited from the organization. Verify certificate/team matching in a release
run. A notarization HTTP 401 requires checking the `APPLE_ID` and `APPLE_ID_PWD`
pair; generate the password at <https://account.apple.com/> and set it directly in
[GitHub Actions secrets](https://github.com/rxtech-lab/finetext/settings/secrets/actions).
Do not paste passwords or private keys into chat.
