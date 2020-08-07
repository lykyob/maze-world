local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Modules = ReplicatedStorage:WaitForChild('Modules')
local logger = require(Modules.src.utils.Logger)

local Maze = require(script.Parent.Maze)
local Models = ReplicatedStorage:WaitForChild('Models')
local Prefabs = Models.Prefabs
local Walls = Models.Walls
local recursive_backtracker = require(script.Parent.MazeBacktrace)

local blockHeight = 20
local blockWidth = 25
local blockDepth = 0

local floorPartName = 'FloorPart'

function partToRegion3(obj)
	local abs = math.abs

	local cf = obj.CFrame -- this causes a LuaBridge invocation + heap allocation to create CFrame object - expensive! - but no way around it. we need the cframe
	local size = obj.Size -- this causes a LuaBridge invocation + heap allocation to create Vector3 object - expensive! - but no way around it
	local sx, sy, sz = size.X, size.Y, size.Z -- this causes 3 Lua->C++ invocations
	local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = cf:components() -- this causes 1 Lua->C++ invocations and gets all components of cframe in one go, with no allocations
	-- https://zeuxcg.org/2010/10/17/aabb-from-obb-with-component-wise-abs/
	local wsx = 0.5 * (abs(R00) * sx + abs(R01) * sy + abs(R02) * sz) -- this requires 3 Lua->C++ invocations to call abs, but no hash lookups since we cached abs value above; otherwise this is just a bunch of local ops
	local wsy = 0.5 * (abs(R10) * sx + abs(R11) * sy + abs(R12) * sz) -- same
	local wsz = 0.5 * (abs(R20) * sx + abs(R21) * sy + abs(R22) * sz) -- same
	-- just a bunch of local ops
	local minx = x - wsx
	local miny = y - wsy
	local minz = z - wsz

	local maxx = x + wsx
	local maxy = y + wsy
	local maxz = z + wsz

	local minv, maxv = Vector3.new(minx, miny, minz), Vector3.new(maxx, maxy, maxz)
	return Region3.new(minv, maxv)
end

function DrawBlock(x, y, z, location, vertical, wallsFolder)
	local newBlock = Instance.new('Part')

	newBlock.Size = Vector3.new(1, blockHeight, blockWidth)
	local halfWidth = newBlock.Size.Z / 2
	local halfHeight = newBlock.Size.Y / 2

	local position = CFrame.new(x, z + halfHeight, y + halfWidth)

	if vertical then
		local angle = math.rad(90)
		position = CFrame.new(x + halfWidth, z + halfHeight, y) * CFrame.Angles(0, angle, 0)
	end

	newBlock.CFrame = position

	local region = partToRegion3(newBlock)
	region = region:ExpandToGrid(4)

	game.Workspace.Terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(91, 154, 76))
	game.Workspace.Terrain:FillRegion(region, 4, Enum.Material.Grass)

	-- make top walls not walkable, by killing
	local killBlockName = 'Killbrick'
	local killBlock = Prefabs[killBlockName]:Clone()
	killBlock.Size = Vector3.new(3, 4, blockWidth)
	killBlock.CFrame = newBlock.CFrame + Vector3.new(0, blockHeight - 7, 0)
	killBlock.Transparency = 1
	killBlock.Parent = location
end

