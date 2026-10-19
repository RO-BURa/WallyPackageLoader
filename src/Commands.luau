-- 입력 해석과 명령 실행 (터미널처럼 직접 입력하는 것과 버튼이 같이 씀)

const Selection = game:GetService("Selection")

const Config = require(script.Parent.Config)
const Fmt = require(script.Parent.Fmt)
const Auth = require(script.Parent.Auth)
const Installer = require(script.Parent.Installer)
const Publisher = require(script.Parent.Publisher)
const LicenseText = require(script.Parent.LicenseText)
const Linker = require(script.Parent.Linker)
const Tree = require(script.Parent.Tree)

export type Context = {
	plugin: Plugin,
	-- 일반 글자 (라벨에 자동으로 색)
	log: (message: string) -> (),
	-- RichText 서식이 들어간 줄 (Fmt 사용)
	rich: (markup: string) -> (),
	clear: () -> (),
	-- 비밀번호 입력 받기 (입력창이 * 로 가려짐). 비우고 Enter 면 nil
	secret: (prompt: string) -> string?,
}

export type Flags = {
	server: boolean,
	selected: boolean,
	to: string?,
	-- publish 용 (미리보기 본 것을 올림 / 취소)
	yes: boolean?,
	no: boolean?,
	-- login 용 (주의 사항, privacy, terms 에 동의 / 토큰을 비밀번호로 암호화해서 저장)
	agree: boolean?,
	remember: boolean?,
	-- logout 용 (저장된 토큰은 남김)
	keep: boolean?,
	-- import 용 (파일 대신 Explorer 에서 선택한 것을 가져옴)
	select: boolean?,
	-- path 용 (기본 경로로 되돌림)
	reset: boolean?,
	-- 저장할 / 풀 비밀번호와 확인용 (--password <비밀번호> --r <비밀번호>)
	password: string?,
	confirm: string?,
}

const Commands = {}

type HelpEntry = {
	summary: string,
	usage: { string },
	args: { { string } }?,
	options: { { string } }?,
	examples: { string }?,
	notes: { string }?,
}

const COMMAND_ORDER = {
	"add",
	"remove",
	"install",
	"import",
	"path",
	"list",
	"tree",
	"prune",
	"config",
	"login",
	"logout",
	"whoami",
	"cancel",
	"publish",
	"clear",
	"license",
	"privacy",
	"terms",
	"help",
}

const LOCATION_OPTIONS = {
	{ "--server", "server 경로에" },
	{ "--selected", "Explorer 에서 선택한 폴더에" },
	{ "--to <경로>", "지정한 경로에 (예: ServerStorage/Libs)" },
}

