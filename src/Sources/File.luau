-- 로컬 파일에서 가져오기 (.lua / .luau / .zip)

const StudioService = game:GetService("StudioService")

const L = require(script.Parent.Parent.Locale).L
const Vfs = require(script.Parent.Parent.Util.Vfs)
const Zip = require(script.Parent.Parent.Util.Zip)
const Manifest = require(script.Parent.Manifest)
const Types = require(script.Parent.Types)

type Package = Types.Package

export type Imported = {
	kind: "script",
	name: string,
	source: string,
} | {
	kind: "package",
	package: Package,
} | {
	kind: "folder",
	name: string,
	vfs: Vfs.Vfs,
}

const File = {}

-- 파일 선택 창을 띄움. 취소하면 빈 목록
function File.prompt(): { File }
	const ok, files = pcall(StudioService.PromptImportFilesAsync, StudioService, { "lua", "luau", "zip" })
	if not ok then
		error(L(`파일 선택 실패: {files}`, `Could not open the file picker: {files}`), 0)
	end
	return files or {}
end

function File.read(file: File): Imported
	const fileName = file.Name
	const contents = file:GetBinaryContents()
	const lower = string.lower(fileName)

	if string.sub(lower, -4) == ".lua" or string.sub(lower, -5) == ".luau" then
		return {
			kind = "script",
			name = (string.gsub(fileName, "%.luau?$", "")),
			source = contents,
		}
	end

	if string.sub(lower, -4) ~= ".zip" then
		error(L(`지원하지 않는 파일: {fileName}`, `Unsupported file: {fileName}`), 0)
	end

	const vfs = Vfs.new(Zip.extract(contents)):stripSingleRoot()
	const manifest = Manifest.read(vfs)
	const baseName = string.gsub(fileName, "%.[zZ][iI][pP]$", "")

	-- 이름과 버전이 있는 패키지면 _Index 구조로 설치
	if manifest and manifest.scope and manifest.name and manifest.version then
		return {
			kind = "package",
			package = {
				source = "file",
				scope = string.lower(manifest.scope),
				name = string.lower(manifest.name),
				version = manifest.version,
				realm = manifest.realm,
				dependencies = manifest.dependencies,
				serverDependencies = manifest.serverDependencies,
				entryPath = manifest.entryPath,
				fetch = function()
					return vfs
				end,
			},
		}
	end

	return { kind = "folder", name = baseName, vfs = vfs }
end

return File
