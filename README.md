# WallyPackageLoader

Roblox Studio 안에서 패키지를 바로 불러오는 플러그인입니다.
`wally install` + Rojo 없이도 Wally / GitHub(pesde 방식) / 로컬 파일에서 패키지를 가져와
Wally 와 같은 `_Index` 구조로 설치합니다.

## 기능
- **Wally**: `sleitnick/signal@^2` 처럼 입력하면 api.wally.run 에서 받아 설치 (의존성 재귀 설치)
- **GitHub**: `gh:owner/repo@^1.0` (semver 태그), `gh:owner/repo#main` (브랜치/태그/커밋)
  - `wally.toml` 또는 `pesde.toml` 의 의존성도 같이 설치
  - pesde 는 중앙 레지스트리를 없애고 Git 태그 기반으로 바뀌는 중이라 ([RFC #59](https://github.com/pesde-pkg/pesde/issues/59)) GitHub 소스를 지원
- **파일에서 가져오기**: `.lua` / `.luau` (ModuleScript 하나), `.zip` (wally.toml 이 있으면 패키지로, 없으면 폴더로)
- **타입 re-export**: thunk 모듈이 패키지의 `export type` 을 다시 export 해서
  `Packages.Signal.Signal<T>` 같은 타입을 바로 사용 가능 (pesde 링커와 같은 방식, `const` 가 있는 소스도 처리)
- **설정**: `ServerStorage.PackageLoaderConfig` 에 저장되어 Team Create 로 공유
  - `SharedPackages` (기본 `ReplicatedStorage/Packages`)
  - `ServerPackages` (기본 `ServerScriptService/ServerPackages`)
  - `Dependencies` (설치한 패키지 목록, "Config 전체 설치" 로 다시 설치 가능)
- 설치 위치는 Config 경로를 쓰거나, 직접 입력 / Explorer 에서 선택한 폴더로 지정 가능
- **정리**: 어디서도 쓰이지 않는 `_Index` 엔트리 삭제 (이 플러그인이 만든 것만, Rojo 로 동기화한 Wally 패키지는 건드리지 않음)

## 설치 구조
```
ReplicatedStorage/Packages/
  Signal                      -- thunk (require + export type re-export)
  _Index/
    sleitnick_signal@2.0.1/
      signal                  -- 실제 패키지
      Promise                 -- 의존성 thunk
    evaera_promise@4.0.0/
      promise
```

## 빌드
```bash
rokit install
# Windows
rojo build -o "$LOCALAPPDATA/Roblox/Plugins/WallyPackageLoader.rbxm"
# macOS
rojo build -o ~/Documents/Roblox/Plugins/WallyPackageLoader.rbxm
```
처음 사용할 때 Studio 가 HTTP 요청(api.wally.run, api.github.com, codeload.github.com)과
스크립트 삽입 권한을 물어봅니다.

## 구조
| 파일 | 역할 |
|---|---|
| `src/init.server.luau` | 툴바 버튼, DockWidget |
| `src/Ui.luau` | UI |
| `src/Installer.luau` | 스펙 해석, 의존성 재귀 설치, Config 저장, 정리 |
| `src/Linker.luau` | `_Index` 구조, thunk 생성, require 경로 계산 |
| `src/Builder.luau` | 파일 -> Instance (Rojo 규칙, `default.project.json`) |
| `src/Config.luau` | `PackageLoaderConfig` 읽기/쓰기 |
| `src/Http.luau` | HttpService 래퍼 |
| `src/Sources/` | Wally, GitHub, File, manifest(wally.toml / pesde.toml) |
| `src/Util/` | Inflate(deflate/gzip), Zip, Semver, Toml, TypeExports, Vfs |

## 아직 안 되는 것
- pesde 레지스트리 패키지 (`name = "scope/name"` 형식 의존성), GitHub 외 Git 저장소
- 패키지 안의 `.rbxm` / `.rbxmx` / `.model.json`, `*.meta.json` 속성
- zip64, 암호화된 zip

## 참고한 레퍼런스
- [zzlib.luau](https://github.com/xhayper/zzlib.luau) (WTFPL) - Inflate 구조
- [roblox-package-manager](https://github.com/McThor2/roblox-package-manager) (MIT) - Wally API 사용법, 파일 변환, 설정 저장 방식
- [pesde](https://github.com/pesde-pkg/pesde) (MIT) - thunk 의 타입 re-export 로직 (`src/linking/generator.rs`)
- [wally-package-types](https://github.com/JohnnyMorganz/wally-package-types) (MIT) - 타입 re-export 아이디어
