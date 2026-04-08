return function(D)
local M = {}
D.Output = M
local C = D.Core

local function w(path, data) C.writeFile(path, data) end

-- ══ REMOTE GUIDE ══
local function saveRemoteGuide()
    if #D.S.remotes == 0 then return end
    local cats = {
        RemoteEvent           = {t="REMOTE EVENTS (FireServer)",      items={}},
        RemoteFunction        = {t="REMOTE FUNCTIONS (InvokeServer)", items={}},
        UnreliableRemoteEvent = {t="UNRELIABLE REMOTE EVENTS",        items={}},
        BindableEvent         = {t="BINDABLE EVENTS",                 items={}},
        BindableFunction      = {t="BINDABLE FUNCTIONS",              items={}},
    }
    for _, r in ipairs(D.S.remotes) do
        local cat = cats[r.class]
        if cat then cat.items[#cat.items+1] = r end
    end
    local L = {
        "-- ╔════════════════════════════════════╗",
        "-- ║   REMOTE GUIDE — Dumper Pro v13    ║",
        "-- ║   "..D.cfg.folder,
        "-- ║   "..os.date("%Y-%m-%d %H:%M:%S"),
        "-- ║   Total: "..#D.S.remotes,
        "-- ╚════════════════════════════════════╝","",
    }
    for _, cat in pairs(cats) do
        if #cat.items > 0 then
            L[#L+1] = "-- ══ "..cat.t.." ("..#cat.items..") ══"
            L[#L+1] = ""
            for _, r in ipairs(cat.items) do
                L[#L+1] = "-- ┌ "..r.name
                L[#L+1] = "-- │ Path: "..r.path
                L[#L+1] = "-- │ Parent: "..r.parent
                if r.class=="RemoteEvent" then
                    L[#L+1] = "-- │ ► "..r.path..":FireServer()"
                elseif r.class=="RemoteFunction" then
                    L[#L+1] = "-- │ ► local r = "..r.path..":InvokeServer()"
                end
                if #r.callbacks > 0 then
                    for _, cb in ipairs(r.callbacks) do
                        L[#L+1] = "-- │   ["..cb.name.."] "..cb.type
                    end
                end
                L[#L+1] = "-- └───────────────────"
                L[#L+1] = ""
            end
        end
    end
    w(D.S.rootDir.."/RemoteGuide.lua", table.concat(L,"\n"))
    D.UI:Log("Saved RemoteGuide.lua ("..#D.S.remotes..")", "green")
end

-- ══ HOOKS ══
local function saveHooks()
    if #D.S.hooks == 0 then return end
    local L = {"HOOK ANALYSIS — "..#D.S.hooks.." found",""}
    for _, h in ipairs(D.S.hooks) do
        L[#L+1] = "━━━━━━━━━━━━━━━━━━━"
        L[#L+1] = "Type:   "..h.type
        L[#L+1] = "Status: "..h.status
        L[#L+1] = "Detail: "..h.detail
        if h.scriptSource then L[#L+1] = "Script: "..h.scriptSource end
        if h.constants then L[#L+1] = "Consts: "..table.concat(h.constants,", ") end
        if h.source then L[#L+1] = "Source:\n"..h.source end
        L[#L+1] = ""
    end
    w(D.S.rootDir.."/HookAnalysis.txt", table.concat(L,"\n"))
    D.UI:Log("Saved HookAnalysis.txt", "green")
end

-- ══ CONNECTIONS ══
local function saveConnections()
    if #D.S.connections == 0 then return end
    local L = {"CONNECTIONS ("..#D.S.connections..")",""}
    local bySignal, order = {}, {}
    for _, c in ipairs(D.S.connections) do
        if not bySignal[c.signal] then bySignal[c.signal]={}; order[#order+1]=c.signal end
        bySignal[c.signal][#bySignal[c.signal]+1] = c
    end
    for _, sig in ipairs(order) do
        local conns = bySignal[sig]
        L[#L+1] = "── "..sig.." ("..#conns..") ──"
        for _, c in ipairs(conns) do
            local disp = c.script or "unknown"
            if c.scriptName and c.scriptName~="unknown" and c.scriptName~=c.script then
                disp = disp.." ["..c.scriptName.."]"
            end
            if c.scriptClass and c.scriptClass~="?" then
                disp = disp.." ("..c.scriptClass..")"
            end
            L[#L+1] = "  ["..c.funcType.."] "..disp..(c.enabled and "" or " (OFF)")
        end
        L[#L+1] = ""
    end
    w(D.S.rootDir.."/Connections.txt", table.concat(L,"\n"))
    D.UI:Log("Saved Connections.txt", "green")
end

-- ══ ERRORS ══
local function saveErrors()
    if #D.S.scanErrors == 0 then return end
    local L = {"SCAN ERRORS ("..#D.S.scanErrors..")",""}
    for _, e in ipairs(D.S.scanErrors) do
        L[#L+1] = "["..e.section.."] "..(e.signal or "").." — "..(e.error or "?")
    end
    w(D.S.rootDir.."/ScanErrors.txt", table.concat(L,"\n"))
    D.UI:Log("Saved ScanErrors.txt ("..#D.S.scanErrors..")", "yellow")
end

-- ══ SKIPPED ══
local function saveSkipped()
    if #D.S.skipped == 0 then return end
    local L = {"SKIPPED ("..#D.S.skipped..")",""}
    local byR = {}
    for _, s in ipairs(D.S.skipped) do
        if not byR[s.reason] then byR[s.reason]={} end
        byR[s.reason][#byR[s.reason]+1] = s
    end
    for reason, list in pairs(byR) do
        L[#L+1] = "── "..reason:upper().." ("..#list..") ──"
        for _, s in ipairs(list) do
            L[#L+1] = "  ["..s.class.."] "..s.path.." (via "..s.from..")"
        end
        L[#L+1] = ""
    end
    w(D.S.rootDir.."/Skipped.txt", table.concat(L,"\n"))
    D.UI:Log("Saved Skipped.txt ("..#D.S.skipped..")", "yellow")
end

-- ══ UI TREE ══
local function saveUITree()
    if not D.cfg.dumpUI then return end
    pcall(function()
        local pg = C.LP:FindFirstChild("PlayerGui")
        if not pg then return end
        local L = {"UI TREE",""}
        local function walk(obj,depth)
            if depth>25 then return end
            local info = string.rep("  ",depth).."["..obj.ClassName.."] "..obj.Name
            pcall(function() if obj:IsA("GuiObject") then info=info.." V="..tostring(obj.Visible) end end)
            pcall(function()
                if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                    info=info.." T="..tostring(obj.Text):sub(1,40)
                end
            end)
            L[#L+1] = info
            pcall(function() for _,c in ipairs(obj:GetChildren()) do walk(c,depth+1) end end)
        end
        walk(pg,0)
        w(D.S.rootDir.."/UITree.txt", table.concat(L,"\n"))
        D.UI:Log("Saved UITree.txt", "green")
    end)
end

-- ══ GAME INFO ══
local function saveGameInfo()
    if not D.cfg.dumpInfo then return end
    local s = D.S.stats
    local L = {}
    L[#L+1] = "═══════════════════════════"
    L[#L+1] = "DUMPER PRO v13 — REPORT"
    L[#L+1] = "═══════════════════════════"
    L[#L+1] = ""
    L[#L+1] = "Game:    "..D.cfg.folder
    L[#L+1] = "PlaceId: "..game.PlaceId
    L[#L+1] = "Version: "..tostring(game.PlaceVersion)
    L[#L+1] = "JobId:   "..game.JobId
    L[#L+1] = "Date:    "..os.date("%Y-%m-%d %H:%M:%S")
    L[#L+1] = "Player:  "..C.LP.Name
    L[#L+1] = "Mode:    "..(D.cfg.mode or "normal")
    L[#L+1] = "Memory:  "..math.floor(C.getMemKB()/1024).."MB"
    pcall(function() L[#L+1] = "Exec:    "..(identifyexecutor() or "?") end)
    L[#L+1] = ""
    L[#L+1] = "── CAPABILITIES ──"
    for _,n in ipairs(C.PROBES) do
        L[#L+1] = string.format("  %-28s %s", n, D.has[n] and "✓" or "✗")
    end
    L[#L+1] = ""
    L[#L+1] = "── RESULTS ──"
    L[#L+1] = "Total:       "..s.total
    L[#L+1] = "OK:          "..s.ok
    L[#L+1] = "Failed:      "..s.fail
    L[#L+1] = "Skipped:     "..#D.S.skipped
    L[#L+1] = "Aggressive:  "..s.aggressive
    L[#L+1] = "Remotes:     "..s.remotes
    L[#L+1] = "Hooks:       "..s.hooks
    L[#L+1] = "Connections: "..#D.S.connections
    L[#L+1] = "Errors:      "..#D.S.scanErrors
    L[#L+1] = "Time:        "..C.elapsed()
    L[#L+1] = ""
    L[#L+1] = "── CACHE ──"
    L[#L+1] = "Hits:   "..D.S.cacheStats.hits
    L[#L+1] = "Misses: "..D.S.cacheStats.misses
    L[#L+1] = "Dedup:  "..D.S.cacheStats.dedup
    L[#L+1] = "Linked: "..D.S.cacheStats.linked
    L[#L+1] = ""
    L[#L+1] = "── DECOMPILE METHODS ──"
    for m,c in pairs(s.methods) do L[#L+1] = string.format("  %-20s %d",m,c) end
    L[#L+1] = ""
    L[#L+1] = "── DISCOVERY SOURCES ──"
    for m,c in pairs(s.sources) do L[#L+1] = string.format("  %-25s %d",m,c) end
    L[#L+1] = ""
    L[#L+1] = "── MODE LIMITS ──"
    for k,v in pairs(D.limits) do L[#L+1] = string.format("  %-22s %s",k,tostring(v)) end
    if #D.S.scanErrors > 0 then
        L[#L+1] = ""
        L[#L+1] = "── SCAN ERRORS ──"
        for _,e in ipairs(D.S.scanErrors) do
            L[#L+1] = "  ["..e.section.."] "..(e.signal or "").." — "..(e.error or "?"):sub(1,80)
        end
    end
    w(D.S.rootDir.."/GameInfo.txt", table.concat(L,"\n"))
end

-- ══ FAILED ══
local function saveFailed()
    if #D.S.fails == 0 then return end
    w(D.S.rootDir.."/Failed.txt", "FAILED ("..#D.S.fails..")\n\n"..table.concat(D.S.fails,"\n"))
    D.UI:Log("Saved Failed.txt ("..#D.S.fails..")", "yellow")
end

-- ══ SINGLE FILE ══
local function saveSingleFile()
    if not D.S.isSingleFile or #D.S.singleBuffer == 0 then return end
    local header = {
        "-- ═══════════════════════════════════",
        "-- DUMPER PRO v13 — SINGLE FILE",
        "-- Game: "..D.cfg.folder,
        "-- Date: "..os.date("%Y-%m-%d %H:%M:%S"),
        "-- Scripts: "..D.S.stats.ok,
        "-- ═══════════════════════════════════","","",
    }
    w(D.S.rootDir.."/AllScripts.lua", table.concat(header,"\n")..table.concat(D.S.singleBuffer))
    D.UI:Log("Saved AllScripts.lua ("..D.S.stats.ok.." scripts)", "green")
end

-- ══ SAVE ALL ══
function M.saveAll()
    if not D.has.writefile then
        D.UI:Log("writefile unavailable — cannot save", "red")
        return
    end
    D.UI:SetPhase("saving")
    D.UI:Log("Saving reports...", "blue")
    pcall(saveRemoteGuide)
    pcall(saveHooks)
    pcall(saveConnections)
    pcall(saveErrors)
    pcall(saveSkipped)
    pcall(saveUITree)
    pcall(saveGameInfo)
    pcall(saveFailed)
    pcall(saveSingleFile)
    D.UI:Log("All saved to: "..D.S.rootDir.."/", "green")
end

end