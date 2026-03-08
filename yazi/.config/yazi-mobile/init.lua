local function readable_size(bytes)
  local units = { 'B', 'K', 'M', 'G', 'T', 'P' }
  local size = bytes
  local unit = 1

  while size >= 1024 and unit < #units do
    size = size / 1024
    unit = unit + 1
  end

  local text
  if unit == 1 or size >= 10 then
    text = string.format('%.0f%s', size, units[unit])
  else
    text = string.format('%.1f%s', size, units[unit])
  end

  return text:gsub('%.0([KMGTPE])$', '%1')
end

Status:children_add(function()
  local hovered = cx.active.current.hovered
  if not hovered then
    return ''
  end

  local size = hovered:size()
  if not size then
    return ''
  end

  return ui.Line {
    ' ',
    ui.Span(readable_size(size)):fg('cyan'),
    ' ',
  }
end, 450, Status.RIGHT)
