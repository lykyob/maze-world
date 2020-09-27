local Root = script:FindFirstAncestor('MazeGenerator')
local Roact = require(Root.Roact)
local M = require(Root.M)
local Plugin = Root.Plugin
local FitList = require(Plugin.Components.FitList)
local FitText = require(Plugin.Components.FitText)
local FormButton = require(Plugin.Components.FormButton)
local FormTextInput = require(Plugin.Components.FormTextInput)

local e = Roact.createElement

local function SettingsFormItem(props)
	local Text = props.Text
	local theme = props.theme
	local Input = props.Input
	local LayoutOrder = props.LayoutOrder

	local textFieldWidth = 200

	return e(
		FitList,
		{
			fitAxes = 'X',
			containerProps = {
				LayoutOrder = LayoutOrder,
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 0, 0, 50),
			},
			layoutProps = {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 10),
			},
		},
		{
			Label = e(FitText, {
				Kind = 'TextLabel',
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = theme.TitleFont,
				TextSize = 20,
				Text = Text,
				TextColor3 = theme.Text1,
				MinSize = Vector2.new(textFieldWidth, 0),
			}),
			Input = Input,
		}
	)
end

return SettingsFormItem