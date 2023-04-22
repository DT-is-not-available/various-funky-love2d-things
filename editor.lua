---Creates a new editor object
---@param w? integer
---@param h? integer
---@param style? table
---@return editor
return function(w, h, style)
	--- @class default_style
	local default_style = {
		background = {0.1, 0.1, 0.1},
		line_number = {0.5, 0.5, 0.5},
		text = {1, 1, 1},
		current_line = {0.2, 0.2, 0.2},
		current_line_number = {0.85, 0.85, 0.85},
		selection = {0.15, 0.65, 1, 0.35},

		token_string = {206/255, 145/255, 120/255},
		token_blue = {62/255, 156/255, 214/255},
		token_purple = {197/255, 131/255, 192/255},
		token_variable = {156/255, 220/255, 1},
		token_number = {181/255, 206/255, 168/255},
		token_comment = {106/255, 153/255, 85/255},
	}
	style = style or {}
	local style_mt = {__index=function(tbl, i) return (default_style)[i] end}
	setmetatable(style, style_mt)

	--- @class editor
	local self = {}

	local lg = love.graphics

	--- The canvas the editor draws to before drawing to the screen.
	self.canvas = lg.newCanvas(w or lg.getWidth(), h or lg.getHeight())

	local font = lg.newFont("RobotoMono-Regular.ttf", style.font_size)

	if font:getWidth('W') ~= font:getWidth('|') then
		error("editor: font must be monospace")
	end

	local char_width = font:getWidth('W')
	local char_height = font:getHeight()

	local x = 0
	local y = 0

	-- A list containing each line of text in the file.
	self.text = {""}
	-- A list containing each line of formatted text in the file, represented as a love2d colored text table.
	self.formatted_text = {{style.text, ""}}
	--- Line number the cursor is placed on, 1-based.
	self.line = 1
	--- Character number the cursor is placed on.
	---
	--- While this is 0-based, it places the cursor *before* the character.
	self.pos = 0
	self.select_line = 1
	self.select_pos = 0

	--- The maximum distance the Y position of the viewport can travel to.
	self.max_scroll_y = 0
	--- The Y position of the viewport.
	self.scroll_y = 0
	--- The maximum distance the X position of the viewport can travel to.
	self.max_scroll_x = 0
	--- The X position of the viewport.
	self.scroll_x = 0

	--- Variable that controls whether or not the blinking cursor is shown.
	---
	--- Loops from `0-60`, if it is above `30` the cursor is not shown.
	self.carretTimer = 0

	local undo_history = {}
	local undo_index = 0

	--- Sets the style of the editor.
	--- @see default_style
	--- @param style_table table
	function self:set_style(style_table)
		style = style_table
		setmetatable(style, style_mt)
		font = lg.newFont("RobotoMono-Regular.ttf", style.font_size)

		if font:getWidth('W') ~= font:getWidth('|') then
			error("editor: font must be monospace")
		end

		char_width = font:getWidth('W')
		char_height = font:getHeight()
		self:format_all_text()
	end

	--- Gets the style of the editor.
	--- @see default_style
	function self:get_style()
		return style
	end

	--- Calculates the scroll width of the viewport.
	---
	--- **This takes some time with longer texts, so use it sparingly!**
	function self:get_width()
		return font:getWidth(self:getText()) + 50
	end

	--- Sets the max width of the viewport using `:get_width()`.
	---
	--- **This takes some time with longer texts, so use it sparingly!**
	function self:set_max_scroll_x()
		self.max_scroll_x = math.max(self:get_width() - self.canvas:getWidth() + 50, 0)
	end

	local function push_undo(undofunc, undoargs, redofunc, redoargs)
		undo_history[undo_index+1] = {undofunc, undoargs, redofunc, redoargs}
		undo_index = undo_index + 1
		if undo_index ~= #undo_history then
			for i = undo_index + 1, #undo_history do
				undo_history[i] = nil
			end
		end
	end

	local function undo()
		if undo_index > 0 then
			undo_history[undo_index][1](unpack(undo_history[undo_index][2]))
			undo_index = undo_index - 1
		end
	end

	local function redo()
		if undo_index < #undo_history then
			undo_index = undo_index + 1
			undo_history[undo_index][3](unpack(undo_history[undo_index][4]))
		end
	end

	--- Scrolls the viewport vertically to meet the cursor
	--- @param maximum_distance? number
	function self:autoscroll_vertically(maximum_distance)
		maximum_distance = maximum_distance or self.max_scroll_y
		if (self.line-1)*char_height - char_height < self.scroll_y then
			self.scroll_y = self.scroll_y + math.max((self.line-1)*char_height - self.scroll_y - char_height, -maximum_distance)
			if self.scroll_y < 0 then
				self.scroll_y = 0
			end
		end
		if (self.line)*char_height - self.canvas:getHeight() + char_height > self.scroll_y then
			self.scroll_y = self.scroll_y + math.min((self.line)*char_height - self.canvas:getHeight() + char_height - self.scroll_y, maximum_distance)
		end
	end

	--- Scrolls the viewport horizontally to meet the cursor
	--- @param maximum_distance? number
	function self:autoscroll_horizontally(maximum_distance)
		maximum_distance = maximum_distance or self.max_scroll_x
		if (self.pos)*char_width - char_width*2.5 < self.scroll_x then
			self.scroll_x = self.scroll_x + math.max((self.pos)*char_width - char_width*2.5 - self.scroll_x, -maximum_distance)
		end
		if (self.pos+1)*char_width + 50 - self.canvas:getWidth() + char_width*2.5 > self.scroll_x then
			self.scroll_x = self.scroll_x + math.min((self.pos+1)*char_width + 50 - self.canvas:getWidth() + char_width*2.5 - self.scroll_x, maximum_distance)
		end
		if self.scroll_x < 0 then
			self.scroll_x = 0
		end
		if self.scroll_x > self.max_scroll_x then
			self.scroll_x = self.max_scroll_x
		end
	end

	--- @param index integer
	--- Deletes the line at the specified index
	function self:delete_line(index)
		self.max_scroll_y = self.max_scroll_y - char_height
		if self.scroll_y > self.max_scroll_y then
			self.scroll_y = self.max_scroll_y
		end
		table.remove(self.text, index)
		table.remove(self.formatted_text, index)
		self:autoscroll_vertically()
		self:autoscroll_horizontally()
	end

	--- @overload fun(self, text: string)
	--- @param index integer
	--- @param text string
	--- Inserts a new line at the specified index
	function self:insert_line(index, text)
		self.max_scroll_y = self.max_scroll_y + char_height
		if not text then
			table.insert(self.text, index)
