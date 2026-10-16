-- 소스들이 공통으로 돌려주는 패키지 정보

const Vfs = require(script.Parent.Parent.Util.Vfs)

export type Realm = "shared" | "server"

export type Package = {
	source: "wally" | "github" | "file",
	scope: string,
	name: string,
	version: string,
	realm: Realm,
	-- 별칭 -> 의존성 스펙 ("scope/name@range" 또는 "gh:owner/repo@range")
	dependencies: { [string]: string },
	serverDependencies: { [string]: string },
	-- 패키지 진입 파일 (pesde.toml 의 target.lib 등). 없으면 Builder 기본 규칙
	entryPath: string?,
	fetch: () -> Vfs.Vfs,
}

-- wally.toml / pesde.toml 에서 읽은 정보
export type Manifest = {
	scope: string?,
	name: string?,
	version: string?,
	realm: Realm,
	dependencies: { [string]: string },
	serverDependencies: { [string]: string },
	entryPath: string?,
}

return {}