const HELP: { [string]: HelpEntry } = {
	add = {
		summary = "Config 에 패키지 추가 (설치는 install)",
		usage = { "add [<별칭> =] <패키지> [옵션]", "<별칭> = <패키지>" },
		args = {
			{ "<별칭>", "thunk 이름. 없으면 원래 패키지 이름 (vide-opinionated)" },
			{ "<패키지>", "버전을 안 적으면 찾은 버전으로 고정 (@0.4.3)" },
			{ "", "sleitnick/signal@^2      Wally" },
			{ "", "gh:owner/repo@^1         GitHub 태그" },
			{ "", "gh:owner/repo#main       GitHub 브랜치 / 태그 / 커밋" },
			{ "", "pesde:scope/name@^1      pesde 레지스트리" },
		},
		options = LOCATION_OPTIONS,
		examples = {
			"add cayasde/vide-opinionated",
			"vide = cayasde/vide-opinionated@^0.4",
			"add gh:owner/repo#main --to ServerStorage/Libs",
			"install",
		},
	},
	remove = {
		summary = "패키지 삭제 (rm)",
		usage = { "remove <별칭 | 패키지>", "remove" },
		args = {
			{ "<별칭>", "Config 에 적힌 이름 (asdf)" },
			{ "<패키지>", "패키지 이름, 버전 무시 (ro-bura/signal)" },
			{ "(없음)", "Explorer 에서 선택한 패키지" },
		},
		examples = { "remove asdf", "rm ro-bura/signal" },
	},
	install = {
		summary = "Config 대로 설치 (없는 건 지우고 적힌 건 설치, wally install)",
		usage = { "install" },
	},
	import = {
		summary = "파일에서 가져오기 (.lua / .luau 여러 개, .zip). Config 아래에 보관하고 이름 = script.이름 으로 추가",
		usage = { "import [옵션]", "import --select [--server | --to <경로>]" },
		options = {
			LOCATION_OPTIONS[1],
			LOCATION_OPTIONS[2],
			LOCATION_OPTIONS[3],
			{ "--select", "파일 대신 Explorer 에서 선택한 것을 복제해서 가져옴 (원본은 그대로)" },
		},
	},
	path = {
		summary = "shared / server 경로 설정",
		usage = {
			"path shared <경로 | --selected>",
			"path server <경로 | --selected>",
			"path reset [shared | server]",
		},
		options = {
			{ "reset", "기본 경로로 되돌림 (shared: ReplicatedStorage/Packages, server: ServerScriptService/ServerPackages). 뒤에 아무것도 없으면 둘 다" },
		},
		examples = {
			"path shared ReplicatedStorage/Packages",
			"path server --selected",
			"path reset",
			"path reset server",
			"path shared --reset",
		},
		notes = { "경로만 바꿈. 이미 설치한 건 옮기지 않으니 install 로 다시 설치" },
	},
	list = {
		summary = "설치한 패키지 목록 (ls)",
		usage = { "list" },
	},
	tree = {
		summary = "의존성 트리",
		usage = { "tree", "tree --selected" },
		options = {
			{ "(없음)", "Config 에 적힌 패키지 기준. 설치된 건 _Index 를 보고, 안 된 건 서버에서 찾아서 그림" },
			{ "--selected", "Explorer 에서 선택한 것 기준: wally.toml (또는 그게 든 패키지), thunk, _Index 패키지, 패키지 폴더" },
		},
		notes = {
			"(위와 같음): 위에서 이미 펼친 패키지, (순환): 서로를 의존, (server): 서버 전용",
		},
	},
	prune = {
		summary = "안 쓰는 _Index 폴더 정리",
		usage = { "prune" },
	},
	config = {
		summary = "Config 스크립트 열기",
		usage = { "config" },
	},
	clear = {
		summary = "로그 지우기",
		usage = { "clear" },
	},
	login = {
		summary = "GitHub 로그인 (토큰은 플레이스에 절대 안 들어감)",
		usage = {
			"login --agree [--remember]",
			"login --agree --password <비밀번호> --r <비밀번호>",
			"login <토큰> --agree [--remember]",
			"login [--password <비밀번호>]",
		},
		args = {
			{ "(없음)", "기기 로그인: 나오는 주소에서 코드를 입력하고 승인. Wally 업로드 + GitHub 요청 한도 증가" },
			{ "<토큰>", "직접 만든 GitHub 토큰 (권한 없이 만들어도 됨). GitHub 요청 한도만 늘어나고 Wally 업로드는 안 됨" },
		},
		options = {
			{ "--agree", "주의 사항과 privacy / terms 를 읽고 동의함. 없으면 주의 사항만 보여주고 로그인 안 함" },
			{ "--remember", "로그인 후 비밀번호(10자 이상)를 두 번 입력받아 토큰을 암호화해 이 컴퓨터에 저장. 없으면 Studio 를 끄면 로그아웃" },
			{ "--password <비밀번호> --r <비밀번호>", "비밀번호를 바로 적음 (--r 은 확인용). 저장할 때는 --remember 없이도 됨. 로그에는 **** 로" },
		},
		notes = {
			"저장된 로그인이 있으면 login 은 새로 로그인하지 않고 저장된 것을 풂 (login --password <비밀번호>, 없으면 입력창에 * 로 가려서 받음)",
			"새로 로그인하려면 logout 후 login --agree",
			"비밀번호를 잊었으면 logout 후 다시 로그인",
		},
	},
	logout = {
		summary = "GitHub 로그아웃 (저장된 토큰도 삭제)",
		usage = { "logout [--keep]" },
		options = {
			{ "--keep", "이번 세션만 로그아웃하고 저장된 토큰은 남김 (다음에 login --password 로 다시 풂)" },
		},
	},
	cancel = {
		summary = "기다리는 중인 GitHub 로그인 취소",
		usage = { "cancel" },
	},
	whoami = {
		summary = "로그인한 GitHub 계정",
		usage = { "whoami" },
	},
	publish = {
		summary = "Explorer 에서 선택한 패키지를 Wally 에 업로드 (패키지 안의 wally.toml 사용)",
		usage = { "publish [--yes | --no]" },
		options = {
			{ "(없음)", "wally.toml 이 없으면 만들어서 열고, 있으면 올릴 내용을 미리보기" },
			{ "--yes", "방금 미리보기 한 것을 업로드 (login 필요). 같은 버전은 다시 못 올리고 올린 건 못 지움" },
			{ "--no", "미리보기 한 것을 취소" },
		},
		examples = { "publish", "publish --yes" },
		notes = {
			"wally.toml 은 패키지 안의 ModuleScript (업로드할 땐 빠지고 zip 의 wally.toml 이 됨)",
			"의존성은 [dependencies] 에 적고 코드에서 require(script.Parent.별칭)",
			"개발할 땐 패키지를 shared 경로 (Packages) 안에 두면 옆의 thunk 로 의존성이 바로 됨",
		},
	},
	privacy = {
		summary = "개인정보 처리 안내 (토큰을 어디에 저장하고 어디로 보내는지)",
		usage = { "privacy" },
	},
	terms = {
		summary = "이용 약관",
		usage = { "terms" },
	},
	license = {
		summary = "라이선스와 참고한 프로젝트 고지",
		usage = { "license" },
	},
	help = {
		summary = "도움말",
		usage = { "help", "help <명령어>" },
	},
}

