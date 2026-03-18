local M = {}

local function normalize_leading_indent(line)
  local leading = line:match '^\t+'
  if leading then
    return ('  '):rep(#leading) .. line:sub(#leading + 1)
  end

  return line
end

local function list_item_parts(line)
  return line:match '^(%s*)([-*+])(%s+.*)$'
end

local function trimmed_ends_with_colon(line)
  return line:gsub('%s+$', ''):sub(-1) == ':'
end

local function is_drawer_boundary(line)
  return line:match '^%s*:[%u_]+:%s*$' ~= nil
end

local function is_drawer_end(line)
  return line:match '^%s*:END:%s*$' ~= nil
end

local function is_property_line(line)
  return line:match '^%s*[%w_/%-]+::%s*' ~= nil
end

local function block_content(line)
  local content = line:gsub('^%s*', '')
  return content:gsub('^%-%s+', '')
end

local function is_directive_boundary(line)
  return block_content(line):match '^#%+[%u_]+'
end

local function is_directive_start(line)
  return block_content(line):match '^#%+BEGIN_'
end

local function is_directive_end(line)
  return block_content(line):match '^#%+END_'
end

local function should_prefix_bullet(line)
  local indent, content = line:match '^(%s*)(.*)$'
  if #indent == 0 or content == '' then
    return false
  end

  if list_item_parts(line) then
    return false
  end

  if is_property_line(line) or is_drawer_boundary(line) or is_directive_boundary(line) then
    return false
  end

  return true
end

local function is_fence(line)
  return line:match '^%s*```'
end

function M.format_lines(lines)
  local out = {}
  local parents = {}
  local in_drawer = false
  local in_directive = false
  local in_fence = false

  for _, raw_line in ipairs(lines) do
    local line = normalize_leading_indent(raw_line)
    local is_blank = line:match '^%s*$' ~= nil

    if in_fence then
      table.insert(out, line)
      if is_fence(line) then
        in_fence = false
      end
    elseif in_drawer or in_directive then
      table.insert(out, line)

      if in_drawer and is_drawer_end(line) then
        in_drawer = false
      end
      if in_directive and is_directive_end(line) then
        in_directive = false
      end
    elseif not is_blank then
      if is_fence(line) then
        table.insert(out, line)
        in_fence = true
      else
        if should_prefix_bullet(line) then
          local indent, content = line:match '^(%s*)(.*)$'
          line = indent .. '- ' .. vim.trim(content)
        end

        local indent, marker, rest = list_item_parts(line)
        local indent_width = indent and #indent or nil

        if indent_width ~= nil then
          while #parents > 0 and indent_width <= parents[#parents].indent do
            table.remove(parents)
          end

          for i = #parents, 1, -1 do
            local parent = parents[i]
            if indent_width > parent.indent then
              indent_width = parent.child_indent
              line = (' '):rep(indent_width) .. marker .. rest
              break
            end
          end

          if trimmed_ends_with_colon(line) then
            table.insert(parents, {
              indent = indent_width,
              child_indent = indent_width + 2,
            })
          end
        end

        table.insert(out, line)

        if is_drawer_boundary(line) and not is_drawer_end(line) then
          in_drawer = true
        elseif is_directive_start(line) then
          in_directive = true
        end
      end
    end
  end

  return out
end

return M
