-- 플레이스에 저장되는 설정 (ServerStorage.PackageLoaderConfig)
-- Team Create 로 함께 작업하는 사람도 같은 설정을 봄

const HttpService = game:GetService("HttpService")
const ServerStorage = game:GetService("ServerStorage")

export type Dependency = {
	spec: string,
	realm: "shared" | "server",
	location: string?,
}

const Config = {}

const CONFIG_NAME = "PackageLoaderConfig"
const DEFAULT_SHARED = "ReplicatedStorage/Packages"
const DEFAULT_SERVER = "ServerScriptService/ServerPackages"

function Config.getInstance(): Configuration
	const existing = ServerStorage:FindFirstChild(CONFIG_NAME)
	if existing and existing:IsA("Configuration") then
		return existing
	end
	const config = Instance.new("Configuration")
	config.Name = CONFIG_NAME
	config:SetAttribute("SharedPackages", DEFAULT_SHARED)
	config:SetAttribute("ServerPackages", DEFAULT_SERVER)
	config:SetAttribute("Dependencies", "{}")
	config.Parent = ServerStorage
	return config
end

function Config.getSharedPath(): string
	return Config.getInstance():GetAttribute("SharedPackages") or DEFAULT_SHARED
end

function Config.getServerPath(): string
	return Config.getInstance():GetAttribute("ServerPackages") or DEFAULT_SERVER
end

function Config.setSharedPath(path: string)
	Config.getInstance():SetAttribute("SharedPackages", path)
end

function Config.setServerPath(path: string)
	Config.getInstance():SetAttribute("ServerPackages", path)
end

-- 별칭 -> 의존성
function Config.getDependencies(): { [string]: Dependency }
	const raw = Config.getInstance():GetAttribute("Dependencies")
	if type(raw) ~= "string" then
		return {}
	end
	const ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(decoded) == "table" then decoded else {}
end

function Config.setDependency(alias: string, dependency: Dependency?)
	const dependencies = Config.getDependencies()
	dependencies[alias] = dependency
	Config.getInstance():SetAttribute("Dependencies", HttpService:JSONEncode(dependencies))
end

-- "ReplicatedStorage/Packages" 같은 경로를 Instance 로 (없는 폴더는 create 일 때 만듦)
function Config.resolvePath(path: string, create: boolean?): Instance?
	const parts = string.split(path, "/")
	const ok, service = pcall(game.GetService, game, parts[1])
	if not ok or not service then
		error(`알 수 없는 서비스: {parts[1]}`, 0)
	end

	local current: Instance = service
	for i = 2, #parts do
		const name = parts[i]
		if name ~= "" then
			local child = current:FindFirstChild(name)
			if not child then
				if not create then
					return nil
				end
				child = Instance.new("Folder")
				child.Name = name
				child.Parent = current
			end
			current = child
		end
	end
	return current
end

-- Instance -> "Service/Folder/..." 경로
function Config.pathOf(instance: Instance): string
	const parts = {}
	local current: Instance? = instance
	while current and current ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	if current ~= game then
		error(`{instance:GetFullName()} 은(는) DataModel 안에 있지 않음`, 0)
	end
	return table.concat(parts, "/")
end

return Config