const INDENT = "    "

const function section(context: Context, title: string)
	context.rich("")
	context.rich(Fmt.color("yellow", Fmt.bold(title .. ":")))
end

-- 이름이 ASCII 인 짧은 목록: 한 줄에 이름 + 설명
const function nameRows(context: Context, rows: { { string } }, width: number)
	for _, row in rows do
		context.rich(INDENT .. Fmt.color("green", Fmt.escape(Fmt.pad(row[1], width))) .. Fmt.escape(row[2]))
	end
end

-- 자세한 목록 (rojo --help 형식): 이름 줄 아래에 설명을 들여씀. 이름이 "" 면 앞 항목 설명이 이어짐
const function detailRows(context: Context, rows: { { string } })
	for index, row in rows do
		if row[1] ~= "" then
			if index > 1 then
				context.rich("")
			end
			context.rich(INDENT .. Fmt.color("green", Fmt.escape(row[1])))
		end
		context.rich(INDENT .. INDENT .. Fmt.escape(row[2]))
	end
end

const function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

-- 패키지 입력 해석
--   "asdf = ro-bura/signal", "ro-bura/signal as asdf", "ro-bura/signal", 'asdf = "ro-bura/signal",'
function Commands.parseSpec(text: string): (string, string?)
	const cleaned = trim((string.gsub(trim(text), ",$", "")))
	-- Config 에서 그대로 복사한 ["vide-opinionated"] = "..." 형식
	local alias, spec = string.match(cleaned, "^%[[\"'](.-)[\"']%]%s*=%s*(.+)$")
	if not alias then
		alias, spec = string.match(cleaned, "^([%a_][%w_%-]*)%s*=%s*(.+)$")
	end
	if not alias then
		spec, alias = string.match(cleaned, "^(.-)%s+as%s+([%a_][%w_%-]*)$")
	end
	local result = trim(spec or cleaned)
	result = string.match(result, "^\"(.*)\"$") or string.match(result, "^'(.*)'$") or result
	return result, alias
end

-- 버전, ref, 접두사를 뗀 패키지 이름 (소문자)
const function packageId(spec: string): string
	local id = string.lower(trim(spec))
	id = string.gsub(id, "^wally:", "")
	id = string.gsub(id, "^github:", "gh:")
	id = string.gsub(id, "[@#].*$", "")
	return id
end

-- 별칭이나 패키지 이름으로 Config 항목 찾기
function Commands.findEntries(query: string): { Config.Entry }
	const spec, alias = Commands.parseSpec(query)
	const matches = {}
	for _, entry in Config.entries() do
		local matched
		if alias then
			matched = entry.alias == alias
		elseif string.find(spec, "/", 1, true) then
			matched = entry.spec ~= nil and packageId(entry.spec) == packageId(spec)
		else
			matched = string.lower(entry.alias) == string.lower(spec)
		end
		if matched then
			table.insert(matches, entry)
		end
	end
	return matches
end

-- 단어 목록에서 --server / --selected / --to <경로> 를 떼어냄
const function takeFlags(words: { string }): ({ string }, Flags)
	const rest = {}
	const flags: Flags = { server = false, selected = false, to = nil }
	local i = 1
	while i <= #words do
		const word = words[i]
		if word == "--server" then
			flags.server = true
		elseif word == "--selected" then
			flags.selected = true
		elseif word == "--yes" then
			flags.yes = true
		elseif word == "--no" then
			flags.no = true
		elseif word == "--agree" then
			flags.agree = true
		elseif word == "--remember" then
			flags.remember = true
		elseif word == "--keep" then
			flags.keep = true
		elseif word == "--select" then
			flags.select = true
		elseif word == "--reset" then
			flags.reset = true
		elseif word == "--to" then
			flags.to = words[i + 1]
			if not flags.to then
				error("--to 뒤에 경로가 필요함", 0)
			end
			i += 1
		elseif word == "--password" or word == "--r" then
			const value = words[i + 1]
			if not value then
				error(`{word} 뒤에 비밀번호가 필요함`, 0)
			end
			if word == "--password" then
				flags.password = value
			else
				flags.confirm = value
			end
			i += 1
		else
			table.insert(rest, word)
		end
		i += 1
	end
	return rest, flags
