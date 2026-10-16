# Privacy Notice

WallyPackageLoader is a Roblox Studio plugin. It does not run any servers of its own and does not collect analytics or telemetry.

## What data is used

- **GitHub access token** (only if you use `login`): either a token from GitHub's OAuth Device Flow (the same flow as `wally login`, scope `read:user`) or a personal access token you paste in.
- **GitHub username**: read from `api.github.com/user` with your token to show who is logged in (`whoami`) and to confirm a login worked.
- **Package names, versions and contents** you add, install, import or publish.

The plugin never asks for your Roblox password, cookie or any other Roblox credential.

## Where it is stored

- By default the GitHub token is kept **only in memory** and is forgotten when Roblox Studio closes.
- Only if you log in with `--remember`, the token is **encrypted with a password you choose** (at least 10 characters) and saved **on your computer** in Roblox Studio's plugin settings (`plugin:SetSetting`). You unlock it with `unlock` after restarting Studio.
  The password itself is never saved or sent anywhere. Plugin settings are stored as a plain file, so anyone who gets the file could try to guess a weak password; choose a long one.
- It is **never** saved into the place (including `PackageLoaderConfig`), so it is not shared through Team Create or published places.
- `PackageLoaderConfig` (in `ServerStorage`) stores only package names, versions and paths, and files you imported. It is part of your place.

## Where it is sent

The plugin only talks to these services (the same domains Roblox Studio asks you to approve):

| Destination | What is sent | When |
| --- | --- | --- |
| `github.com` | OAuth Device Flow requests | `login` |
| `api.github.com` | Your token (Authorization header) | `login`, `whoami`, GitHub packages (`gh:`) while logged in |
| `api.wally.run` | Your token (Authorization header) and the package you upload | `publish --yes` only |
| `api.wally.run`, `codeload.github.com`, `raw.githubusercontent.com` | Package names and versions (no token) | `add`, `install`, `login` |

Nothing is sent to the plugin author or to any other third party. Every HTTP destination must first be approved by you in Roblox Studio's plugin permission prompt.

## Deleting your data

- Run `logout` to forget the token and delete it from your computer if it was saved with `--remember`.
- To revoke the token on GitHub's side, remove it under GitHub **Settings > Applications** (device login) or **Settings > Developer settings > Personal access tokens** (token login).
- Packages published to Wally are public and cannot be deleted by this plugin. See Wally's policies for removal requests.

## Contact

Questions or concerns: contact the plugin creator through their Roblox profile.