function DrawBlock2(x, y, z, location, vertical, wallsFolder)
	local walls = wallsFolder:GetChildren()
	local randomWall = walls[math.random(1, #walls)]
	local newBlock = randomWall:Clone()

	newBlock.Parent = location
	-- newBlock.Size = Vector3.new(3,3,3)
	-- newBlock.Orientation = Vector3.new(0, 0, 90)

	local halfWidth = newBlock.PrimaryPart.Size.Z / 2
	local halfHeight = newBlock.PrimaryPart.Size.Y / 2
	local position = CFrame.new(x, z + halfHeight, y + halfWidth)

	if vertical then
		local angle = math.rad(90)
		position = CFrame.new(x + halfWidth, z + halfHeight, y) * CFrame.Angles(0, angle, 0)
	end

	-- we are flipping y an z here, using x and y for Maze is simpler to read, z is height
	-- x, y, z is correct order
	newBlock:SetPrimaryPartCFrame(position)

	local region = partToRegion3(newBlock.PrimaryPart)
	region = region:ExpandToGrid(4)

	game.Workspace.Terrain:FillRegion(region, 4, Enum.Material.Grass)
	--[[
	workspace.Terrain:FillBlock(
		newBlock.PrimaryPart.CFrame,
		newBlock.PrimaryPart.Size,
		Enum.Material.WoodPlanks
	)]]
end

function DrawFloor(x, y, z, location, width, height)
	local block = 'Floor'
	local newBlock = Prefabs[block]:Clone()
	newBlock.Parent = location
	newBlock.Size = Vector3.new(width, 1, height)
	newBlock.Name = floorPartName
	newBlock.Transparency = 1
	newBlock.CanCollide = false

	local position = CFrame.new(x + width / 2, z, y + height / 2)
	newBlock.CFrame = position

	workspace.Terrain:FillBlock(newBlock.CFrame, newBlock.Size, Enum.Material.Water)
end

function DrawStart(x, y, z, location, width, height)
	local block = 'SpawnPlaceholder'
	local newBlock = Prefabs[block]:Clone()

	local position = Vector3.new(x + width / 2, z + 4, y + height / 2)
	newBlock.Position = position
	newBlock.Parent = location
end

function DrawFinish(x, y, z, location, width, height)
	local block = 'FinishPlaceholder'
	local newBlock = Prefabs[block]:Clone()

	local position = Vector3.new(x + width / 2, z, y + height / 2)
	newBlock.Position = position
	newBlock.Parent = location
end

local function draw_maze(maze, blockWidth, blockDepth, location, primaryPart, wallFolder)
	local halfWidth = primaryPart.Size.X / 2
	local halfDepth = primaryPart.Size.Z / 2
	local halfHeight = primaryPart.Size.Y / 2

	local blockHeight = 20
	local x = primaryPart.Position.X - halfWidth
	local y = primaryPart.Position.Z - halfDepth
	local z = primaryPart.Position.Y + halfHeight

	logger:d('Positioning Maze: ' .. x .. ' ' .. y)
	local maze_width = (blockWidth + blockDepth) * #maze[1] + blockDepth
	local maze_height = (blockWidth + blockDepth) * #maze + blockDepth

	DrawFloor(x, y, z, location, maze_width, maze_height)
	DrawStart(x, y, z + 1, location, blockWidth, blockWidth)

	local finisWidth = blockWidth - 2
	DrawFinish(
		x + maze_width - finisWidth,
		y + maze_height - finisWidth,
		z + 1,
		location,
		finisWidth,
		finisWidth
	)

	for yi = 1, #maze do
		for xi = 1, #maze[1] do
			local pos_x = x + (blockWidth + blockDepth) * (xi - 1) + blockDepth
			local pos_y = y + (blockWidth + blockDepth) * (yi - 1) + blockDepth

			local cell = maze[yi][xi]

			if not cell.north:IsOpened() then
				DrawBlock(pos_x, pos_y - blockDepth, z, location, true, wallFolder)
			end

			if not cell.east:IsOpened() then
				DrawBlock(pos_x + blockWidth, pos_y, z, location, false, wallFolder)
			end

			if not cell.south:IsOpened() then
				DrawBlock(pos_x, pos_y + blockWidth, z, location, true, wallFolder)
			end

			if not cell.west:IsOpened() then
				DrawBlock(pos_x - blockDepth, pos_y, z, location, false, wallFolder)
			end
		end
	end
end

local MazeGenerator = {}

local mazeFolderName = 'Maze'

function MazeGenerator:generate(map, width, height)
	logger:d('Generating maze  width:' .. width .. ', height:' .. height)
	local primaryPart = map.PrimaryPart

	local maze = Maze:new(width, height, true)

	recursive_backtracker(maze)

	local mazeFolder = map:FindFirstChild(mazeFolderName)

	if mazeFolder then
		local floorPart = mazeFolder:FindFirstChild(floorPartName)

		workspace.Terrain:FillBlock(
			floorPart.CFrame,
			floorPart.Size + Vector3.new(0, blockHeight * 2, 0),
			Enum.Material.Air
		)
		mazeFolder:Destroy()
	end

	mazeFolder = Instance.new('Folder')
	mazeFolder.Name = mazeFolderName
	mazeFolder.Parent = map

	local wallFolder = Walls.Walls_1
	draw_maze(maze, blockWidth, blockDepth, mazeFolder, primaryPart, wallFolder)
end

return MazeGenerator