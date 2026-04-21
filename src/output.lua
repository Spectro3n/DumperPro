return function(D)
local M = {}
D.Output = M
local C = D.Core

local function w(path, data) C.writeFile(path, data) end

-- ══════════════════════════════════
--  REMOTE GUIDE v2 — DETAILED
-- ══════════════════════════════════

local function getRemoteUsage(r)
    if r.class == "RemoteEvent" then
        return r.path..":FireServer(args...)"
    elseif r.class == "RemoteFunction" then
        return "local result = "..r.path..":InvokeServer(args...)"
    elseif r.class == "UnreliableRemoteEvent" then
        return r.path..":FireServer(args...)  -- unreliable/UDP"
    elseif r.class == "BindableEvent" then
        return r.path..":Fire(args...)"
    elseif r.class == "BindableFunction" then
        return "local result = "..r.path..":Invoke(args...)"
    end
    return r.path..":Fire()"
end

local function getRemoteDescription(r)
    local desc = {}
    if r.class == "RemoteEvent" then
        desc[#desc+1] = "-- │ Type: RemoteEvent — client→server one-way communication"
        desc[#desc+1] = "-- │ Client calls :FireServer(...) to send data to the server."
        desc[#desc+1] = "-- │ Server receives via .OnServerEvent:Connect(function(player, ...) end)"
        desc[#desc+1] = "-- │ Server can fire back via :FireClient(player, ...) or :FireAllClients(...)"
    elseif r.class == "RemoteFunction" then
        desc[#desc+1] = "-- │ Type: RemoteFunction — client↔server two-way request/response"
        desc[#desc+1] = "-- │ Client calls :InvokeServer(...) → waits for server response."
        desc[#desc+1] = "-- │ Server handles via .OnServerInvoke = function(player, ...) return ... end"
        desc[#desc+1] = "-- │ ⚠ InvokeServer YIELDS — the client thread pauses until server responds."
    elseif r.class == "UnreliableRemoteEvent" then
        desc[#desc+1] = "-- │ Type: UnreliableRemoteEvent — fast but lossy UDP communication"
        desc[#desc+1] = "-- │ Same as RemoteEvent but uses UDP — packets may be dropped."
        desc[#desc+1] = "-- │ Used for high-frequency data (positions, rotations) where loss is OK."
        desc[#desc+1] = "-- │ Smaller payload limit than regular RemoteEvent."
    elseif r.class == "BindableEvent" then
        desc[#desc+1] = "-- │ Type: BindableEvent — same-context (client↔client) event"
        desc[#desc+1] = "-- │ Fire with :Fire(...), listen with .Event:Connect(function(...) end)"
        desc[#desc+1] = "-- │ Does NOT cross client/server boundary — local communication only."
    elseif r.class == "BindableFunction" then
        desc[#desc+1] = "-- │ Type: BindableFunction — same-context request/response"
        desc[#desc+1] = "-- │ Call with :Invoke(...), handle with .OnInvoke = function(...) return ... end"
        desc[#desc+1] = "-- │ Does NOT cross client/server boundary — local communication only."
    end
    return desc
end

local function saveRemoteGuide()
    if #D.S.remotes == 0 then return end

    local cats = {
        RemoteEvent           = {t="REMOTE EVENTS (FireServer)",      items={}, order=1},
        RemoteFunction        = {t="REMOTE FUNCTIONS (InvokeServer)", items={}, order=2},
        UnreliableRemoteEvent = {t="UNRELIABLE REMOTE EVENTS (UDP)",  items={}, order=3},
        BindableEvent         = {t="BINDABLE EVENTS (local)",         items={}, order=4},
        BindableFunction      = {t="BINDABLE FUNCTIONS (local)",      items={}, order=5},
    }
    for _, r in ipairs(D.S.remotes) do
        local cat = cats[r.class]
        if cat then cat.items[#cat.items+1] = r end
    end

    local L = {
        "-- ╔══════════════════════════════════════════════════╗",
        "-- ║  ██████╗ ██╗   ██╗███╗   ███╗██████╗ ███████╗  ║",
        "-- ║  ██╔══██╗██║   ██║████╗ ████║██╔══██╗██╔════╝  ║",
        "-- ║  ██║  ██║██║   ██║██╔████╔██║██████╔╝█████╗    ║",
        "-- ║  ██║  ██║██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══╝    ║",
        "-- ║  ██████╔╝╚██████╔╝██║ ╚═╝ ██║██║     ███████╗  ║",
        "-- ║  ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚══════╝  ║",
        "-- ║        REMOTE GUIDE — PRO v14                    ║",
        "-- ╚══════════════════════════════════════════════════╝",
        "-- Game: "..D.cfg.folder,
        "-- Date: "..os.date("%Y-%m-%d %H:%M:%S"),
        "-- Total Remotes: "..#D.S.remotes,
        "",
        "-- ═══════════════════════════════════════════════════",
        "-- HOW TO READ THIS GUIDE:",
        "-- • Each remote shows its full path, type, and usage example",
        "-- • Argument info is inferred from connected handler functions",
        "-- • Connection count shows how many scripts listen to this remote",
        "-- • Constants show string values used inside handler functions",
        "-- ═══════════════════════════════════════════════════",
        "",
    }

    -- Sort categories by order
    local sortedCats = {}
    for _, cat in pairs(cats) do sortedCats[#sortedCats+1] = cat end
    table.sort(sortedCats, function(a,b) return a.order < b.order end)

    for _, cat in ipairs(sortedCats) do
        if #cat.items > 0 then
            L[#L+1] = "-- ╔═══════════════════════════════════════════════╗"
            L[#L+1] = "-- ║ "..cat.t.." ("..#cat.items..")"
            L[#L+1] = "-- ╚═══════════════════════════════════════════════╝"
            L[#L+1] = ""

            for ri, r in ipairs(cat.items) do
                L[#L+1] = "-- ┌─────────────────────────────────────────────────"
                L[#L+1] = "-- │ #"..ri.." "..r.class..': "'..r.name..'"'
                L[#L+1] = "-- │ Path: "..r.path
                L[#L+1] = "-- │ Parent: "..r.parent
                L[#L+1] = "-- │"

                -- Type description
                local descLines = getRemoteDescription(r)
                for _, dl in ipairs(descLines) do L[#L+1] = dl end
                L[#L+1] = "-- │"

                -- Usage
                L[#L+1] = "-- │ ► HOW TO USE:"
                L[#L+1] = "-- │   "..getRemoteUsage(r)
                L[#L+1] = "-- │"

                -- Argument info from callbacks
                if #r.callbacks > 0 then
                    L[#L+1] = "-- │ ► CALLBACKS/HANDLERS: "..#r.callbacks
                    for _, cb in ipairs(r.callbacks) do
                        L[#L+1] = "-- │   ["..cb.name.."] type="..cb.type
                        if cb.numParams then
                            L[#L+1] = "-- │     Arguments: "..cb.numParams..(cb.isVararg and " + varargs (...)" or "")
                            -- Generate argument placeholders
                            local argStr = {}
                            for ai = 1, cb.numParams do argStr[ai] = "arg"..ai end
                            if cb.isVararg then argStr[#argStr+1] = "..." end
                            L[#L+1] = "-- │     Signature: function("..table.concat(argStr, ", ")..")"
                        end
                        if cb.constants and #cb.constants > 0 then
                            L[#L+1] = "-- │     Constants used: "..table.concat(cb.constants, ", "):sub(1,200)
                            -- Infer argument types from constants
                            local hasTypeOf = false
                            local hasToNumber = false
                            for _, c in ipairs(cb.constants) do
                                if c == "typeof" or c == "type" then hasTypeOf = true end
                                if c == "tonumber" then hasToNumber = true end
                            end
                            if hasTypeOf then
                                L[#L+1] = "-- │     ⚡ Handler uses type-checking (typeof/type)"
                            end
                            if hasToNumber then
                                L[#L+1] = "-- │     ⚡ Handler converts to number (tonumber)"
                            end
                        end
                    end
                    L[#L+1] = "-- │"
                end

                -- Connection count
                if r.connectionCount and r.connectionCount > 0 then
                    L[#L+1] = "-- │ ► ACTIVE CONNECTIONS: "..r.connectionCount
                    L[#L+1] = "-- │"
                end

                L[#L+1] = "-- └─────────────────────────────────────────────────"
                L[#L+1] = ""
            end
        end
    end

    w(D.S.rootDir.."/RemoteGuide.lua", table.concat(L,"\n"))
    D.UI:Log("Saved RemoteGuide.lua ("..#D.S.remotes.." remotes, detailed)", "green")
end

-- ══ HOOKS — enhanced ══
local function saveHooks()
    if #D.S.hooks == 0 then return end
    local L = {
        "╔══════════════════════════════════════════════════╗",
        "║  HOOK ANALYSIS — Dumper Pro v14                  ║",
        "║  "..#D.S.hooks.." hooks detected                            ║",
        "║  "..os.date("%Y-%m-%d %H:%M:%S").."                           ║",
        "╚══════════════════════════════════════════════════╝",
        "",
    }

    -- Group by status
    local hooked, original, unknown = {}, {}, {}
    for _, h in ipairs(D.S.hooks) do
        if h.status == "HOOKED" then hooked[#hooked+1] = h
        elseif h.status == "original" then original[#original+1] = h
        else unknown[#unknown+1] = h end
    end

    if #hooked > 0 then
        L[#L+1] = "══ ⚠ HOOKED ("..#hooked..") — These have been modified ══"
        L[#L+1] = ""
        for _, h in ipairs(hooked) do
            L[#L+1] = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            L[#L+1] = "Type:    "..h.type
            L[#L+1] = "Status:  ⚠ HOOKED"
            L[#L+1] = "Detail:  "..h.detail
            if h.scriptSource then L[#L+1] = "Script:  "..h.scriptSource end
            if h.wrappedOriginal then L[#L+1] = "Wraps:   "..h.wrappedOriginal end
            if h.debugInfo then
                local di = h.debugInfo
                if di.name then L[#L+1] = "FuncName: "..di.name end
                if di.source then L[#L+1] = "Source:   "..di.source end
                if di.numParams then L[#L+1] = "Params:   "..di.numParams end
                if di.lineStart then L[#L+1] = "Lines:    "..di.lineStart.."-"..(di.lineEnd or "?") end
            end
            if h.constants then L[#L+1] = "Consts:  "..table.concat(h.constants,", ") end
            if h.upvalues then
                L[#L+1] = "Upvalues:"
                for _, uv in ipairs(h.upvalues) do L[#L+1] = "  "..uv end
            end
            if h.source then L[#L+1] = "Source:\n"..h.source end
            L[#L+1] = ""
        end
    end

    if #original > 0 then
        L[#L+1] = "══ ✓ ORIGINAL ("..#original..") — Not modified ══"
        L[#L+1] = ""
        for _, h in ipairs(original) do
            L[#L+1] = "  ✓ "..h.type.." — "..h.detail
        end
        L[#L+1] = ""
    end

    if #unknown > 0 then
        L[#L+1] = "══ ? UNKNOWN ("..#unknown..") ══"
        L[#L+1] = ""
        for _, h in ipairs(unknown) do
            L[#L+1] = "  ? "..h.type.." — "..h.detail
            if h.source then L[#L+1] = "    Source:\n"..h.source end
        end
        L[#L+1] = ""
    end

    w(D.S.rootDir.."/HookAnalysis.txt", table.concat(L,"\n"))
    D.UI:Log("Saved HookAnalysis.txt ("..#hooked.." hooked, "..#original.." original)", "green")
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
    L[#L+1] = "DUMPER PRO v14 — REPORT"
    L[#L+1] = "═══════════════════════════"
    L[#L+1] = ""
    L[#L+1] = "Game:    "..D.cfg.folder
    L[#L+1] = "PlaceId: "..game.PlaceId
    L[#L+1] = "Version: "..tostring(game.PlaceVersion)
    L[#L+1] = "JobId:   "..game.JobId
    L[#L+1] = "Date:    "..os.date("%Y-%m-%d %H:%M:%S")
    L[#L+1] = "Player:  "..C.LP.Name
    L[#L+1] = "Mode:    "..(D.cfg.mode or "normal")
    L[#L+1] = "Memory:  "..C.getMemMB().."MB"
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
        "-- DUMPER PRO v14 — SINGLE FILE",
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