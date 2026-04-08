--[[
    DUMPER PRO v13 — Loader
    ALL scanners active in ALL modes.
    Safe = crash-proof. Turbo = max speed. Same coverage.
]]

local BASE = "https://raw.githubusercontent.com/Spectro3n/DumperPro/main/src/"

local ok, err = pcall(function()
    loadstring(game:HttpGet(BASE .. "init.lua"))(BASE)
end)

if not ok then
    warn("[DumperPro] Fatal: " .. tostring(err))
end