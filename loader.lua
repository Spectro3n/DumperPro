--[[
    DUMPER PRO v13 — Loader
    Execute este script para iniciar.
    
    Estrutura:
    src/init.lua → src/core.lua → src/decompile.lua
                 → src/collect.lua → src/hooks.lua → src/output.lua
]]

local BASE = "https://raw.githubusercontent.com/Spectro3n/DumperPro/main/src/"

local ok, err = pcall(function()
    loadstring(game:HttpGet(BASE .. "init.lua"))(BASE)
end)

if not ok then
    warn("[DumperPro] Fatal: " .. tostring(err))
end