end

const function selected(): Instance?
	return Selection:Get()[1]
end

-- 플래그에 맞는 설치 위치 (selectedFallback: 선택한 게 있으면 그걸 기본으로)
const function targetFor(flags: Flags, selectedFallback: boolean?): Instance
	if flags.to then
		return Config.resolvePath(flags.to, true) :: Instance
	elseif flags.selected then
		const target = selected()
		if not target then
			error("Explorer 에서 폴더를 선택해주세요", 0)
		end
		return target
	elseif flags.server then
		return Installer.serverRoot()
	elseif selectedFallback and selected() then
		return selected() :: Instance
	end
	return Installer.sharedRoot()
end

-- Config 에만 추가 (설치는 install)
-- 플래그에 맞는 설치 위치 경로 (폴더를 만들지 않음, add 용)
const function targetPathFor(flags: Flags): string
	if flags.to then
		const service = string.match(flags.to, "^[^/]+") or ""
		if not pcall(game.GetService, game, service) then
			error(`알 수 없는 서비스: {service}`, 0)
		end
		return flags.to
	elseif flags.selected then
		const target = selected()
		if not target then
			error("Explorer 에서 폴더를 선택해주세요", 0)
		end
		return Config.pathOf(target)
	elseif flags.server then
		return Config.getServerPath()
	end
	return Config.getSharedPath()
end

function Commands.add(text: string, flags: Flags, context: Context)
	-- 버튼을 누를 때 입력창에 "add ..." 를 그대로 써둔 경우
	const spec, alias = Commands.parseSpec((string.gsub(text, "^%s*[aA][dD][dD]%s+", "")))
	if spec == "" then
		error("패키지를 입력해주세요 (예: cayasde/vide-opinionated)", 0)
	end
	Installer.add(spec, alias, targetPathFor(flags), context.log)
end

function Commands.remove(rawText: string, context: Context)
	const text = string.gsub(rawText, "^%s*[rR][eE][mM][oO][vV][eE]%s+", "")
	if trim(text) == "" then
		const target = selected()
		if target and Linker.isManaged(target) and target.Parent then
			Installer.remove(target.Name, Config.pathOf(target.Parent), context.log)
			return
		end
		error("지울 별칭이나 패키지를 입력하거나 Explorer 에서 패키지를 선택해주세요", 0)
	end

	const matches = Commands.findEntries(text)
	if #matches == 0 then
		error(`Config 에 '{trim(text)}' 가 없음 (list 로 확인)`, 0)
	elseif #matches > 1 then
		const names = {}
		for _, entry in matches do
			table.insert(names, `{entry.alias} ({entry.location})`)
		end
		error(`여러 개가 맞음: {table.concat(names, ", ")}. 별칭으로 지정하거나 Explorer 에서 선택해주세요`, 0)
	end
	Installer.remove(matches[1].alias, matches[1].location, context.log)
end

function Commands.import(flags: Flags, context: Context, selectedFallback: boolean?)
	if flags.select then
		const target = selected()
		if not target then
			error("Explorer 에서 가져올 것을 선택해주세요", 0)
		end
		-- --select 일 때 --selected 는 의미가 겹쳐서 설치 위치는 --server / --to 만
		Installer.importInstance(target, {
			location = targetFor({ server = flags.server, selected = false, to = flags.to }),
			log = context.log,
		})
		return
	end
	Installer.importFiles({ location = targetFor(flags, selectedFallback), log = context.log })
end

-- 기본 경로로 되돌림 (which: "shared" / "server" / nil 이면 둘 다)
function Commands.resetPath(which: string?, context: Context)
	if which and which ~= "shared" and which ~= "server" then
		error("path reset [shared | server]", 0)
	end
	if not which or which == "shared" then
		Config.setSharedPath(Config.DEFAULT_SHARED)
		context.log(`shared 경로: {Config.DEFAULT_SHARED} (기본값)`)
	end
	if not which or which == "server" then
		Config.setServerPath(Config.DEFAULT_SERVER)
		context.log(`server 경로: {Config.DEFAULT_SERVER} (기본값)`)
	end
	context.log("경로만 바꿈. 이미 설치한 건 install 로 다시 설치해주세요")
end

