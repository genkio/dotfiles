-- One profile per iPhone app. Points are fractions of the mirrored screen (x across, y down), or
-- functions that take the screen size in points and return one. Button keys are hs.keycodes.map
-- names. Hotkeys work only while iPhone Mirroring is frontmost.

-- Diablo II port: the touch layout in d2r-mobile's dm_touch_controls.c.
local d2Main = { x = 0.844, y = 0.788 }

-- Offset from the main button in the game's layout units. One unit measures 0.24% of the screen height.
local function d2Skill(dx, dy)
  return function(screen)
    return { x = d2Main.x + dx * 0.0024 * screen.h / screen.w, y = d2Main.y + dy * 0.0024 }
  end
end

-- The belt sits on a 1320-high mock centred on the screen.
local function d2Belt(column)
  return function(screen)
    local u = screen.h / 1320
    return { x = 0.5 + (120 * column - 344) * u / screen.w, y = 1241.5 / 1320 }
  end
end

return {
  toggle = { { "ctrl", "alt" }, "m" },
  nextProfile = { { "ctrl", "alt" }, "p" },

  profiles = {
    {
      name = "Diablo II",
      -- Floating stick: press inside the lower-left zone and drag. Reach is a fraction of the
      -- screen width; full deflection is 60 phone points, about 7%.
      stick = { x = 0.25, y = 0.70, reach = 0.10 },
      buttons = {
        ["`"] = d2Main,
        ["1"] = d2Skill(-96, 18),
        ["2"] = d2Skill(-84, -50),
        ["3"] = d2Skill(-34, -92),
        ["4"] = d2Skill(34, -92),
        q = d2Belt(1),
        w = d2Belt(2),
        e = d2Belt(3),
        r = d2Belt(4),
      },
    },
  },
}
