-- 메모리 위의 가상 파일 시스템 (zip 등에서 읽은 파일들)

export type Vfs = {
	files: { [string]: string },

	read: (self: Vfs, path: string) -> string?,
	isFile: (self: Vfs, path: string) -> boolean,
	isDir: (self: Vfs, path: string) -> boolean,
	list: (self: Vfs, dir: string) -> ({ string }, { string }),
	sub: (self: Vfs, dir: string) -> Vfs,
	stripSingleRoot: (self: Vfs) -> Vfs,
}

const Vfs = {}
Vfs.__index = Vfs

-- 경로 정규화: "\" -> "/", "./" 제거, 앞뒤 "/" 제거
const function normalize(path: string): string
	local p = string.gsub(path, "\\", "/")
	p = string.gsub(p, "/%./", "/")
	p = string.gsub(p, "^%./", "")
	p = string.gsub(p, "/+", "/")
	p = string.gsub(p, "^/", "")
	p = string.gsub(p, "/$", "")
	if p == "." then
		return ""
	end
	return p
end
Vfs.normalize = normalize

function Vfs.new(files: { [string]: string }): Vfs
	const normalized = {}
	for path, content in files do
		normalized[normalize(path)] = content
	end
	return setmetatable({ files = normalized }, Vfs) :: any
end

const function join(dir: string, name: string): string
	return if dir == "" then name else `{dir}/{name}`
end
Vfs.join = join

function Vfs.read(self: Vfs, path: string): string?
	return self.files[normalize(path)]
end

function Vfs.isFile(self: Vfs, path: string): boolean
	return self.files[normalize(path)] ~= nil
end

function Vfs.isDir(self: Vfs, path: string): boolean
	const prefix = normalize(path)
	if prefix == "" then
		return next(self.files) ~= nil
	end
	for filePath in self.files do
		if string.sub(filePath, 1, #prefix + 1) == prefix .. "/" then
			return true
		end
	end
	return false
end

-- 반환: 하위 파일 이름 목록, 하위 폴더 이름 목록 (정렬됨)
function Vfs.list(self: Vfs, dir: string): ({ string }, { string })
	const prefix = normalize(dir)
	const prefixLen = if prefix == "" then 0 else #prefix + 1
	const fileSet, dirSet = {}, {}

	for filePath in self.files do
		if prefix == "" or string.sub(filePath, 1, prefixLen) == prefix .. "/" then
			const rest = string.sub(filePath, prefixLen + 1)
			const slash = string.find(rest, "/", 1, true)
			if slash then
				dirSet[string.sub(rest, 1, slash - 1)] = true
			else
				fileSet[rest] = true
			end
		end
	end

	const fileNames, dirNames = {}, {}
	for name in fileSet do
		table.insert(fileNames, name)
	end
	for name in dirSet do
		table.insert(dirNames, name)
	end
	table.sort(fileNames)
	table.sort(dirNames)
	return fileNames, dirNames
end

-- dir 을 루트로 하는 새 Vfs
function Vfs.sub(self: Vfs, dir: string): Vfs
	const prefix = normalize(dir)
	if prefix == "" then
		return self
	end
	const files = {}
	for filePath, content in self.files do
		if string.sub(filePath, 1, #prefix + 1) == prefix .. "/" then
			files[string.sub(filePath, #prefix + 2)] = content
		end
	end
	return Vfs.new(files)
end

-- GitHub zipball 처럼 최상위에 폴더 하나만 있으면 그 안으로 들어감
function Vfs.stripSingleRoot(self: Vfs): Vfs
	const fileNames, dirNames = self:list("")
	if #fileNames == 0 and #dirNames == 1 then
		return self:sub(dirNames[1])
	end
	return self
end

return Vfs
