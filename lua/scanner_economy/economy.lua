-- Scanner Economy v1.0 - shared code (by Led Icarus)
-- Mixed into the Orbital Scanner and the HQ / Outpost building scripts.
--
-- Once per second the mod reads the planet-wide stock of each mineral and keeps
-- the last 60 s of readings; net rate = change in stock / time. Compressed
-- liquids are flows (per-second figures), not stock.
--
-- NOTE: PlayerService:GetResourceIncome crashes the game natively, never call it.

local SE = {}

local TAG       = "[ScannerEconomy] "
local VERSION   = "v1.0"
local WINDOW    = 60          -- seconds of history used for rates
local HUD_ID    = "scanner_economy"
local POPUP_GUI = "gui/popup/scanner_economy"

local MINERALS = {
    { "carbonium",   "Carbonium", "carbonium" },
    { "steel",       "Ironium", "ironium" },        -- internal id of Ironium
    { "cobalt",      "Cobalt", "cobalt" },
    { "palladium",   "Palladium", "palladium" },
    { "titanium",    "Titanium", "titanium" },
    { "uranium_ore", "Crude uranium", "uranium_ore" },
    { "uranium",     "Uranium", "uranium" },
}
local LIQUIDS = {
    { "water",          "Water", "water_vein" },
    { "sludge",         "Sludge", "sludge_vein" },
    { "mud",            "Mud", "mud_vein" },
    { "morphium",       "Morphium", "morphium_vein" },
    { "magma",          "Magma", "magma" },
    { "flammable_gas",  "Flammable gas", "flammable_gas" },
    { "supercoolant",   "Supercoolant", "super_coolant" },
    { "plasma",         "Plasma", "plasma" },
    { "plasma_charged", "Charged plasma", "supercharged_plasma" },
    { "resin",          "Resin", "resin" },
}

