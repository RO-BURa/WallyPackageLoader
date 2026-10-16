-- 입력 해석과 명령 실행 (터미널처럼 직접 입력하는 것과 버튼이 같이 씀)

const Selection = game:GetService("Selection")

const Config = require(script.Parent.Config)
const Fmt = require(script.Parent.Fmt)
const Installer = require(script.Parent.Installer)
const Linker = require(script.Parent.Linker)

export type Context = {
	plugin: Plugin,
	-- 일반 글자 (라벨에 자동으로 색)
	log: (message: string) -> (),
	-- RichText 서식이 들어간 줄 (Fmt 사용)
	rich: (markup: string) -> (),
	clear: () -> (),
}

export type Flags = {
	server: boolean,
	selected: boolean,
	to: string?,
}

const Commands = {}

type HelpEntry = {
	summary: string,
	usage: { string },
	args: { { string } }?,
	options: { { string } }?,
	examples: { string }?,
}

const COMMAND_ORDER = { "add", "remove", "install", "import", "path", "list", "prune", "config", "clear", "help" }

const LOCATION_OPTIONS = {
	{ "--server", "server 경로에" },
	{ "--selected", "Explorer 에서 선택한 폴더에" },
	{ "--to <경로>", "지정한 경로에 (예: ServerStorage/Libs)" },
}

const HELP: { [string]: HelpEntry } = {
	add = {
		summary = "패키지 설치",
		usage = { "add [<별칭> =] <패키지> [옵션]", "<별칭> = <패키지>" },
		args = {
			{ "<별칭>", "thunk 이름. 없으면 패키지 이름 (signal -> Signal)" },
			{ "<패키지>", "sleitnick/signal@^2      Wally" },
			{ "", "gh:owner/repo@^1         GitHub 태그" },
			{ "", "gh:owner/repo#main       GitHub 브랜치 / 태그 / 커밋" },
		},
		options = LOCATION_OPTIONS,
		examples = { "add ro-bura/signal", "asdf = ro-bura/signal@^1", "add gh:owner/repo#main --to ServerStorage/Libs" },
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
		summary = "Config 에 적힌 패키지 전체 설치",
		usage = { "install" },
	},
	import = {
		summary = "파일에서 가져오기 (.lua / .luau 여러 개, .zip)",
		usage = { "import [옵션]" },
		options = LOCATION_OPTIONS,
	},
	path = {
		summary = "shared / server 경로 설정",
		usage = { "path shared <경로 | --selected>", "path server <경로 | --selected>" },
		examples = { "path shared ReplicatedStorage/Packages", "path server --selected" },
	},
	list = {
		summary = "설치한 패키지 목록 (ls)",
		usage = { "list" },
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
	local alias, spec = string.match(cleaned, "^([%a_][%w_]*)%s*=%s*(.+)$")
	if not alias then
		spec, alias = string.match(cleaned, "^(.-)%s+as%s+([%a_][%w_]*)$")
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
			matched = packageId(entry.spec) == packageId(spec)
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
		elseif word == "--to" then
			flags.to = words[i + 1]
			if not flags.to then
				error("--to 뒤에 경로가 필요함", 0)
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

function Commands.add(text: string, flags: Flags, context: Context)
	const spec, alias = Commands.parseSpec(text)
	if spec == "" then
		error("패키지를 입력해주세요 (예: asdf = ro-bura/signal)", 0)
	end
	Installer.install(spec, { alias = alias, location = targetFor(flags), log = context.log })
end

function Commands.remove(text: string, context: Context)
	if trim(text) == "" then
		const target = selected()
		if target and target:GetAttribute(Linker.LINK_ATTRIBUTE) and target.Parent then
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
	Installer.importFiles({ location = targetFor(flags, selectedFallback), log = context.log })
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

function Commands.list(context: Context)
	const entries = Config.entries()
	if #entries == 0 then
		context.log("설치한 패키지가 없음")
		return
	end
	for _, entry in entries do
		const folder = Config.resolvePath(entry.location, false)
		const installed = folder and folder:FindFirstChild(entry.alias)
		context.rich(
			Fmt.color("green", Fmt.bold(Fmt.escape(entry.alias)))
				.. " = "
				.. Fmt.escape(entry.spec)
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
		return
	end

	context.rich(Fmt.bold("PackageLoader"))
	context.rich("Wally / GitHub / 파일에서 패키지를 바로 불러옴")
	section(context, "USAGE")
	context.rich(INDENT .. Fmt.escape("<명령어> [인자] [옵션]"))
	context.rich(INDENT .. Fmt.escape("<별칭> = <패키지>") .. "     " .. Fmt.color("dim", "명령어 없이 치면 add"))
	section(context, "COMMANDS")
	const rows = {}
	for _, name in COMMAND_ORDER do
		table.insert(rows, { name, HELP[name].summary })
	end
	nameRows(context, rows, 10)
	context.rich("")
	context.rich(Fmt.color("dim", Fmt.escape("help <명령어> 로 자세히, ↑ / ↓ 로 이전 명령")))
end

function Commands.openConfig(context: Context)
	context.plugin:OpenScript(Config.getModule())
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

	const command = string.lower(filtered[1])
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
		Commands.setPath(string.lower(args[1] or ""), if flags.selected then "--selected" else args[2], context)
	elseif command == "list" or command == "ls" then
		Commands.list(context)
	elseif command == "prune" then
		Installer.prune(context.log)
		context.log("정리 완료")
	elseif command == "config" then
		Commands.openConfig(context)
	elseif command == "clear" then
		context.clear()
	elseif command == "help" or command == "?" then
		Commands.help(context, args[1])
	else
		const addArgs, addFlags = takeFlags(filtered)
		Commands.add(table.concat(addArgs, " "), addFlags, context)
	end
end

return Commands
