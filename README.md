# WallyPackageLoader

English | [한국어](README.ko.md)

A Roblox Studio plugin that loads packages right inside Studio.
Without `wally install` or Rojo, it fetches packages from Wally / pesde / GitHub / local files
and installs them in the same `_Index` layout Wally uses.

The plugin speaks English and Korean. It follows the Studio language by default; change it with `lang en` / `lang ko` (`lang auto` to follow Studio again).

## Features
- **Wally**: `add sleitnick/signal@^2` puts it in the Config, `install` downloads it from api.wally.run (dependencies are installed recursively)
- **GitHub**: `gh:owner/repo@^1.0` (semver tags), `gh:owner/repo#main` (branch / tag / commit)
  - Dependencies in `wally.toml` or `pesde.toml` are installed too
- **pesde**: `pesde:scope/name@^1.0` (registry.pesde.daimond113.com). Only versions with a Roblox target (roblox / roblox_server); the `.tar.gz` is installed using `target.lib` from pesde.toml. pesde / Wally dependencies are installed too
- **Import from files**: `.lua` / `.luau` (several at once), `.zip` (dependencies too if it has a wally.toml)
  - Imported files are kept in the `Imported` folder inside `PackageLoaderConfig` and added to the Config as `Name = script.Imported.Name`
  - Plain folders cannot be picked (Studio has no folder picker), so zip them first
- **Type re-export**: thunks re-export the package's `export type`s, so types like `Packages.Signal.Signal<T>` just work (same approach as the pesde linker, handles sources using `const`)
- **Rojo file formats**: `.model.json`, `*.meta.json` / `init.meta.json` (properties, attributes, className, Tags),
  `$properties` / `$attributes` in project.json, `.rbxm` (`SerializationService`, skipped if unreadable)
- **Prune**: removes `_Index` entries nothing uses (only ones this plugin made; Wally packages synced by Rojo are left alone)

## Usage
Type a command in the input box and press Enter, or type a package / path and press a button.
Logs only go to the plugin window, never to the Output window. Errors / done / warnings are colored (matching the Studio theme).

### Commands
```
vide = cayasde/vide-opinionated       without a command it is add
add cayasde/vide-opinionated          add to the Config (alias is the package name vide-opinionated, version pinned to @0.4.3)
add vide = cayasde/vide-opinionated@^0.4   alias vide (... as vide works too)
add <package> --server                add to the server path
add <package> --selected              add to the folder selected in the Explorer
add <package> --to ServerStorage/Libs add to the given path
remove asdf  /  remove ro-bura/signal remove by alias or package name (rm works too)
install                               install from the Config (removes what is not listed, installs what is)
import [--server | --selected | --to <path>]   import from files
import --select [--server | --to <path>]      copy what is selected in the Explorer (the original stays)
path shared <path | --selected>       set the shared path
path server <path | --selected>       set the server path
path reset [shared | server]          back to the default path (both when nothing follows, path shared --reset works too)
list                                  list installed packages
tree [--selected]                     dependency tree (from the Config / from a selected wally.toml, thunk or package folder)
prune                                 remove unused _Index folders
config                                open the Config script
login --agree [--remember]            GitHub device login (Wally publishing + higher GitHub request limit)
login --agree --password <pw> --r <pw>   log in and save encrypted with a password (--r repeats it)
login <token> --agree [--remember]    a GitHub token you made (only the GitHub request limit)
logout [--keep] / whoami              log out (also deletes the saved token, --keep keeps it) / logged in account
login [--password <pw>]               unlock the saved login (without --password, a hidden input box)
cancel                                cancel a GitHub login that is waiting (runs even while busy)
publish [--yes | --no]                publish the selected package to Wally (uses the wally.toml inside it)
clear                                 clear the log
lang [ko | en | auto]                 language (follows Studio by default)
license                               license and notices for referenced projects
privacy / terms                       privacy notice / terms of use
help [command]                        help (help add for details)
```
You can drag to select and copy text in the log (edits are undone right away).
Commands containing a token / password are shown as `****` in the log.

`add` only writes to the Config, like `wally add`. Installing is done by `install` (the Install All button).
Without a version, the found version is pinned (`cayasde/vide-opinionated` -> `cayasde/vide-opinionated@0.4.3`).