-- Compressed liquids are planet-wide resources named "<liquid>_compressed";
-- this is what the Liquid Decompressor shows as "available".
local LIQUIDS_C = {}
for _, r in ipairs(LIQUIDS) do
    LIQUIDS_C[#LIQUIDS_C + 1] = { r[1] .. "_compressed", r[2], r[3] }
end

local function SafeLimit(player, id)
    local ok, v = pcall(function() return PlayerService:GetResourceLimit(player, id) end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function Log(msg)
    pcall(function() LogService:Log(TAG .. tostring(msg)) end)
end

local function SafeAmount(player, id)
    local ok, v = pcall(function() return PlayerService:GetResourceAmount(player, id) end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function FmtAmount(v)
    if v == nil then return "n/a" end
    if v == 0 then return "0" end
    local a = math.abs(v)
    if a >= 1000000 then return string.format("%.2fM", v / 1000000) end
    if a >= 1000    then return string.format("%.1fK", v / 1000) end
    return string.format("%.0f", v)
end

local function FmtRate(v)
    if v == nil then return "--" end
    if math.abs(v) < 0.005 then return "0/s" end
    local sign = v > 0 and "+" or "-"
    local a = math.abs(v)
    if a >= 100 then return sign .. string.format("%.0f/s", a) end
    if a >= 10  then return sign .. string.format("%.1f/s", a) end
    return sign .. string.format("%.2f/s", a)
end

local function Styled(rate, text)
    if rate == nil or math.abs(rate) < 0.005 then return text end
    if rate > 0 then return '<style="resource_green">' .. text .. '</style>' end
    return '<style="resource_red">' .. text .. '</style>'
end

local function Row(player, self, r)
    local amount = SafeAmount(player, r[1])
    local rate = self:SE_Rate(r[1])
    local limit = SafeLimit(player, r[1])
    local text = '<img="gui/hud/resource_icons/' .. r[3] .. '"> ' .. r[2] .. ":  " .. FmtAmount(amount)
    if limit ~= nil and limit > 0 and amount ~= nil and amount >= limit - 0.5 then
        text = text .. '  <style="resource_yellow">FULL</style>  ' .. Styled(rate, FmtRate(rate)) .. " (capped)"
    else
        text = text .. "   " .. Styled(rate, FmtRate(rate))
    end
    return text, amount, rate
end

function SE:SE_Setup()
    self.se_history = {}
    self.se_time    = 0
    self.se_hudLeft = 10
    pcall(function()
        GuiService:HideHudText(HUD_ID)
        GuiService:ShowHudText(HUD_ID, "Scanner Economy " .. VERSION .. " loaded")
    end)
    if self.se_fsm == nil then
        self.se_fsm = self:CreateStateMachine()
        self.se_fsm:AddState( "sample", { execute="SE_SampleExecute", interval=1.0 } )
        self.se_fsm:ChangeState("sample")
    end
end

function SE:SE_SampleExecute( state, dt )
    local ok, err = pcall(function()
        dt = dt or 1.0
        self.se_time = (self.se_time or 0) + dt
        local player = PlayerService:GetLeadingPlayer()
        local snap = { t = self.se_time, v = {} }
        for _, r in ipairs(MINERALS) do snap.v[r[1]] = SafeAmount(player, r[1]) end
        for _, r in ipairs(LIQUIDS_C) do snap.v[r[1]] = SafeAmount(player, r[1]) end
        local h = self.se_history
        h[#h + 1] = snap
        while #h > 1 and (self.se_time - h[1].t) > WINDOW do
            table.remove(h, 1)
        end

        if self.se_hudLeft and self.se_hudLeft > 0 then
            self.se_hudLeft = self.se_hudLeft - dt
            if self.se_hudLeft <= 0 then GuiService:HideHudText(HUD_ID) end
        end
    end)
    if not ok and not self.se_loggedSampleError then
        self.se_loggedSampleError = true
        Log("Sample error: " .. tostring(err))
    end
end

function SE:SE_Rate(id)
    local h = self.se_history
    if h == nil or #h < 2 then return nil end
    local a, b = h[1], h[#h]
    local dt = b.t - a.t
    if dt <= 0 or a.v[id] == nil or b.v[id] == nil then return nil end
    return (b.v[id] - a.v[id]) / dt
end

---------------------------------------------------------------------------
-- panel
---------------------------------------------------------------------------
function SE:SE_BuildText()
    local player = PlayerService:GetLeadingPlayer()
    local secs = 0
    if self.se_history and #self.se_history > 1 then
        secs = math.floor(self.se_history[#self.se_history].t - self.se_history[1].t)
    end

    local lines = {}
    lines[#lines + 1] = "<style=\"resource_max\">GLOBAL ECONOMY</style>"
    if secs < 10 then
        lines[#lines + 1] = "Still measuring (" .. secs .. "s of data) - rates need ~10s or more"
    else
        lines[#lines + 1] = "Net change per second, averaged over the last " .. secs .. "s"
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "<style=\"resource_max\">MINERALS (all outposts)</style>"
    for _, r in ipairs(MINERALS) do
        local text = Row(player, self, r)
        lines[#lines + 1] = text
    end

    -- Compressed liquids are flows. GetResourceLimit = total compressed per
    -- second (matches the Decompressor's "Compressed" column); GetResourceAmount
    -- = a buffer that fills up to that limit ("Full storage" when it is full).
    -- The per-decompressor "In use" figure is not exposed to Lua.
    local liq = {}
    for _, r in ipairs(LIQUIDS_C) do
        local amount = SafeAmount(player, r[1])
        local limit  = SafeLimit(player, r[1])
        if limit ~= nil and limit > 0 then
            local text = '<img="gui/hud/resource_icons/' .. r[3] .. '"> ' .. r[2] .. ":  "
                .. '<style="resource_green">+' .. FmtAmount(limit) .. "/s</style> compressed"
            if amount ~= nil then
                local pct = math.floor(100 * amount / limit + 0.5)
                if amount >= limit - 0.5 then
                    text = text .. '   <style="resource_yellow">buffer FULL</style>'
                else
                    text = text .. "   buffer " .. pct .. "%"
                end
            end
            liq[#liq + 1] = text
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "<style=\"resource_max\">COMPRESSED LIQUIDS (all outposts)</style>"
    if #liq == 0 then
        lines[#lines + 1] = "no liquid compressors running"
    else
        for _, l in ipairs(liq) do lines[#lines + 1] = l end
    end
    return table.concat(lines, "\r\n")
end

function SE:SE_OpenPanel()
    local text = self:SE_BuildText()
    Log("Opening panel:\r\n" .. text)
    GuiService:OpenPopup(self.entity, POPUP_GUI, text)
end


function SE:SE_SafeOpenPanel()
    local ok, err = pcall(function() self:SE_OpenPanel() end)
    if not ok then
        Log("OpenPanel error: " .. tostring(err))
        pcall(function()
            GuiService:HideHudText(HUD_ID)
            GuiService:ShowHudText(HUD_ID, "Scanner Economy error: " .. tostring(err))
        end)
        self.se_hudLeft = 15
    end
end

-- copy every SE_ method onto a building class
function SE.Mixin(cls)
    for k, v in pairs(SE) do
        if type(k) == "string" and string.sub(k, 1, 3) == "SE_" then cls[k] = v end
    end
end

return SE