function Commands.setPath(kind: string, value: string?, context: Context)
	local path = value and trim(value) or ""
	if path == "" or path == "--selected" then
		const target = selected()
		if not target then
			error("Explorer 에서 폴더를 선택하거나 경로를 입력해주세요", 0)
		end
		path = Config.pathOf(target)
	else
		Config.resolvePath(path, true)
	end

	if kind == "shared" then
		Config.setSharedPath(path)
	elseif kind == "server" then
		Config.setServerPath(path)
	else
		error("path shared <경로> 또는 path server <경로>", 0)
	end
	context.log(`{kind} 경로: {path}`)
end

-- 트리 출력
const function printTree(roots: { Tree.Node }, context: Context)
	if #roots == 0 then
		context.log("보여줄 의존성이 없음")
		return
	end
	for _, line in Tree.lines(roots) do
		local text = Fmt.color("dim", Fmt.escape(line.prefix)) .. Fmt.bold(Fmt.escape(line.alias))
		text ..= "  " .. Fmt.color("dim", Fmt.escape(line.label))
		if line.note then
			text ..= " " .. Fmt.color("yellow", Fmt.escape(line.note))
		end
		context.rich(text)
	end
end

-- Instance 를 기준으로 트리 루트들
const function treeFromInstance(target: Instance): { Tree.Node }
	const installed = Tree.installed()

	-- wally.toml (또는 그게 든 패키지)
	const manifestScript = if target.Name == Publisher.MANIFEST_NAME and target:IsA("ModuleScript")
		then target
		else Publisher.getManifest(target)
	if manifestScript then
		const data = Publisher.readManifest(manifestScript)
		const package = if type(data.package) == "table" then data.package else {}
		const label = `{tostring(package.name or "?")}@{tostring(package.version or "?")} (wally.toml)`
		const remote = Tree.remote(Installer.resolve)
		return {
			remote.manifest(
				(manifestScript.Parent :: Instance).Name,
				label,
				data.dependencies or {},
				data["server-dependencies"] or {}
			),
		}
	end

	if target:GetAttribute(Linker.LINK_ATTRIBUTE) then
		return { installed.thunk(target) }
	end
	if target:GetAttribute(Linker.ENTRY_ATTRIBUTE) then
		return { installed.entry(target) }
	end
	const parent = target.Parent
	if parent and parent:GetAttribute(Linker.ENTRY_ATTRIBUTE) then
		return { installed.entry(parent) }
	end

	-- 패키지 폴더: 안의 thunk 전부
	const roots = {}
	const thunks = {}
	for _, child in target:GetChildren() do
		if child:GetAttribute(Linker.LINK_ATTRIBUTE) then
			table.insert(thunks, child)
		end
	end
	table.sort(thunks, function(a, b)
		return string.lower(a.Name) < string.lower(b.Name)
	end)
	for _, thunk in thunks do
		table.insert(roots, installed.thunk(thunk))
	end
	if #roots == 0 then
		error(`{target.Name}: wally.toml, thunk, 패키지 폴더 중 하나를 선택해주세요`, 0)
	end
	return roots
end

function Commands.tree(flags: Flags, context: Context)
	if flags.selected then
		const target = selected()
		if not target then
			error("Explorer 에서 wally.toml, 패키지, 패키지 폴더 중 하나를 선택해주세요", 0)
		end
		printTree(treeFromInstance(target), context)
		return
	end

	-- Config 기준: 설치된 건 _Index, 안 된 건 서버에서
	const installed = Tree.installed()
	local remote = nil
	const groups: { [string]: { Tree.Node } } = {}
	const order: { string } = {}
	for _, entry in Config.entries() do
		const folder = Config.resolvePath(entry.location, false)
		const thunk = if folder then folder:FindFirstChild(entry.alias) else nil
		local node: Tree.Node
		if thunk and thunk:GetAttribute(Linker.LINK_ATTRIBUTE) then
			node = installed.thunk(thunk)
		elseif entry.spec then
			remote = remote or Tree.remote(Installer.resolve)
			node = remote.spec(entry.alias, entry.spec)
			node.note = (if node.note then node.note .. " " else "") .. "(설치 안 됨)"
		else
			node = { alias = entry.alias, label = "직접 넣은 것", note = "(설치 안 됨)", children = {} }
		end
		if not groups[entry.location] then
			groups[entry.location] = {}
			table.insert(order, entry.location)
		end
		table.insert(groups[entry.location], node)
	end
	if #order == 0 then
		context.log("Config 에 적힌 패키지가 없음")
		return
	end
	for _, location in order do
		section(context, location)
		printTree(groups[location], context)
	end
