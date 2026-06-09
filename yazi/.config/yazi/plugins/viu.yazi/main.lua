-- Alacritty has no graphics protocol -> render images as ANSI half-blocks via viu.
local M = {}

function M:peek(job)
	local path = tostring(job.file.url)
	local output, err = Command("viu")
		:arg({ "-b", "-s", "-w", tostring(job.area.w), "-h", tostring(job.area.h), "--", path })
		:output()

	local text
	if output then
		text = ui.Text.parse(output.stdout)
	else
		text = ui.Text(string.format("Failed to start `viu`, error: %s", err))
	end

	ya.preview_widget(job, text:area(job.area))
end

function M:seek() end

return M