### GitHub login / publishing to Wally
- Login is command only. Once logged in, the Logout / Prepare Publish buttons appear.
- By default the token lives **only in memory** and is gone when Studio closes. It never goes into the place (Config etc.).
- With `--remember`, you pick a password (10+ characters, typed twice) after logging in, and the token is saved **encrypted** with it on this computer via `plugin:SetSetting`.
  You can also type it inline: `login --agree --password <pw> --r <pw>` (`--r` catches typos, shown as `****` in the log).
  After restarting Studio, unlock it with `login --password <pw>` (or `login` and the hidden input box). With a saved login, `login` unlocks it instead of logging in again. To start over: `logout`, then `login --agree`.
  - Encryption: PBKDF2-HMAC-SHA256 (random salt, as many iterations as take about 1 second on this computer, at least 20,000) + HMAC-SHA256 keystream + HMAC tag
  - Whoever gets the settings file cannot use the token without the password. A short or common password can still be guessed, so pick a long one.
  - Forgot the password? `logout`, then `login --agree --remember` again.
- The token in `login <token>` is shown as `****` in the log.
- `login` shows the warnings every time and only proceeds with `--agree`, meaning you read and agree to `privacy` / `terms`.
- `login --agree`: the same GitHub device login as `wally login` (Wally's GitHub OAuth app, `read:user` scope).
  Enter the code at the shown address (github.com/login/device) and approve.
- `login <token> --agree`: a token you made (no scopes needed). Only raises the GitHub API request limit (60 -> 5000 per hour).
  The Wally server only accepts tokens from the Wally app, so publish with `login`.
- `publish`: like `wally publish`, it uses the `wally.toml` inside the package as the manifest.
  1. Select the package (usually a ModuleScript) in the Explorer and run `publish` (Prepare Publish button).
     Without a `wally.toml`, it creates a `wally.toml` ModuleScript inside the package and opens it. Fill in name / version / description / authors / dependencies.
     It is real TOML, so you can paste an existing wally.toml (wrapping it in `return [==[ ... ]==]` is optional).
  2. Run `publish` again to preview the files and the `wally.toml`.
  3. `publish --yes` publishes what you just saw, `publish --no` cancels. If something changed after the preview, it shows the preview again instead.
  - The `wally.toml` script is left out of the upload and becomes the `wally.toml` file in the zip.
  - ModuleScript / Script / LocalScript -> `.luau`, Folder -> folder, StringValue -> `.txt`, anything else -> `.rbxm`
  - Selecting a thunk in Packages publishes the real module it points to.
  - Only Wally packages (`scope/name@version`) can be dependencies. Require them with `require(script.Parent.Alias)`.
    While developing, keep the package inside the shared path (`ReplicatedStorage/Packages`) so the thunks next to it resolve dependencies.
  - **The same version cannot be published twice, and published versions cannot be deleted.**

### Search window
Open it with the **Search** toolbar button. Type a search word and press Enter (or the magnifying glass), then **Add** a result to the Config (install with Install All).
- Search in: Wally, pesde (Roblox packages only), GitHub (any combination)
- Packages already in the Config show Added instead of Add
- ⚙: narrow by author (Wally scope / GitHub user), GitHub Luau repositories only
- GitHub search matches repository names / descriptions (it does not check for a wally.toml). Without login the request limit is low (10 per minute)
- Click a result for details: pick a version; per version description / realm / license / authors / dependencies; `Add <version>` / `Add ^<version>`; **Files** (file list)
  - GitHub: stars (starred by you when logged in), license, last push, wally.toml / pesde.toml dependencies, start of the README
  - Files: click a file to view it (Back to Info / Back to Files to go back). Wally / pesde download the package, GitHub fetches only the clicked file
  - The text and the Config line box can be selected and copied
- Icons use the Roblox Builder Icons font that ships with Studio

### Buttons
| Button | Action |
|---|---|
| Add / Add to Server / Add to Selected | Add the typed package to the Config under shared / server / the selected folder (install with Install All) |
| Remove | Remove the typed alias or package; with an empty input, the package selected in the Explorer |
| Install All | Install from the Config. Removes what is not listed (only things the plugin made), like `wally install` |
| Prune | Remove unused `_Index` folders. Remove does this already, so it is only needed after deleting a thunk by hand |
| Import File | File picker. Kept under the Config, added to it and installed to the shared path (elsewhere: `import --selected` / `--to`) |
| Open Config | Open the Config script |
| Set Shared Path / Set Server Path | Use the folder selected in the Explorer (or the typed path) |
| List / Help | Installed packages / command help |
| Logout / Prepare Publish | **Only while logged in.** Log out / create the `wally.toml` in the selected package or preview it (publish with `publish --yes`) |

## Config (ServerStorage.PackageLoaderConfig)
A ModuleScript you can edit; it is shared through Team Create. After editing it by hand, press **Install All**.
```luau
return {
	shared = "ReplicatedStorage/Packages",
	server = "ServerScriptService/ServerPackages",

	dependencies = {
		Signal = "sleitnick/signal@^2",
		MyLib = script.Imported.MyLib,  -- imported by hand (Import File)
	},
	serverDependencies = {},
	custom = {
		["ServerStorage/Libs"] = {
			Myrepo = "gh:me/myrepo@^1",
		},
	},
}
```
- `shared` / `server` can be a path string (`"ReplicatedStorage/Packages"`, `"game/ReplicatedStorage/Packages"`) or an Instance (`game.ReplicatedStorage.Packages`).
- A value can be an Instance instead of a spec (`MyLib = script.MyLib`). It is copied on install, so the original stays under the Config.
  A ModuleScript is copied to `_Index/custom_Alias` with a thunk; anything else (Folder etc.) is copied straight to the install location.
- `install` only removes things the plugin made (thunks / copies) that are no longer listed. Things you put there yourself are left alone.

When the Config is first created, a comment listing the available keys is added at the bottom.
Add / Remove / path changes only edit the lines they need, so your comments and order are kept.
If the structure cannot be understood (e.g. the table is built with code), nothing is changed and an error is shown.
Names with `-` are written as `["vide-opinionated"] = "cayasde/vide-opinionated@0.4.3"` (Luau syntax).

## Install layout
```
ReplicatedStorage/Packages/
  Signal                      -- thunk (require + export type re-export)
  _Index/
    sleitnick_signal@2.0.1/
      signal                  -- the package
      Promise                 -- dependency thunk
    evaera_promise@4.0.0/
      promise
```

## Installation
1. Download the latest `WallyPackageLoader.rbxm` from [Releases](https://github.com/RO-BURa/WallyPackageLoader/releases).
2. In Studio, click **Plugins → Plugins Folder** and put it in the folder that opens.
3. Reopen Studio and the buttons appear in the toolbar.

To update, overwrite it with the new `.rbxm`.

## Building
```bash
rokit install
rojo build --plugin WallyPackageLoader.rbxm
```
`--plugin` builds straight into Studio's local plugins folder.

Pushing a tag like `v0.1.0` makes GitHub Actions build the `.rbxm` and attach it to a Release (`.github/workflows/release.yml`).

On first use Studio asks for HTTP access (api.wally.run, registry.pesde.daimond113.com, api.github.com, codeload.github.com, raw.githubusercontent.com, github.com for login) and script injection.

## Source layout
| File | Role |
|---|---|
| `src/init.server.luau` | Toolbar buttons, DockWidgets |
| `src/Ui.luau` | Main window UI |
| `src/SearchUi.luau` | Search window UI |
| `src/Locale.luau` | Korean / English |
| `src/Tree.luau` | Dependency tree |
| `src/Installer.luau` | Spec resolving, recursive install, Config updates, prune |
| `src/Linker.luau` | `_Index` layout, thunks, require paths |
| `src/Builder.luau` | Files -> Instances (Rojo rules, `default.project.json`) |
| `src/Config.luau` | Reading / writing the `PackageLoaderConfig` ModuleScript |
| `src/Http.luau` | HttpService wrapper |
| `src/Auth.luau` | GitHub login (device login / token), token storage |
| `src/Publisher.luau` | Instance -> Wally package zip, upload |
| `src/Sources/` | Wally, pesde, GitHub, File, manifest (wally.toml / pesde.toml), Search, Details (search detail view) |
| `src/Util/` | Inflate (deflate/gzip), Zip (read/write), Tar, Crypto (SHA-256, PBKDF2, token encryption), Semver, Toml, Lexer, TypeExports, ConfigEditor, RojoValues (Rojo property values), Vfs |

## Not supported yet
- Other pesde indexes (the default registry only), Git hosts other than GitHub
- `.rbxmx` (XML models) only when `SerializationService` can read them
- zip64, encrypted zips

## References
- [zzlib.luau](https://github.com/xhayper/zzlib.luau) (WTFPL) - Inflate structure
- [roblox-package-manager](https://github.com/McThor2/roblox-package-manager) (MIT) - Wally API usage, file conversion, settings storage
- [pesde](https://github.com/pesde-pkg/pesde) (MIT) - type re-export logic for thunks (`src/linking/generator.rs`)
- [wally-package-types](https://github.com/JohnnyMorganz/wally-package-types) (MIT) - the type re-export idea

## Notes for the Creator Store
- The Roblox Community Standards do not allow linking to or showing external site URLs, so the text inside the plugin (`PRIVACY`, `TERMS`, `THIRD_PARTY_NOTICES`, error messages) has no external links.
  The one exception is the GitHub login address needed for device login. The store description has no links either.

## License / privacy / terms
[MIT](LICENSE). Privacy notice: [PRIVACY.md](PRIVACY.md), terms of use: [TERMS.md](TERMS.md). Notices for referenced projects are in [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).
All four files are bundled into the plugin as StringValues at build time (`syncRules` in `default.project.json`)
and can be read with the `license` / `privacy` / `terms` commands. A `LICENSE` module is also created inside `PackageLoaderConfig` the first time (you can delete it).