end

function Commands.list(context: Context)
	const entries = Config.entries()
	if #entries == 0 then
		context.log("설치한 패키지가 없음")
		return
	end
	for _, entry in entries do
		const folder = Config.resolvePath(entry.location, false)
		const installed = folder and folder:FindFirstChild(entry.alias)
		local valueText: string
		if entry.source then
			const ok, expression = pcall(Config.childExpression, entry.source)
			valueText = if ok then expression else entry.source:GetFullName()
		else
			valueText = entry.spec :: string
		end
		context.rich(
			Fmt.color("green", Fmt.bold(Fmt.escape(entry.alias)))
				.. " = "
				.. Fmt.escape(valueText)
				.. "  "
				.. Fmt.color("dim", `({Fmt.escape(entry.location)})`)
				.. (if installed then "" else "  " .. Fmt.color("yellow", "[설치 안 됨]"))
		)
	end
end

-- help: 전체 목록, help <명령어>: 자세히 (rojo --help 형식)
function Commands.help(context: Context, topic: string?)
	if topic and topic ~= "" then
		const name = if topic == "rm" then "remove" elseif topic == "ls" then "list" else string.lower(topic)
		const entry = HELP[name]
		if not entry then
			error(`알 수 없는 명령어: {topic} (help 로 목록 확인)`, 0)
		end

		context.rich(Fmt.color("green", Fmt.bold(name)))
		context.rich(Fmt.escape(entry.summary))
		section(context, "USAGE")
		for _, usage in entry.usage do
			context.rich(INDENT .. Fmt.escape(usage))
		end
		if entry.args then
			section(context, "ARGS")
			detailRows(context, entry.args)
		end
		if entry.options then
			section(context, "OPTIONS")
			detailRows(context, entry.options)
		end
		if entry.examples then
			section(context, "EXAMPLES")
			for _, example in entry.examples do
				context.rich(INDENT .. Fmt.color("dim", "> ") .. Fmt.escape(example))
			end
		end
		if entry.notes then
			section(context, "NOTES")
			for _, note in entry.notes do
				context.rich(INDENT .. Fmt.escape(note))
			end
		end
		return
	end

	context.rich(Fmt.bold("PackageLoader"))
	context.rich("Wally / GitHub / 파일에서 패키지를 바로 불러옴")
	section(context, "USAGE")
	context.rich(INDENT .. Fmt.escape("<명령어> [인자] [옵션]"))
	context.rich(INDENT .. Fmt.escape("<별칭> = <패키지>") .. "     " .. Fmt.color("dim", "명령어 없이 치면 add"))
	context.rich(INDENT .. Fmt.color("dim", "add 로 Config 에 추가한 뒤 install 로 설치"))
	section(context, "COMMANDS")
	const rows = {}
	for _, name in COMMAND_ORDER do
		table.insert(rows, { name, HELP[name].summary })
	end
	nameRows(context, rows, 10)
	context.rich("")
	context.rich(Fmt.color("dim", Fmt.escape("help <명령어> 로 자세히")))
end

function Commands.openConfig(context: Context)
	context.plugin:OpenScript(Config.getModule())
end

-- 로그인할 때마다 보여주는 주의 사항
const LOGIN_WARNINGS = {
	"경고: 토큰은 기본적으로 Studio 를 끌 때까지만 기억하고, 플레이스(Config 등)에는 절대 안 들어감",
	"경고: --remember / --password 를 붙이면 비밀번호로 암호화해서 이 컴퓨터의 Studio 설정에 저장 (다음에는 login --password). 비밀번호가 짧거나 흔하면 풀릴 수 있음",
	"경고: 공용 PC 라면 다 쓴 뒤 logout 해주세요",
	"경고: login <토큰> 은 권한(scope) 없이 만든 토큰을 쓰는 걸 추천",
	"경고: Wally 업로드(publish --yes)는 되돌릴 수 없음 (같은 버전 재업로드, 삭제 불가)",
}

const CANCELLED = "저장 안 함, Studio 를 끄면 로그아웃"

-- 저장할 비밀번호: --password / --r 로 적었으면 미리 검사, 아니면 nil (로그인 뒤에 입력창으로 받음)
const function checkPasswordFlags(flags: Flags): string?
	if not flags.password then
		if flags.confirm then
			error("--r 은 --password 와 같이 써야 함", 0)
		end
		return nil
	end
	if #flags.password < Auth.MIN_PASSWORD_LENGTH then
		error(`비밀번호는 {Auth.MIN_PASSWORD_LENGTH}자 이상`, 0)
	end
	if not flags.confirm then
		error("확인용으로 --r <비밀번호> 도 적어주세요", 0)
	end
	if flags.confirm ~= flags.password then
		error("--password 와 --r 의 비밀번호가 다름", 0)
	end
	return flags.password
