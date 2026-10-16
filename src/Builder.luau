-- 가상 파일(Vfs) -> Roblox Instance 변환 (Rojo 규칙)
-- 참고: roblox-package-manager 의 FileConverter (MIT), Rojo 동기화 규칙

const HttpService = game:GetService("HttpService")

const Vfs = require(script.Parent.Util.Vfs)
const Toml = require(script.Parent.Util.Toml)

type Vfs = Vfs.Vfs

const Builder = {}

const SCRIPT_EXTENSIONS = { ".luau", ".lua" }

-- 이름이 Lua 식별자로 쓸 수 있으면 그대로, 아니면 ["..."] 로 감싸기
const function isIdentifier(name: string): boolean
	return string.match(name, "^[%a_][%w_]*$") ~= nil
end

-- JSON/TOML 값 -> Luau 테이블 리터럴 소스
const function toLuau(value: any, indent: string): string
	const kind = typeof(value)
	if kind == "string" then
		return string.format("%q", value)
	elseif kind == "number" or kind == "boolean" then
		return tostring(value)
	elseif kind == "table" then
		const inner = indent .. "\t"
		const parts = {}
		if #value > 0 or next(value) == nil then
			for _, item in ipairs(value) do
				table.insert(parts, inner .. toLuau(item, inner))
			end
		else
			const keys = {}
			for key in value do
				table.insert(keys, tostring(key))
			end
			table.sort(keys)
			for _, key in keys do
				const keyText = if isIdentifier(key) then key else `[{string.format("%q", key)}]`
				table.insert(parts, `{inner}{keyText} = {toLuau(value[key], inner)}`)
			end
		end
		if #parts == 0 then
			return "{}"
		end
		return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. indent .. "}"
	end
	return "nil"
end
Builder.toLuau = toLuau

const function newScript(className: string, name: string, source: string): Instance
	const instance = Instance.new(className)
	instance.Name = name
	;(instance :: any).Source = source
	return instance
end

