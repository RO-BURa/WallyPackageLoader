-- Rojo JSON 속성 / Attribute 값 -> Roblox 값
--   암시적: "Size": [1, 2, 3]            (속성의 현재 타입을 보고 변환)
--   명시적: "Size": { "Vector3": [1, 2, 3] }
-- .model.json, .meta.json, project.json 의 $properties / $attributes 에서 사용

const RojoValues = {}

const function identity(value: any): any
	return value
end

const function toNumber(value: any): number
	if type(value) ~= "number" then
		error(`숫자가 필요함: {value}`, 0)
	end
	return value
end

const function vector3(value: any): Vector3
	return Vector3.new(value[1], value[2], value[3])
end

const function vector2(value: any): Vector2
	return Vector2.new(value[1], value[2])
end

const function color3(value: any): Color3
	return Color3.new(value[1], value[2], value[3])
end

const function cframe(value: any): CFrame
	if type(value) == "table" and value.position then
		const p, o = value.position, value.orientation
		if not o then
			return CFrame.new(p[1], p[2], p[3])
		end
		return CFrame.new(p[1], p[2], p[3], o[1][1], o[1][2], o[1][3], o[2][1], o[2][2], o[2][3], o[3][1], o[3][2], o[3][3])
	end
	-- 숫자 12개 / 3개
	return CFrame.new(table.unpack(value))
end

const function font(value: any): Font
	if type(value) == "string" then
		return Font.new(value)
	end
	const weight = if value.weight then (Enum.FontWeight :: any)[value.weight] else Enum.FontWeight.Regular
	const style = if value.style then (Enum.FontStyle :: any)[value.style] else Enum.FontStyle.Normal
	return Font.new(value.family, weight, style)
end

const function numberSequence(value: any): NumberSequence
	if type(value) == "number" then
		return NumberSequence.new(value)
	end
	const keypoints = {}
	for _, point in value.keypoints or value do
		table.insert(keypoints, NumberSequenceKeypoint.new(point.time, point.value, point.envelope or 0))
	end
	return NumberSequence.new(keypoints)
end

const function colorSequence(value: any): ColorSequence
	const keypoints = {}
	for _, point in value.keypoints or value do
		table.insert(keypoints, ColorSequenceKeypoint.new(point.time, color3(point.color)))
	end
	return ColorSequence.new(keypoints)
end

const function physicalProperties(value: any): PhysicalProperties?
	if value == "Default" or value == nil then
		return nil
	end
	return PhysicalProperties.new(
		value.density,
		value.friction,
		value.elasticity,
		value.frictionWeight,
		value.elasticityWeight
	)
end

-- 명시적 타입 이름 (rbx-dom 이름) -> 변환 함수
const EXPLICIT: { [string]: (any) -> any } = {
	Bool = identity,
	String = identity,
	Content = identity,
	ContentId = identity,
	Float32 = toNumber,
	Float64 = toNumber,
	Int32 = toNumber,
	Int64 = toNumber,
	Vector2 = vector2,
	Vector2int16 = function(value)
		return Vector2int16.new(value[1], value[2])
	end,
	Vector3 = vector3,
	Vector3int16 = function(value)
		return Vector3int16.new(value[1], value[2], value[3])
	end,
	Color3 = color3,
	Color3uint8 = function(value)
		return Color3.fromRGB(value[1], value[2], value[3])
	end,
	UDim = function(value)
		return UDim.new(value[1], value[2])
	end,
	UDim2 = function(value)
		return UDim2.new(value[1][1], value[1][2], value[2][1], value[2][2])
	end,
	Rect = function(value)
		return Rect.new(value[1][1], value[1][2], value[2][1], value[2][2])
	end,
	NumberRange = function(value)
		return NumberRange.new(value[1], value[2])
	end,
	CFrame = cframe,
	BrickColor = function(value)
		return BrickColor.new(value)
	end,
	Font = font,
	NumberSequence = numberSequence,
	ColorSequence = colorSequence,
	PhysicalProperties = physicalProperties,
	-- Enum 은 숫자. 실제 EnumItem 으로는 속성 타입을 보고 바꿈
	Enum = toNumber,
}

