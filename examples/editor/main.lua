local Editor = require("init")
local editor = Editor(nil, nil, {})

function editor:format(text)
	text = text .. "\n"
	local formatted_text = {}
	local t = {}
	local function match(pattern, col)
		local i, j = 0, nil
		while true do
			i, j = string.find(text, pattern, i+1)
			if i == nil then break end
			local sub = text:sub(i, j)
			t[#t+1] = {i-1, {sub, type(col) == "function" and col(sub) or col}}
			text = text:sub(1, i-1) .. ("\n"):rep(#sub) .. text:sub(j + 1)
		end
	end
	local style = self:get_style()
	match('([\"\'])[^\n]-[^\\]%1', style.token_string)
	match('([\"\'])%1', style.token_string)
	match('([\"\'])[^\n]-\n', style.token_string)
	match('%-%-[^\n]-\n', style.token_comment)
	match(':', style.token_blue)
	match('%-?%d-%.?%d+', style.token_number)
	match('[%w_]+', function(m)
		local blue = {
			['self'] = true,
			['local'] = true,
			['true'] = true,
			['false'] = true,
			['nil'] = true,
		}
		local purple = {
			['function'] = true,
			['while'] = true,
			['do'] = true,
			['end'] = true,
			['if'] = true,
			['then'] = true,
			['else'] = true,
			['elseif'] = true,
			['for'] = true,
			['in'] = true,
		}
		if blue[m] then
			return style.token_blue
		elseif purple[m] then
			return style.token_purple
		else
			return style.token_variable
		end
	end)
	match('[^\n]+', style.text)
	table.sort(t, function(a, b) return a[1] < b[1] end)
	for i, value in ipairs(t) do
		formatted_text[#formatted_text+1] = value[2][2]
		formatted_text[#formatted_text+1] = value[2][1]
	end
	return formatted_text
end

love.keyboard.setKeyRepeat(true)

function love.textinput(text)
	editor:textinput(text)
end

function love.keypressed(key)
	editor:keypressed(key)
end

function love.mousepressed(x, y, button)
	editor:mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
	editor:mousereleased(x, y, button)
end

function love.mousemoved(x, y)
	editor:mousemoved(x, y)
end

function love.wheelmoved(x, y)
	editor:wheelmoved(x, y)
end

function love.draw()
	editor:draw(0, 0)
end

function love.update()
	editor:update()
end

function love.resize()
	editor:resize(love.graphics.getDimensions())
end
