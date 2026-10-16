# WallyPackageLoader

Roblox Studio 안에서 패키지를 바로 불러오는 플러그인입니다.
`wally install` + Rojo 없이도 Wally / GitHub(pesde 방식) / 로컬 파일에서 패키지를 가져와
Wally 와 같은 `_Index` 구조로 설치합니다.

## 기능
- **Wally**: `sleitnick/signal@^2` 처럼 add 로 Config 에 추가하고 install 로 api.wally.run 에서 받아 설치 (의존성 재귀 설치)
- **GitHub**: `gh:owner/repo@^1.0` (semver 태그), `gh:owner/repo#main` (브랜치/태그/커밋)
  - `wally.toml` 또는 `pesde.toml` 의 의존성도 같이 설치
  - pesde 는 중앙 레지스트리를 없애고 Git 태그 기반으로 바뀌는 중이라 ([RFC #59](https://github.com/pesde-pkg/pesde/issues/59)) GitHub 소스를 지원
- **파일에서 가져오기**: `.lua` / `.luau` (여러 개 한 번에 선택 가능), `.zip` (wally.toml 이 있으면 의존성도 설치)
  - 가져온 것은 `PackageLoaderConfig` 안의 `Imported` 폴더에 보관하고 Config 에 `이름 = script.Imported.이름` 으로 적은 뒤 설치
  - 일반 폴더는 Studio API 에 폴더 선택 기능이 없어서 zip 으로 압축해서 가져와야 함
- **타입 re-export**: thunk 모듈이 패키지의 `export type` 을 다시 export 해서
  `Packages.Signal.Signal<T>` 같은 타입을 바로 사용 가능 (pesde 링커와 같은 방식, `const` 가 있는 소스도 처리)
- **Rojo 파일 형식**: 패키지 안의 `.model.json`, `*.meta.json` / `init.meta.json` (properties, attributes, className, Tags),
  project.json 의 `$properties` / `$attributes`, `.rbxm` (`SerializationService`, 읽을 수 없으면 건너뜀) 지원
- **정리**: 어디서도 쓰이지 않는 `_Index` 엔트리 삭제 (이 플러그인이 만든 것만, Rojo 로 동기화한 Wally 패키지는 건드리지 않음)

## 사용법
입력창에 명령을 치고 Enter 를 누르거나, 입력창에 패키지/경로를 적고 버튼을 누릅니다.
로그는 플러그인 창에만 나오고 Output 창에는 찍지 않습니다. 오류/완료/경고 등은 색으로 구분합니다 (Studio 테마에 맞춤).

### 명령어
```
vide = cayasde/vide-opinionated       명령어 없이 치면 add
add cayasde/vide-opinionated          Config 에 추가 (별칭은 원래 이름 vide-opinionated, 버전은 @0.4.3 으로 고정)
add vide = cayasde/vide-opinionated@^0.4   별칭 vide (... as vide 도 됨)
add <패키지> --server                 server 경로에 추가
add <패키지> --selected               Explorer 에서 선택한 폴더에 추가
add <패키지> --to ServerStorage/Libs  지정한 경로에 추가
remove asdf  /  remove ro-bura/signal 별칭이나 패키지 이름으로 삭제 (rm 도 됨)
install                               Config 대로 설치 (Config 에 없는 건 지우고 적힌 건 설치)
import [--server | --selected | --to <경로>]   파일에서 가져오기
path shared <경로 | --selected>       shared 경로 설정
path server <경로 | --selected>       server 경로 설정
list                                  설치한 패키지 목록
prune                                 안 쓰는 _Index 폴더 정리
config                                Config 스크립트 열기
login --agree [--remember]            GitHub 기기 로그인 (Wally 업로드 + GitHub 요청 한도)
login <토큰> --agree [--remember]     직접 만든 GitHub 토큰 (GitHub 요청 한도만)
logout / whoami                       로그아웃 / 로그인한 계정
cancel                                기다리는 중인 GitHub 로그인 취소 (다른 작업 중에도 실행됨)
publish <scope/name@버전> [--server] [--deps] [--yes]   선택한 것을 Wally 에 업로드
clear                                 로그 지우기
license                               라이선스와 참고한 프로젝트 고지
privacy / terms                       개인정보 처리 안내 / 이용 약관
help [명령어]                         도움말 (help add 처럼 자세히)
```
↑ / ↓ 로 이전에 입력한 명령을 불러옵니다.

`add` 는 `wally add` 처럼 Config 에만 적습니다. 실제 설치는 `install` (Install All 버튼) 로 합니다.
버전을 안 적으면 찾은 버전으로 고정해서 적습니다 (`cayasde/vide-opinionated` -> `cayasde/vide-opinionated@0.4.3`).

### GitHub 로그인 / Wally 업로드
- 로그인은 명령어로만 합니다. 로그인하면 Logout / Publish 버튼이 나타납니다.
- 토큰은 기본적으로 **메모리에만** 있고 Studio 를 끄면 사라집니다. `--remember` 를 붙이면 `plugin:SetSetting` 으로 이 컴퓨터에 저장해서 로그인이 유지되지만,
  설정은 암호화되지 않고 다른 로컬 플러그인이 읽을 수 있습니다. 플레이스(Config 등)에는 어느 경우에도 들어가지 않습니다.
- `login <토큰>` 은 로그와 입력 기록에 남지 않습니다.
- `login` 은 할 때마다 주의 사항을 보여주고, `privacy` / `terms` 를 읽고 동의한다는 뜻으로 `--agree` 를 붙여야 진행합니다.
- `login --agree`: `wally login` 과 같은 GitHub 기기 로그인입니다 (Wally 의 GitHub OAuth 앱, `read:user` 권한).
  나오는 주소(github.com/login/device)에서 코드를 입력하고 승인하면 됩니다.
- `login <토큰> --agree`: 직접 만든 토큰 (권한 없이 만들어도 됨). GitHub API 요청 한도만 늘어납니다 (시간당 60 -> 5000).
  Wally 서버는 Wally 앱으로 받은 토큰만 받기 때문에 업로드는 `login` 으로 해야 합니다.
- `publish`: Explorer 에서 선택한 것 (보통 패키지 ModuleScript) 을 Rojo 형식 파일 + `wally.toml` + `default.project.json` 으로 묶어 올립니다.
  - ModuleScript / Script / LocalScript -> `.luau`, Folder -> 폴더, StringValue -> `.txt`, 그 외 -> `.rbxm`
  - scope 는 GitHub 아이디 (또는 이미 가진 scope), 이름은 소문자
  - `--deps`: Config 의 dependencies / serverDependencies 중 Wally 패키지를 의존성으로 넣음
  - `--yes` 가 없으면 올릴 파일과 `wally.toml` 만 보여줍니다. **같은 버전은 다시 올릴 수 없고, 올린 것은 지울 수 없습니다.**

### 버튼
| 버튼 | 동작 |
|---|---|
| Add / Add to Server / Add to Selected | 입력한 패키지를 Config 의 shared / server / 선택한 폴더 목록에 추가 (설치는 Install All) |
| Remove | 입력한 별칭이나 패키지 삭제, 입력이 비어 있으면 Explorer 에서 선택한 패키지 삭제 |
| Install All | Config 대로 설치. Config 에 없는 것 (플러그인이 만든 것만) 은 지움 (`wally install` 과 비슷) |
| Prune | 안 쓰는 `_Index` 폴더 정리. Remove 할 때 자동으로 하므로 thunk 를 손으로 지웠을 때만 필요 |
| Import File | 파일 선택 창. Config 아래에 보관하고 Config 에 추가한 뒤 shared 경로에 설치 (다른 곳은 `import --selected` / `--to`) |
| Open Config | Config 스크립트 열기 |
| Set Shared Path / Set Server Path | Explorer 에서 선택한 폴더(없으면 입력한 경로)로 설정 |
| List / Help | 설치한 패키지 목록 / 명령어 도움말 |
| Logout / Publish | **로그인했을 때만 보임.** 로그아웃 / 입력창 내용으로 `publish` (예: `ro-bura/x@1.0.0`, 실제로 올리려면 `--yes` 까지) |

## 설정 (ServerStorage.PackageLoaderConfig)
직접 고칠 수 있는 ModuleScript 이고 Team Create 로 공유됩니다. 직접 고친 뒤에는 **Install All** 을 누릅니다.
```luau
return {
	shared = "ReplicatedStorage/Packages",
	server = "ServerScriptService/ServerPackages",

	dependencies = {
		Signal = "sleitnick/signal@^2",
		MyLib = script.Imported.MyLib,  -- 직접 가져온 것 (Import File)
	},
	serverDependencies = {},
	custom = {
		["ServerStorage/Libs"] = {
			Myrepo = "gh:me/myrepo@^1",
		},
	},
}
```
- `shared` / `server` 는 경로 문자열(`"ReplicatedStorage/Packages"`, `"game/ReplicatedStorage/Packages"`) 이나
  Instance (`game.ReplicatedStorage.Packages`) 둘 다 됩니다.
- 값은 스펙 문자열 대신 Instance 도 됩니다 (`MyLib = script.MyLib`). 설치할 때 복사하므로 원본은 Config 아래에 그대로 남습니다.
  ModuleScript 면 `_Index/custom_별칭` 에 복사하고 thunk 를 만들고, 그 외 (Folder 등) 는 설치 위치에 바로 복사합니다.
- `install` 은 설치 위치에서 Config 에 없는 것 중 플러그인이 만든 것 (thunk / 복사본) 만 지웁니다. 직접 넣은 것은 건드리지 않습니다.

처음 만들 때 맨 아래에 쓸 수 있는 항목 설명이 주석으로 들어갑니다.
Add / Remove / 경로 설정은 필요한 줄만 고치기 때문에 직접 단 주석과 순서가 그대로 남습니다.
테이블을 코드로 만드는 등 구조를 알아볼 수 없으면 아무것도 바꾸지 않고 오류를 보여줍니다.
이름에 `-` 가 있으면 Luau 문법상 `["vide-opinionated"] = "cayasde/vide-opinionated@0.4.3"` 처럼 적힙니다.

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

처음 사용할 때 Studio 가 HTTP 요청(api.wally.run, api.github.com, codeload.github.com, 로그인 시 github.com / raw.githubusercontent.com)과
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
| `src/Auth.luau` | GitHub 로그인 (기기 로그인 / 토큰), 토큰 저장 |
| `src/Publisher.luau` | Instance -> Wally 패키지 zip, 업로드 |
| `src/Sources/` | Wally, GitHub, File, manifest(wally.toml / pesde.toml) |
| `src/Util/` | Inflate(deflate/gzip), Zip(읽기/쓰기), Semver, Toml, Lexer, TypeExports, ConfigEditor, RojoValues(Rojo 속성 값), Vfs |

## 아직 안 되는 것
- pesde 레지스트리 패키지 (`name = "scope/name"` 형식 의존성), GitHub 외 Git 저장소
- `.rbxmx` (XML 모델) 는 `SerializationService` 가 읽을 수 있을 때만 됨
- zip64, 암호화된 zip

## 참고한 레퍼런스
- [zzlib.luau](https://github.com/xhayper/zzlib.luau) (WTFPL) - Inflate 구조
- [roblox-package-manager](https://github.com/McThor2/roblox-package-manager) (MIT) - Wally API 사용법, 파일 변환, 설정 저장 방식
- [pesde](https://github.com/pesde-pkg/pesde) (MIT) - thunk 의 타입 re-export 로직 (`src/linking/generator.rs`)
- [wally-package-types](https://github.com/JohnnyMorganz/wally-package-types) (MIT) - 타입 re-export 아이디어

## 마켓 배포 시 참고
- Roblox 커뮤니티 가이드라인은 외부 사이트 URL 을 링크 / 표시하는 것을 막고 있어서, 플러그인 안의 글(`PRIVACY`, `TERMS`, `THIRD_PARTY_NOTICES`, 오류 메시지)에는 외부 링크를 넣지 않습니다.
  예외는 기기 로그인에 꼭 필요한 GitHub 로그인 주소 하나입니다. 마켓 설명란에도 링크를 넣지 않습니다.

## 라이선스 / 개인정보 / 약관
[MIT](LICENSE). 개인정보 처리 안내는 [PRIVACY.md](PRIVACY.md), 이용 약관은 [TERMS.md](TERMS.md). 참고한 프로젝트의 고지는 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES) 에 있습니다.
네 파일 모두 빌드할 때 플러그인 안에 StringValue 로 들어가고 (`default.project.json` 의 `syncRules`),
`license` / `privacy` / `terms` 명령으로 볼 수 있습니다. `PackageLoaderConfig` 를 처음 만들 때 그 안에 `LICENSE` 모듈도 같이 만듭니다 (지워도 됨).