---@diagnostic disable-next-line: param-type-mismatch
			table.insert(self.formatted_text, self:format(index))
		end
		table.insert(self.text, index, text)
		table.insert(self.formatted_text, index, self:format(text))
		self:autoscroll_vertically()
		self:autoscroll_horizontally()
	end

	--- @param index integer
	--- @param text? string
	--- Overwrites/reformats a line at the specified index
	function self:set_line(index, text)
		if text then self.text[index] = text end
		self.formatted_text[index] = self:format(text or self.text[index])
	end

	--- Deselects any selected text
	function self:deselect()
		self.select_line = self.line
		self.select_pos = self.pos
	end

	--- Deselects any selected text unless the shift key is being held
	function self:try_deselect()
		if not love.keyboard.isDown("lshift") and not love.keyboard.isDown("rshift") then
			self:deselect()
		end
	end

	--- Checks if any text is selected
	function self:is_selected()
		return self.pos ~= self.select_pos or self.line ~= self.select_line
	end

	--- Deletes the selected text
	function self:delete_selected()
		if not self:is_selected() then
			return
		end
		local start_select
		local end_select
		if self.select_line > self.line then
			start_select = {self.pos, self.line}
			end_select = {self.select_pos, self.select_line}
		elseif self.select_line == self.line then
			if self.select_pos > self.pos then
				start_select = {self.pos, self.line}
				end_select = {self.select_pos, self.select_line}
			else
				start_select = {self.select_pos, self.select_line}
				end_select = {self.pos, self.line}
			end
		else
			start_select = {self.select_pos, self.select_line}
			end_select = {self.pos, self.line}
		end
		local i = end_select[2] - 1
		while i > start_select[2] do
			end_select[2] = end_select[2] - 1
			self:delete_line(i)
			i = i - 1
		end
		if start_select[2] == end_select[2] then
			self:set_line(self.line, self.text[self.line]:sub(1, start_select[1]) .. self.text[self.line]:sub(end_select[1] + 1))
		else
			self:set_line(start_select[2], self.text[start_select[2]]:sub(1, start_select[1]) .. self.text[end_select[2]]:sub(end_select[1] + 1))
			self:delete_line(end_select[2])
		end
		self.pos = start_select[1]
		self.line = start_select[2]
		self:set_max_scroll_x()
		self:autoscroll_horizontally()
		self:deselect()
	end

	--- Returns the selected text
	function self:get_selected()
		if not self:is_selected() then
			return nil
		end
		local start_select
		local end_select
		if self.select_line > self.line then
			start_select = {self.pos, self.line}
			end_select = {self.select_pos, self.select_line}
		elseif self.select_line == self.line then
			if self.select_pos > self.pos then
				start_select = {self.pos, self.line}
				end_select = {self.select_pos, self.select_line}
			else
				start_select = {self.select_pos, self.select_line}
				end_select = {self.pos, self.line}
			end
		else
			start_select = {self.select_pos, self.select_line}
			end_select = {self.pos, self.line}
		end
		if start_select[2] == end_select[2] then
			return self.text[self.line]:sub(start_select[1] + 1, end_select[1])
		else
			local start = self.text[start_select[2]]:sub(start_select[1] + 1) .. "\n"
			local i = end_select[2] - 1
			local t = {}
			while i > start_select[2] do
				t[i - start_select[2]] = self.text[i]
				i = i - 1
			end
			local str = start .. table.concat(t, "\n") .. (#t > 0 and "\n" or "") .. self.text[end_select[2]]:sub(1, end_select[1])
			return str
		end
	end

	--- A function that takes a one line string as an input and returns a colored text table.
	---
	--- This function can be overwritten to implement syntax highlighting
	--- @return table colored_text
	--- @param text string
	function self:format(text)
		return {style.text, text}
	end

	--- Resizes the viewport
	--- @param width integer
	--- @param height integer
	function self:resize(width, height)
		self.canvas = lg.newCanvas(width or lg.getWidth(), height or lg.getHeight())
		self:set_max_scroll_x()
		if self.scroll_x < 0 then
			self.scroll_x = 0
		end
		if self.scroll_x > self.max_scroll_x then
			self.scroll_x = self.max_scroll_x
		end
	end

	--- Returns the raw text in the file
	function self:getText()
		return table.concat(self.text, "\n")
	end

	--- Draws the viewport at the specified x and y positions
	--- @param x_pos number
	--- @param y_pos number
	function self:draw(x_pos, y_pos)
		x = x_pos
		y = y_pos
		local start_select
		local end_select
		if self.select_line > self.line then
			start_select = {self.pos, self.line}
			end_select = {self.select_pos, self.select_line}
		elseif self.select_line == self.line then
			if self.select_pos > self.pos then
				start_select = {self.pos, self.line}
				end_select = {self.select_pos, self.select_line}
			else
				start_select = {self.select_pos, self.select_line}
				end_select = {self.pos, self.line}
			end
		else
			start_select = {self.select_pos, self.select_line}
			end_select = {self.pos, self.line}
		end
		local o = lg.getCanvas()
		lg.setCanvas(self.canvas)
		lg.setFont(font)
		lg.clear(style.background)
		lg.translate(0, -self.scroll_y)
		local index = 0
		for i = math.floor(self.scroll_y/char_height) + 1, math.min(#self.text, math.floor((self.scroll_y+self.canvas:getHeight())/char_height + 1)), 1 do
			local line = self.text[i]
			if i == self.line and not self:is_selected() then
				if style.current_line_style < 0 then
					lg.setColor(style.current_line)
					lg.rectangle("fill", 50-self.scroll_x, (i-1)*char_height, self.canvas:getWidth()+20, char_height)
				end
			end
			lg.translate(-self.scroll_x, 0)
			lg.setColor(1, 1, 1)
			lg.print(self.formatted_text[i], 50, (i-1)*char_height)
			lg.setColor(style.selection)
			if i > start_select[2] and i < end_select[2] then
				lg.rectangle("fill", 50, (i-1)*char_height, (#line+1)*char_width, char_height)
			end
			if i == start_select[2] and start_select[2] ~= end_select[2] then
				lg.rectangle("fill", 50 + start_select[1] * char_width, (i-1)*char_height, (#line+1)*char_width - start_select[1] * char_width, char_height)
			end
			if i == end_select[2] and start_select[2] ~= end_select[2] then
				lg.rectangle("fill", 50, (i-1)*char_height, end_select[1] * char_width, char_height)
			end
			if i == start_select[2] and start_select[2] == end_select[2] then
				lg.rectangle("fill", 50 + start_select[1] * char_width, (i-1)*char_height, end_select[1] * char_width - start_select[1] * char_width, char_height)
			end
			lg.translate(self.scroll_x, 0)
			if i == self.line and not self:is_selected() then
				if style.current_line_style >= 0 then
					lg.setColor(style.current_line)
					lg.setLineWidth(style.current_line_style or 1)
					lg.rectangle("line", 49.5-self.scroll_x, (i-1)*char_height+0.5, self.canvas:getWidth()+20, char_height)
				end
				lg.setColor(style.current_line_number or style.text)
			end
			lg.setColor(style.line_number_panel or style.background)
			lg.rectangle("fill", 0, (i-1)*char_height-1, 49, char_height+2)
			lg.setColor(style.line_number)
			lg.print(tostring(i), 40-font:getWidth(tostring(i)), (i-1)*char_height)
			index = i
		end
		lg.setColor(style.line_number_panel or style.background)
		lg.rectangle("fill", 0, index*char_height-1, 49, self.canvas:getHeight())
		lg.setColor(style.carret or style.text)
		if self.carretTimer < 30 and self.pos*char_width-self.scroll_x >= 0 then
			lg.rectangle( "fill",
				self.pos*char_width+50-self.scroll_x,
				(self.line-1)*char_height,
				1,
				char_height
			)
		end
		self.carretTimer = self.carretTimer + 1 - math.floor(self.carretTimer/60)*60
		lg.setColor(1, 1, 1, 1)
		lg.translate(0, self.scroll_y)
		lg.setCanvas(o)
		lg.draw(self.canvas, x_pos, y_pos)
	end

	--- does nothing, but it might later
---@diagnostic disable-next-line: undefined-doc-name
	--- @return not_really important
	function self:update()

---@diagnostic disable-next-line: missing-return
	end

	--[[ Text input event:
	
	function love.textinput(text)
		...
		editor:textinput(text)
	end
	]]
	--- @param text string
	function self:textinput(text)
		self:delete_selected()
		self:insert_raw_text_on_line(text:gsub("\t","    "))
		self:deselect()
		self:set_max_scroll_x()
		self:autoscroll_horizontally()
		self:autoscroll_vertically()
	end

	--- Deletes all saved text
	function self:clear()
		self.text = {''}
	end

	--- Inserts text at the cursor's position and moves it, selecting it in the process.
	---
	--- `text` cannot contain a newline
	--- @param text string
	--- @param dont_move_pos? boolean
	function self:insert_raw_text_on_line(text, dont_move_pos)
		self:set_line(self.line, self.text[self.line]:sub(1, self.pos) .. text .. self.text[self.line]:sub(self.pos+1))
		if not dont_move_pos then self.pos = self.pos + #text end
	end

	--- Reformats the entire file
	function self:format_all_text()
		for i = 1, #self.text do
			self:set_line(i, self.text[i])
		end
	end

	--- Pastes the specified text at the cursor position, or when none is specified, paste the clipboard
	---
	--- Unlike `insert_raw_text_on_line` and `textinput`, this supports multiple lines
	--- 
	--- For performance, if your text is only one line, call `textinput` instead
	--- @param text? string
	function self:paste(text)
		local end_select
		if self.select_line > self.line then
			end_select = {self.select_pos, self.select_line}
		elseif self.select_line == self.line then
			if self.select_pos > self.pos then
				end_select = {self.select_pos, self.select_line}
			else
				end_select = {self.pos, self.line}
			end
		else
			end_select = {self.pos, self.line}
		end
		local end_text = self.text[end_select[2]]:sub(end_select[1]+1)
		self.text[end_select[2]] = self.text[end_select[2]]:sub(1, end_select[1])
		self:delete_selected()
		local lines = {}
		for s in (text or love.system.getClipboardText()):gsub("\t","    "):gsub("\r\n", "\n"):gmatch("\n?[^\n]*") do
			lines[#lines+1] = s:gsub("^\n","")
		end
		self:deselect()
		self:insert_raw_text_on_line(lines[1])
		for i = 2, #lines-1, 1 do
			local line = lines[i]
			self.line = self.line + 1
			self:insert_line(self.line, line)
			self.pos = #self.text[self.line]
		end
		self:insert_raw_text_on_line(end_text, true)
		self:deselect()
		self:set_max_scroll_x()
		self:autoscroll_horizontally()
	end

	--[[ Key pressed event:
	
	function love.keypressed(key)
		...
		editor:keypressed(key)
	end
	]]
	function self:keypressed(key)
		self.carretTimer = 0
		if love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
			if key == "v" then
				self:paste()
			end
			if key == "a" then
				self.select_line = 1
				self.select_pos = 0
				self.line = #self.text
				self.pos = #self.text[#self.text]
			end
			if key == "c" then
				local copy = self:get_selected()
				if copy then
					love.system.setClipboardText(copy)
				end
			end
			if key == "x" then
				local copy = self:get_selected()
				if copy then
					love.system.setClipboardText(copy)
				end
				self:delete_selected()
				self:set_max_scroll_x()
			end
		end
		if key == "tab" then
			self:textinput("    ")
		end
		if key == "right" then
			if self.pos == #self.text[self.line] then
				if self.line ~= #self.text then
					self.pos = 0
					self.line = self.line + 1
					self:autoscroll_horizontally()
				end
			else
				self.pos = self.pos + 1
			end
			self:try_deselect()
		end
		if key == "left" then
			if self.pos == 0 then
				if self.line ~= 1 then
					self.line = self.line - 1
					self.pos = #self.text[self.line]
					self:autoscroll_horizontally()
				end
			else
				self.pos = self.pos - 1
			end
			self:try_deselect()
		end
		if key == "up" then
			if self.line == 1 then
				self.pos = 0
			else
				self.line = self.line - 1
				if self.pos > #self.text[self.line] then
					self.pos = #self.text[self.line]
				end
				self:autoscroll_vertically()
			end
			self:try_deselect()
		end
		if key == "down" then
			if self.line == #self.text then
				self.pos = #self.text[self.line]
			else
				self.line = self.line + 1
				if self.pos > #self.text[self.line] then
					self.pos = #self.text[self.line]
				end
				self:autoscroll_vertically()
			end
			self:try_deselect()
		end
		if key == "home" then
			self.pos = 0
			self:try_deselect()
			self:autoscroll_horizontally()
		end
		if key == "end" then
			self.pos = #self.text[self.line]
			self:try_deselect()
			self:autoscroll_horizontally()
		end
		if key == "backspace" then
			if self:is_selected() then
				self:delete_selected()
			else
				if self.line == 1 and self.pos == 0 then
					return
				end
				if self.pos > 0 then
					self:set_line(self.line, self.text[self.line]:sub(1, self.pos-1) .. self.text[self.line]:sub(self.pos+1))
					self.pos = self.pos - 1
				else
					local text = self.text[self.line]
					self:delete_line(self.line)
					self.line = self.line - 1
					self.pos = #self.text[self.line]
					self:set_line(self.line, self.text[self.line] .. text)
				end
			end
			self:set_max_scroll_x()
			self:autoscroll_horizontally()
			self:deselect()
		end
		if key == "delete" then
			if self:is_selected() then
				self:delete_selected()
			else
				if self.line == #self.text and self.pos == #self.text[self.line] then
					return
				end
				if self.pos < #self.text[self.line] then
					self:set_line(self.line, self.text[self.line]:sub(1, self.pos) .. self.text[self.line]:sub(self.pos+2))
				else
					local text = self.text[self.line+1]
					self:delete_line(self.line+1)
					self:set_line(self.line, self.text[self.line] .. text)
				end
			end
			self:set_max_scroll_x()
			self:autoscroll_horizontally()
			self:deselect()
		end
		if key == "kenter" or key == "return" or key == "enter" then
			self:delete_selected()
			local text = self.text[self.line]:sub(self.pos+1)
			self:set_line(self.line, self.text[self.line]:sub(1, self.pos))
			self:insert_line(self.line+1, text)
			self.line = self.line + 1
			self.pos = 0
			self:deselect()
			self:set_max_scroll_x()
			self:autoscroll_horizontally()
			self:autoscroll_vertically()
		end
	end

	--[[ Mouse pressed event:
	
	function love.mousepressed(x_pos, y_pos, button)
		...
		editor:mousepressed(x_pos, y_pos, button)
	end
	]]
	--- @param x_pos number
	--- @param y_pos number
	--- @param button (1 | 2 | 3)
	function self:mousepressed(x_pos, y_pos, button)
		local line = math.floor((y_pos-y+self.scroll_y)/char_height) + 1
		local pos = math.floor(((x_pos-x+self.scroll_x)-50)/char_width+0.5)
		if button == 1 then
			self.carretTimer = 0
			self.line = line
			if self.line > #self.text then
				self.line = #self.text
			end
			if self.line < 1 then
				self.line = 1
			end
			if pos < 0 then
				self.pos = 0
			else
				self.pos = pos
				if self.pos > #self.text[self.line] then
					self.pos = #self.text[self.line]
				end
			end
			self:try_deselect()
			if x_pos < 50 + x then
				self.select_line = self.line + 1
				if self.select_line > #self.text then
					self.select_line = self.line
					self.select_pos = #self.text[self.line]
				end
			end
			self:autoscroll_vertically(char_height)
		end
	end

	--[[ Mouse moved event:
	
	function love.mousemoved(x_pos, y_pos)
		...
		editor:mousemoved(x_pos, y_pos)
	end
	]]
	---@param x_pos number
	---@param y_pos number
	function self:mousemoved(x_pos, y_pos)
		local line = math.floor((y_pos-y+self.scroll_y)/char_height) + 1
		local pos = math.floor(((x_pos-x+self.scroll_x)-50)/char_width+0.5)
		if love.mouse.isDown(1) then
			self.carretTimer = 0
			self.line = line
			if self.line > #self.text then
				self.line = #self.text
			end
			if self.line < 1 then
				self.line = 1
			end
			if pos < 0 then
				self.pos = 0
			else
				self.pos = pos
				if self.pos > #self.text[self.line] then
					self.pos = #self.text[self.line]
				end
			end
			self:autoscroll_vertically(char_height)
		end
	end

	--[[ Mouse released event:
	
	function love.mousereleased(x_pos, y_pos, button)
		...
		editor:mousereleased(x_pos, y_pos, button)
	end
	]]
	--- @param x_pos number
	--- @param y_pos number
	--- @param button (1 | 2 | 3)
	function self:mousereleased(x_pos, y_pos, button)

	end

	--[[ Wheel moved event:
	
	function love.wheelmoved(x_pos, y_pos)
		...
		editor:wheelmoved(x_pos, y_pos)
	end
	]]
	--- @param x_pos number
	--- @param y_pos number
	function self:wheelmoved(x_pos, y_pos)
		local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
		self.scroll_y = self.scroll_y + (shift and x_pos or -y_pos) * 20
		if self.scroll_y < 0 then
			self.scroll_y = 0
		end
		if self.scroll_y > self.max_scroll_y then
			self.scroll_y = self.max_scroll_y
		end
		self.scroll_x = self.scroll_x + (shift and -y_pos or x_pos) * 20
		if self.scroll_x < 0 then
			self.scroll_x = 0
		end
		if self.scroll_x > self.max_scroll_x then
			self.scroll_x = self.max_scroll_x
		end
	end

	return self
end