end

-- 입력창으로 비밀번호를 두 번 받음. 취소하면 nil
const function askNewPassword(context: Context): string?
	while true do
		const password = context.secret(`저장할 비밀번호 ({Auth.MIN_PASSWORD_LENGTH}자 이상, 비우고 Enter 면 저장 안 함)`)
		if not password then
			return nil
		end
		if #password < Auth.MIN_PASSWORD_LENGTH then
			context.log(`경고: 비밀번호는 {Auth.MIN_PASSWORD_LENGTH}자 이상`)
		else
			const again = context.secret("비밀번호 한 번 더")
			if not again then
				return nil
			end
			if again == password then
				return password
			end
			context.log("경고: 두 비밀번호가 다름. 다시 입력해주세요")
		end
	end
end

-- 저장된 로그인 풀기
const function unlockSaved(flags: Flags, context: Context)
	const password = flags.password or context.secret("저장된 로그인의 비밀번호 (비우고 Enter 면 취소)")
	if not password then
		context.log("취소함")
		return
	end
	context.log("확인 중: 저장된 로그인을 푸는 중...")
	const seconds = Auth.unlock(password)
	context.log(`완료: {Auth.whoami()} 로 로그인 (저장된 로그인, {string.format("%.1f", seconds)}초)`)
end

-- 로그인할 때마다 주의 사항을 보여주고, --agree 로 동의해야 진행
-- 저장된 로그인이 있으면 새로 로그인하지 않고 그걸 풂
function Commands.login(token: string?, flags: Flags, context: Context)
	if not token and Auth.hasSaved() then
		if Auth.getToken() then
			context.log("이미 로그인됨 (whoami). 새로 로그인하려면 logout 후 login --agree")
			return
		end
		unlockSaved(flags, context)
		return
	end

	for _, warning in LOGIN_WARNINGS do
		context.log(warning)
	end
	if not flags.agree then
		context.log("경고: 아직 로그인 안 함. 위 내용과 privacy / terms 를 모두 읽고 동의하면 --agree 를 붙여서 다시 실행해주세요")
		context.log(if token then "예: login <토큰> --agree" else "예: login --agree")
		return
	end
	-- 비밀번호 오타는 로그인 전에 먼저 걸러냄
	const presetPassword = checkPasswordFlags(flags)

	local user: string
	local kindText: string
	if token then
		Auth.setToken(token, "token")
		const ok, result = pcall(Auth.whoami)
		if not ok then
			Auth.clear()
			error(`토큰이 맞지 않음: {result}`, 0)
		end
		user = result
		kindText = "토큰, GitHub 요청 한도만 늘어남"
	else
		Auth.deviceLogin(context.log)
		user = Auth.whoami()
		kindText = "기기 로그인"
	end

	local saved = "Studio 를 끄면 로그아웃"
	if presetPassword or flags.remember then
		const password = presetPassword or askNewPassword(context)
		if password then
			context.log("확인 중: 암호화하는 중...")
			const seconds = Auth.save(password)
			saved = `비밀번호로 암호화해서 이 컴퓨터에 저장, {string.format("%.1f", seconds)}초. 다음에는 login --password`
		else
			saved = CANCELLED
		end
	end
	context.log(`완료: {user} 로 로그인 ({kindText}, {saved})`)
end

-- publish 미리보기 한 것 (publish --yes 가 올릴 것)
local pendingPublish: Publisher.Prepared? = nil

const function previewPublish(prepared: Publisher.Prepared, context: Context)
	section(context, "FILES")
	for _, path in prepared.paths do
		context.rich(INDENT .. Fmt.escape(path) .. "  " .. Fmt.color("dim", `({#prepared.files[path]} bytes)`))
	end
	section(context, "wally.toml")
	for _, line in string.split(prepared.manifest, "\n") do
		if line ~= "" then
			context.rich(INDENT .. Fmt.escape(line))
		end
	end
	context.rich("")
	pendingPublish = prepared
	context.log(`경고: 아직 안 올림. {prepared.name}@{prepared.version} 을 올리려면 publish --yes, 취소는 publish --no`)
end

