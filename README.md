# WallyPackageLoader

Roblox Studio 안에서 패키지를 바로 불러오는 플러그인입니다.
`wally install` + Rojo 없이도 Wally / GitHub(pesde 방식) / 로컬 파일에서 패키지를 가져와
Wally 와 같은 `_Index` 구조로 설치합니다.

## 기능
- **Wally**: `sleitnick/signal@^2` 처럼 입력하면 api.wally.run 에서 받아 설치 (의존성 재귀 설치)
- **GitHub**: `gh:owner/repo@^1.0` (semver 태그), `gh:owner/repo#main` (브랜치/태그/커밋)
  - `wally.toml` 또는 `pesde.toml` 의 의존성도 같이 설치
  - pesde 는 중앙 레지스트리를 없애고 Git 태그 기반으로 바뀌는 중이라 ([RFC #59](https://github.com/pesde-pkg/pesde/issues/59)) GitHub 소스를 지원
- **파일에서 가져오기**: `.lua` / `.luau` (여러 개 한 번에 선택 가능), `.zip` (wally.toml 이 있으면 패키지로, 없으면 폴더로)
  - 일반 폴더는 Studio API 에 폴더 선택 기능이 없어서 zip 으로 압축해서 가져와야 함
- **타입 re-export**: thunk 모듈이 패키지의 `export type` 을 다시 export 해서
  `Packages.Signal.Signal<T>` 같은 타입을 바로 사용 가능 (pesde 링커와 같은 방식, `const` 가 있는 소스도 처리)
- **정리**: 어디서도 쓰이지 않는 `_Index` 엔트리 삭제 (이 플러그인이 만든 것만, Rojo 로 동기화한 Wally 패키지는 건드리지 않음)

## 사용법
입력창에 명령을 치고 Enter 를 누르거나, 입력창에 패키지/경로를 적고 버튼을 누릅니다.
로그는 플러그인 창에만 나오고 Output 창에는 찍지 않습니다.

### 명령어
```
asdf = ro-bura/signal                 명령어 없이 치면 add
add ro-bura/signal                    별칭 자동 (Signal)
add asdf = ro-bura/signal@^1          별칭 asdf (ro-bura/signal as asdf 도 됨)
add <패키지> --server                 server 경로에 설치
add <패키지> --selected               Explorer 에서 선택한 폴더에 설치
add <패키지> --to ServerStorage/Libs  지정한 경로에 설치
remove asdf  /  remove ro-bura/signal 별칭이나 패키지 이름으로 삭제 (rm 도 됨)
install                               Config 에 적힌 패키지 전체 설치
import [--server | --selected | --to <경로>]   파일에서 가져오기
path shared <경로 | --selected>       shared 경로 설정
path server <경로 | --selected>       server 경로 설정
list                                  설치한 패키지 목록
prune                                 안 쓰는 _Index 폴더 정리
config                                Config 스크립트 열기
clear                                 로그 지우기
help                                  도움말
```
↑ / ↓ 로 이전에 입력한 명령을 불러옵니다.

### 버튼
| 버튼 | 동작 |
|---|---|
| Add / Add to Server / Add to Selected | 입력한 패키지를 shared 경로 / server 경로 / 선택한 폴더에 설치 |
| Remove | 입력한 별칭이나 패키지 삭제, 입력이 비어 있으면 Explorer 에서 선택한 패키지 삭제 |
| Install All | Config 에 적힌 패키지 전체 설치 (`wally install` 과 비슷) |
| Prune | 안 쓰는 `_Index` 폴더 정리. Remove 할 때 자동으로 하므로 thunk 를 손으로 지웠을 때만 필요 |
| Import File | 파일 선택 창. Explorer 에서 선택한 곳, 없으면 shared 경로에 가져옴 |
| Open Config | Config 스크립트 열기 |
| Set Shared Path / Set Server Path | Explorer 에서 선택한 폴더(없으면 입력한 경로)로 설정 |
| List / Help | 설치한 패키지 목록 / 명령어 도움말 |

## 설정 (ServerStorage.PackageLoaderConfig)
직접 고칠 수 있는 ModuleScript 이고 Team Create 로 공유됩니다. 직접 고친 뒤에는 **Install All** 을 누릅니다.
```luau
return {
	shared = "ReplicatedStorage/Packages",
	server = "ServerScriptService/ServerPackages",

	dependencies = {
		Signal = "sleitnick/signal@^2",
	},
	serverDependencies = {},
	custom = {
		["ServerStorage/Libs"] = {
			Myrepo = "gh:me/myrepo@^1",
		},
	},
}
```
처음 만들 때 맨 아래에 쓸 수 있는 항목 설명이 주석으로 들어갑니다.
Add / Remove / 경로 설정은 필요한 줄만 고치기 때문에 직접 단 주석과 순서가 그대로 남습니다.
테이블을 코드로 만드는 등 구조를 알아볼 수 없을 때만 파일 전체를 다시 씁니다 (이때는 주석이 사라짐).

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
rojo build --plugin WallyPackageLoader.rbxm
```
`--plugin` 은 Studio 의 로컬 플러그인 폴더에 바로 빌드합니다.

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
| `src/Config.luau` | `PackageLoaderConfig` ModuleScript 읽기/쓰기 |
| `src/Http.luau` | HttpService 래퍼 |
| `src/Sources/` | Wally, GitHub, File, manifest(wally.toml / pesde.toml) |
| `src/Util/` | Inflate(deflate/gzip), Zip, Semver, Toml, Lexer, TypeExports, ConfigEditor, Vfs |

## 아직 안 되는 것
- pesde 레지스트리 패키지 (`name = "scope/name"` 형식 의존성), GitHub 외 Git 저장소
- 패키지 안의 `.rbxm` / `.rbxmx` / `.model.json`, `*.meta.json` 속성
- zip64, 암호화된 zip

## 참고한 레퍼런스
- [zzlib.luau](https://github.com/xhayper/zzlib.luau) (WTFPL) - Inflate 구조
- [roblox-package-manager](https://github.com/McThor2/roblox-package-manager) (MIT) - Wally API 사용법, 파일 변환, 설정 저장 방식
- [pesde](https://github.com/pesde-pkg/pesde) (MIT) - thunk 의 타입 re-export 로직 (`src/linking/generator.rs`)
- [wally-package-types](https://github.com/JohnnyMorganz/wally-package-types) (MIT) - 타입 re-export 아이디어

## 라이선스
[MIT](LICENSE)
