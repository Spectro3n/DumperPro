--[[
    DUMPER PRO v13 — Loader (Optimized)
]]

local BASE = "https://raw.githubusercontent.com/Spectro3n/DumperPro/main/src/"

local ok, err = pcall(function()
    loadstring(game:HttpGet(BASE .. "init.lua"))(BASE)
end)

if not ok then
    warn("[DumperPro] Fatal: " .. tostring(err))
end