function Commands.publish(flags: Flags, context: Context)
	if flags.no then
		context.log(if pendingPublish then "완료: publish 취소" else "취소할 publish 가 없음")
		pendingPublish = nil
		return
	end

	if flags.yes then
		const pending = pendingPublish
		if not pending then
			error("먼저 publish 로 미리보기를 확인해주세요", 0)
		end
		-- 미리보기 뒤에 바뀌었으면 다시 확인
		const prepared = Publisher.prepare(pending.source, context.log)
		if prepared.zip ~= pending.zip then
			context.log("경고: 미리보기 뒤에 패키지나 wally.toml 이 바뀜. 다시 확인해주세요")
			previewPublish(prepared, context)
			return
		end
		context.log(`확인 중: {prepared.name}@{prepared.version} 업로드`)
		Publisher.upload(prepared)
		pendingPublish = nil
		context.log(`완료: {prepared.name}@{prepared.version} 업로드`)
		return
	end

	const target = selected()
	if not target then
		error("Explorer 에서 올릴 패키지를 선택해주세요 (보통 패키지 ModuleScript)", 0)
	end
	const source = Publisher.findSource(target)
	if not Publisher.getManifest(source) then
		const login = if Auth.getToken() then select(2, pcall(Auth.whoami)) else nil
		const manifest = Publisher.createManifest(source, if type(login) == "string" then login else nil)
		context.plugin:OpenScript(manifest)
		context.log(`완료: {source.Name} 안에 {Publisher.MANIFEST_NAME} 을 만듦. name / version 등을 채운 뒤 다시 publish`)
		return
	end
	previewPublish(Publisher.prepare(source, context.log), context)
end

-- 한 줄 실행. 첫 단어가 명령어가 아니면 add 로 처리
function Commands.run(line: string, context: Context)
	const text = trim(line)
	if text == "" then
		return
	end

	const words = string.split(text, " ")
	const filtered = {}
	for _, word in words do
		if word ~= "" then
			table.insert(filtered, word)
		end
	end

	-- "list = foo/list" 처럼 별칭이 명령어와 같아도 = 가 있으면 add
	const isAssignment = filtered[2] == "=" or string.find(filtered[1], "=", 1, true) ~= nil
	const command = if isAssignment then "" else string.lower(filtered[1])
	const args, flags = takeFlags(table.move(filtered, 2, #filtered, 1, {}))
	const argText = table.concat(args, " ")

	if command == "add" then
		Commands.add(argText, flags, context)
	elseif command == "remove" or command == "rm" then
		Commands.remove(argText, context)
	elseif command == "install" then
		Installer.installAll(context.log)
	elseif command == "import" then
		Commands.import(flags, context)
	elseif command == "path" then
		const first = string.lower(args[1] or "")
		if first == "reset" then
			Commands.resetPath(if args[2] then string.lower(args[2]) else nil, context)
		elseif flags.reset then
			Commands.resetPath(if first ~= "" then first else nil, context)
		else
			Commands.setPath(first, if flags.selected then "--selected" else args[2], context)
		end
	elseif command == "tree" then
		Commands.tree(flags, context)
	elseif command == "list" or command == "ls" then
		Commands.list(context)
	elseif command == "prune" then
		Installer.prune(context.log)
		context.log("정리 완료")
	elseif command == "config" then
		Commands.openConfig(context)
	elseif command == "clear" then
		context.clear()
	elseif command == "login" then
		Commands.login(args[1], flags, context)
	elseif command == "logout" then
		if flags.keep then
			Auth.clear(true)
			context.log(
				if Auth.hasSaved()
					then "완료: 로그아웃 (저장된 토큰은 남김, login --password 로 다시 풂)"
					else "완료: 로그아웃 (저장된 토큰 없음)"
			)
		else
			Auth.clear()
			context.log("완료: 로그아웃 (저장된 토큰도 삭제)")
		end
	elseif command == "cancel" then
		if Auth.cancelLogin() then
			context.log("취소 요청함. 곧 멈춤")
		else
			context.log("취소할 작업이 없음")
		end
	elseif command == "whoami" then
		context.log(
			`로그인: {Auth.whoami()} ({if Auth.kind() == "device" then "기기 로그인" else "토큰"}, {if Auth.isRemembered() then "암호화해서 이 컴퓨터에 저장됨" else "Studio 를 끄면 로그아웃"})`
		)
	elseif command == "publish" then
		Commands.publish(flags, context)
	elseif command == "privacy" then
		context.rich(Fmt.escape(LicenseText.privacy()))
	elseif command == "terms" then
		context.rich(Fmt.escape(LicenseText.terms()))
	elseif command == "license" then
		context.rich(Fmt.escape(LicenseText.text()))
	elseif command == "help" or command == "?" then
		Commands.help(context, args[1])
	else
		const addArgs, addFlags = takeFlags(filtered)
		Commands.add(table.concat(addArgs, " "), addFlags, context)
	end
end

return Commands
