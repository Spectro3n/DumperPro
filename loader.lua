--[[
    DUMPER PRO v14 — Loader
    Game freeze + anti-crash + deep discovery + 11 decompile strategies
    Safe = crash-proof. Turbo = max speed. Same coverage.
]]

local BASE = "https://raw.githubusercontent.com/Spectro3n/DumperPro/main/src/"

local ok, err = pcall(function()
    loadstring(game:HttpGet(BASE .. "init.lua"))(BASE)
end)

if not ok then
    warn("[DumperPro] Fatal: " .. tostring(err))
end