-- typeof(현재 값) -> 변환 함수 (암시적 값)
const IMPLICIT: { [string]: (any) -> any } = {
	Vector2 = vector2,
	Vector2int16 = EXPLICIT.Vector2int16,
	Vector3 = vector3,
	Vector3int16 = EXPLICIT.Vector3int16,
	Color3 = color3,
	UDim = EXPLICIT.UDim,
	UDim2 = EXPLICIT.UDim2,
	Rect = EXPLICIT.Rect,
	NumberRange = EXPLICIT.NumberRange,
	CFrame = cframe,
	BrickColor = EXPLICIT.BrickColor,
	Font = font,
	NumberSequence = numberSequence,
	ColorSequence = colorSequence,
	PhysicalProperties = physicalProperties,
}

-- { "Vector3": [...] } 처럼 키 하나짜리 테이블이면 (타입, 값)
const function explicitOf(value: any): (string?, any)
	if type(value) ~= "table" then
		return nil, nil
	end
	const key, inner = next(value)
	if type(key) == "string" and next(value, key) == nil and EXPLICIT[key] then
		return key, inner
	end
	return nil, nil
end

const function toEnumItem(enumType: Enum, value: any): EnumItem
	if type(value) == "string" then
		return (enumType :: any)[value]
	end
	return enumType:FromValue(value) :: EnumItem
end

-- instance.property 에 넣을 값으로 변환
function RojoValues.decodeProperty(instance: Instance, property: string, value: any): any
	const current = (instance :: any)[property]
	const currentType = typeof(current)
	const explicitType, inner = explicitOf(value)

	if explicitType then
		const decoded = EXPLICIT[explicitType](inner)
		if currentType == "EnumItem" then
			return toEnumItem(current.EnumType, decoded)
		end
		return decoded
	end

	if currentType == "EnumItem" then
		return toEnumItem(current.EnumType, value)
	elseif currentType == "Content" and type(value) == "string" then
		return (Content :: any).fromUri(value)
	end
	const convert = IMPLICIT[currentType]
	if convert and type(value) == "table" then
		return convert(value)
	end
	return value
end

-- Attribute 값 (문자열/숫자/bool 은 그대로, 나머지는 명시적 형식)
function RojoValues.decodeAttribute(value: any): any
	const explicitType, inner = explicitOf(value)
	if explicitType then
		return EXPLICIT[explicitType](inner)
	end
	return value
end

const function tagsOf(value: any): { string }
	if type(value) == "table" and value.Tags then
		return value.Tags
	end
	return if type(value) == "table" then value else {}
end

-- properties / attributes 적용. 실패한 항목 이름 목록 반환
function RojoValues.apply(instance: Instance, properties: { [string]: any }?, attributes: { [string]: any }?): { string }
	const failed = {}

	for property, value in properties or {} do
		const ok, err = pcall(function()
			if property == "Tags" then
				for _, tag in tagsOf(value) do
					instance:AddTag(tag)
				end
			elseif property == "Attributes" then
				const map = if type(value) == "table" and value.Attributes then value.Attributes else value
				for name, attribute in map do
					instance:SetAttribute(name, RojoValues.decodeAttribute(attribute))
				end
			else
				(instance :: any)[property] = RojoValues.decodeProperty(instance, property, value)
			end
		end)
		if not ok then
			table.insert(failed, `{property} ({string.match(tostring(err), "^[^\n]*")})`)
		end
	end

	for name, value in attributes or {} do
		const ok, err = pcall(function()
			instance:SetAttribute(name, RojoValues.decodeAttribute(value))
		end)
		if not ok then
			table.insert(failed, `@{name} ({string.match(tostring(err), "^[^\n]*")})`)
		end
	end

	return failed
end

return RojoValues