-- "foo.server.luau" -> ("Script", "foo") 처럼 파일 이름에서 종류를 판단
const function classifyScript(fileName: string): (string?, string?)
	for _, ext in SCRIPT_EXTENSIONS do
		if string.sub(fileName, -#ext) == ext then
			const stem = string.sub(fileName, 1, -#ext - 1)
			if string.sub(stem, -7) == ".server" then
				return "Script", string.sub(stem, 1, -8)
			elseif string.sub(stem, -7) == ".client" then
				return "LocalScript", string.sub(stem, 1, -8)
			end
			return "ModuleScript", stem
		end
	end
	return nil, nil
end
Builder.classifyScript = classifyScript

const function shouldSkip(fileName: string): boolean
	return string.sub(fileName, 1, 1) == "."
		or string.sub(fileName, -10) == ".meta.json"
		or string.sub(fileName, -13) == ".project.json"
end

local buildDir: (vfs: Vfs, dir: string, name: string, ignoreProject: boolean?) -> Instance?
local buildProjectFile: (vfs: Vfs, path: string) -> Instance?

const function buildFile(vfs: Vfs, path: string, fileName: string): Instance?
	const content = vfs:read(path) :: string

	const className, scriptName = classifyScript(fileName)
	if className then
		return newScript(className, scriptName :: string, content)
	end

	if string.sub(fileName, -5) == ".json" then
		const ok, decoded = pcall(HttpService.JSONDecode, HttpService, content)
		if not ok then
			warn(`[PackageLoader] JSON 을 읽을 수 없어 건너뜀: {path}`)
			return nil
		end
		return newScript("ModuleScript", string.sub(fileName, 1, -6), "return " .. toLuau(decoded, "") .. "\n")
	elseif string.sub(fileName, -5) == ".toml" then
		const ok, decoded = pcall(Toml.decode, content)
		if not ok then
			warn(`[PackageLoader] TOML 을 읽을 수 없어 건너뜀: {path}`)
			return nil
		end
		return newScript("ModuleScript", string.sub(fileName, 1, -6), "return " .. toLuau(decoded, "") .. "\n")
	elseif string.sub(fileName, -4) == ".txt" then
		const value = Instance.new("StringValue")
		value.Name = string.sub(fileName, 1, -5)
		value.Value = content
		return value
	end

	-- .rbxm / .rbxmx / .model.json 등은 아직 지원하지 않음
	return nil
end

buildDir = function(vfs: Vfs, dir: string, name: string, ignoreProject: boolean?): Instance?
	-- 폴더 안에 default.project.json 이 있으면 그 프로젝트를 따름
	const projectPath = Vfs.join(dir, "default.project.json")
	if not ignoreProject and vfs:isFile(projectPath) then
		const instance = buildProjectFile(vfs, projectPath)
		if instance then
			instance.Name = name
		end
		return instance
	end

	const fileNames, dirNames = vfs:list(dir)

	-- init 스크립트가 있으면 폴더 자체가 그 스크립트가 됨
	local container: Instance? = nil
	local initFile: string? = nil
	for _, fileName in fileNames do
		const className, stem = classifyScript(fileName)
		if className and stem == "init" then
			container = newScript(className, name, vfs:read(Vfs.join(dir, fileName)) :: string)
			initFile = fileName
			break
		end
	end
	if not container then
		const folder = Instance.new("Folder")
		folder.Name = name
		container = folder
	end

	for _, fileName in fileNames do
		if fileName ~= initFile and not shouldSkip(fileName) then
			const child = buildFile(vfs, Vfs.join(dir, fileName), fileName)
			if child then
				child.Parent = container
			end
		end
	end
	for _, dirName in dirNames do
		if string.sub(dirName, 1, 1) ~= "." then
			const child = buildDir(vfs, Vfs.join(dir, dirName), dirName)
			if child then
				child.Parent = container
			end
		end
	end

	return container
end

-- 경로가 파일이든 폴더든 Instance 로
-- fromProject: 프로젝트 파일의 $path 에서 왔으면 같은 프로젝트를 다시 읽지 않도록 함
function Builder.buildPath(vfs: Vfs, path: string, name: string?, fromProject: boolean?): Instance?
	const normalized = Vfs.normalize(path)
	if vfs:isFile(normalized) then
		const fileName = string.match(normalized, "[^/]+$") :: string
		if string.sub(fileName, -13) == ".project.json" then
			return buildProjectFile(vfs, normalized)
		end
		const instance = buildFile(vfs, normalized, fileName)
		if instance and name then
			instance.Name = name
		end
		return instance
	elseif vfs:isDir(normalized) then
		return buildDir(vfs, normalized, name or (string.match(normalized, "[^/]+$") or "Package"), fromProject)
	end
	return nil
end

-- 상대 경로 결합 ("src/../lib" 같은 것도 처리)
const function resolveRelative(baseDir: string, relative: string): string
	const parts = if baseDir == "" then {} else string.split(baseDir, "/")
	for _, part in string.split(Vfs.normalize(relative), "/") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." and part ~= "" then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

const function buildProjectNode(vfs: Vfs, baseDir: string, node: { [string]: any }, name: string): Instance?
	local instance: Instance? = nil

	if type(node["$path"]) == "string" then
		instance = Builder.buildPath(vfs, resolveRelative(baseDir, node["$path"]), name, true)
		if not instance then
			warn(`[PackageLoader] 프로젝트 경로를 찾을 수 없음: {node["$path"]}`)
		end
	end

	if not instance then
		const className = if type(node["$className"]) == "string" then node["$className"] else "Folder"
		const ok, created = pcall(Instance.new, className)
		if not ok then
			warn(`[PackageLoader] 만들 수 없는 클래스: {className}`)
			return nil
		end
		instance = created
	end

	const result = instance :: Instance
	result.Name = name

	for childName, childNode in node do
		if string.sub(childName, 1, 1) ~= "$" and type(childNode) == "table" then
			const child = buildProjectNode(vfs, baseDir, childNode, childName)
			if child then
				child.Parent = result
			end
		end
	end

	return result
end

buildProjectFile = function(vfs: Vfs, path: string): Instance?
	const ok, project = pcall(HttpService.JSONDecode, HttpService, vfs:read(path) :: string)
	if not ok or type(project) ~= "table" or type(project.tree) ~= "table" then
		warn(`[PackageLoader] 잘못된 프로젝트 파일: {path}`)
		return nil
	end
	const baseDir = string.match(path, "^(.*)/[^/]+$") or ""
	return buildProjectNode(vfs, baseDir, project.tree, project.name or "Package")
end

-- 패키지 하나를 Instance 로 만듦
-- 우선순위: entryPath(pesde target.lib) -> default.project.json -> 루트 init 스크립트 -> src/ -> lib/ -> 루트 전체
function Builder.buildPackage(vfs: Vfs, name: string, entryPath: string?): Instance?
	if entryPath and vfs:isFile(entryPath) then
		const normalized = Vfs.normalize(entryPath)
		const _, stem = classifyScript(string.match(normalized, "[^/]+$") :: string)
		if stem == "init" then
			-- init 파일이면 그 폴더 전체가 패키지
			return buildDir(vfs, string.match(normalized, "^(.*)/[^/]+$") or "", name, true)
		end
		return Builder.buildPath(vfs, normalized, name)
	end

	if vfs:isFile("default.project.json") then
		const instance = buildProjectFile(vfs, "default.project.json")
		if instance then
			instance.Name = name
		end
		return instance
	end

	const fileNames = vfs:list("")
	for _, fileName in fileNames do
		const className, stem = classifyScript(fileName)
		if className and stem == "init" then
			return buildDir(vfs, "", name)
		end
	end

	for _, candidate in { "src", "lib" } do
		if vfs:isDir(candidate) then
			return buildDir(vfs, candidate, name)
		end
	end

	return buildDir(vfs, "", name)
end

return Builder
