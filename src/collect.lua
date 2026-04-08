return function(D)
local M = {}
D.Collect = M
local C, has = D.Core, D.has

-- helper: current mode
local function mode() return D.cfg.mode or "normal" end
local function isTurbo() return mode() == "turbo" end
local function isSafe() return mode() == "safe" end

-- ══════════════════════════════════
--  SCAN SERVICE
-- ══════════════════════════════════

local function scanService(svcName)
    if D.S.cancel then return end
    C.safeScan("Svc:"..svcName, function()
        local svc = game:GetService(svcName)
        D.UI:Log("  → "..svcName, "gray")

        if svcName == "Workspace" then
            local ok, ch = pcall(function() return svc:GetChildren() end)
            if not ok or not ch then return end
            for ci, child in ipairs(ch) do
                if D.S.cancel then return end
                pcall(function()
                    if C.isScript(child) then C.enqueue(child, "Workspace") end
                    C.checkRemote(child)
                end)
                local ok2, desc = pcall(function() return child:GetDescendants() end)
                if ok2 and desc then
                    C.processObjList(desc, "Workspace", D.limits.maxDescendants)
                    desc = nil
                end
                -- Turbo: yield less often; Safe: yield every child
                if isTurbo() then
                    if ci % 15 == 0 then C.yieldNow() end
                elseif isSafe() then
                    C.yieldNow()
                    if ci % 3 == 0 then pcall(collectgarbage, "step", D.limits.gcStepSize) end
                else
                    if ci % 6 == 0 then C.yieldNow(); pcall(collectgarbage, "step", 60) end
                end
            end
            ch = nil
        else
            local ok, desc = pcall(function() return svc:GetDescendants() end)
            if ok and desc then
                C.processObjList(desc, svcName, D.limits.maxDescendants)
                desc = nil
            end
        end
    end)
end

-- ══════════════════════════════════
--  CHARACTERS
-- ══════════════════════════════════

local function scanCharacters()
    D.UI:Log("  → Characters", "orange")
    C.safeScan("PlayerChars", function()
        for _, p in ipairs(C.Players:GetPlayers()) do
            if D.S.cancel then break end
            pcall(function()
                local char = p.Character
                if not char then return end
                local ok, desc = pcall(function() return char:GetDescendants() end)
                if ok and desc then C.processObjList(desc, "Char."..p.Name); desc = nil end
            end)
            C.tick()
        end
    end)

    local containers = {
        "Characters","Chars","PlayerCharacters","Entities","NPCs",
        "Mobs","Models","Units","Actors","Avatars","PlayerModels",
    }
    C.safeScan("Containers", function()
        local roots = {}
        pcall(function() roots[#roots+1] = workspace end)
        pcall(function() roots[#roots+1] = game:GetService("ReplicatedStorage") end)
        pcall(function() roots[#roots+1] = game:GetService("ReplicatedFirst") end)
        for _, root in ipairs(roots) do
            for _, name in ipairs(containers) do
                if D.S.cancel then return end
                pcall(function()
                    local c = root:FindFirstChild(name)
                    if c then
                        D.UI:Log("    Found: "..C.safeName(c), "gray")
                        local ok, desc = pcall(function() return c:GetDescendants() end)
                        if ok and desc then C.processObjList(desc, "Container."..name); desc = nil end
                    end
                end)
            end
        end
    end)

    -- Safe: skip workspace humanoid scan (heavy)
    if not isSafe() then
        C.safeScan("HumanoidModels", function()
            local ok, ch = pcall(function() return workspace:GetChildren() end)
            if not ok or not ch then return end
            for ci, child in ipairs(ch) do
                if D.S.cancel then break end
                pcall(function()
                    if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
                        local ok2, desc = pcall(function() return child:GetDescendants() end)
                        if ok2 and desc then C.processObjList(desc, "HModel."..child.Name); desc = nil end
                    end
                end)
                C.tick()
            end
            ch = nil
        end)
    end

    C.safeScan("StarterCharScripts", function()
        pcall(function()
            local scs = game:GetService("StarterPlayer"):FindFirstChild("StarterCharacterScripts")
            if scs then
                local ok, desc = pcall(function() return scs:GetDescendants() end)
                if ok and desc then C.processObjList(desc, "StarterCharScripts"); desc = nil end
            end
        end)
    end)
end

-- ══════════════════════════════════
--  PLAYER TREE
-- ══════════════════════════════════

local function scanPlayerTree()
    if not C.LP then return end
    C.safeScan("PlayerTree", function()
        D.UI:Log("  → Player tree", "gray")
        for _, cn in ipairs({"PlayerGui","PlayerScripts","Backpack","StarterGear"}) do
            if D.S.cancel then break end
            pcall(function()
                local c = C.LP:FindFirstChild(cn)
                if c then
                    local ok, desc = pcall(function() return c:GetDescendants() end)
                    if ok and desc then C.processObjList(desc, "Player."..cn); desc = nil end
                end
            end)
            C.tick()
        end
        pcall(function()
            if C.LP.Character then
                local ok, desc = pcall(function() return C.LP.Character:GetDescendants() end)
                if ok and desc then C.processObjList(desc, "LP.Char"); desc = nil end
            end
        end)
    end)
end

-- ══════════════════════════════════
--  BASIC SOURCES
-- ══════════════════════════════════

local function scanBasicSources()
    if not D.S.cancel and has.getscripts then
        C.safeScan("getscripts", function()
            D.UI:Log("  → getscripts()", "orange")
            local s = getscripts(); C.processObjList(s, "getscripts"); s = nil
        end)
    end
    if not D.S.cancel and D.cfg.scanRunning and has.getrunningscripts then
        C.safeScan("running", function()
            D.UI:Log("  → getrunningscripts()", "orange")
            local s = getrunningscripts(); C.processObjList(s, "running"); s = nil
        end)
    end
    if not D.S.cancel and D.cfg.scanLoaded and has.getloadedmodules then
        C.safeScan("loaded", function()
            D.UI:Log("  → getloadedmodules()", "orange")
            local m = getloadedmodules(); C.processObjList(m, "loaded"); m = nil
        end)
    end
end

-- ══════════════════════════════════
--  NIL INSTANCES (shallow)
-- ══════════════════════════════════

local function scanNil()
    if not D.cfg.scanNil or not has.getnilinstances then return end
    C.safeScan("nil", function()
        D.UI:Log("  → getnilinstances()", "orange")
        local nils = getnilinstances()
        D.UI:Log("    "..#nils.." nil objects", "gray")

        local maxDepth = isSafe() and 1 or (isTurbo() and 3 or 2)

        for i = 1, #nils do
            if D.S.cancel then break end
            pcall(function()
                local obj = nils[i]
                if C.isScript(obj) then C.enqueue(obj, "nil") end
                C.checkRemote(obj)
                if maxDepth >= 1 then
                    pcall(function()
                        for _, ch in ipairs(obj:GetChildren()) do
                            if C.isScript(ch) then C.enqueue(ch, "nil_c1") end
                            C.checkRemote(ch)
                            if maxDepth >= 2 then
                                pcall(function()
                                    for _, gc in ipairs(ch:GetChildren()) do
                                        if C.isScript(gc) then C.enqueue(gc, "nil_c2") end
                                    end
                                end)
                            end
                        end
                    end)
                end
            end)
            C.tick()
            -- Safe: extra memory check
            if isSafe() and i % D.limits.memCheckEvery == 0 then
                if not C.memoryGuard() then break end
            end
        end
        nils = nil
    end)
end

-- ══════════════════════════════════
--  CONNECTION → SCRIPTS
-- ══════════════════════════════════

local function scanConnScripts()
    if D.limits.skipConnSpy then return end
    if not D.cfg.scanConn or not has.getconnections then return end
    C.safeScan("ConnScripts", function()
        D.UI:Log("  → connection scripts", "orange")
        local sigs = {}
        pcall(function() sigs[#sigs+1] = C.Run.Heartbeat end)
        pcall(function() sigs[#sigs+1] = C.Run.Stepped end)
        pcall(function() sigs[#sigs+1] = C.UIS.InputBegan end)
        pcall(function() sigs[#sigs+1] = C.Players.PlayerAdded end)
        for _, sig in ipairs(sigs) do
            if D.S.cancel then break end
            pcall(function()
                local ok, conns = pcall(getconnections, sig)
                if not ok or not conns then return end
                for _, conn in ipairs(conns) do
                    if conn.Function then
                        pcall(function()
                            local e = getfenv(conn.Function)
                            if e then
                                local s = rawget(e, "script")
                                if s and typeof(s) == "Instance" and C.isScript(s) then
                                    C.enqueue(s, "connection")
                                end
                            end
                        end)
                    end
                end
            end)
            C.yieldNow()
        end
    end)
end

-- ══════════════════════════════════
--  REGISTRY
-- ══════════════════════════════════

local function scanRegistry()
    if D.limits.skipRegistry then return end
    if not D.cfg.scanReg then return end
    C.safeScan("Registry", function()
        local reg
        if has.getreg then pcall(function() reg = getreg() end) end
        if not reg then return end
        D.UI:Log("  → registry ("..#reg..")", "orange")
        local limit = math.min(#reg, D.limits.gcLimit)

        if isTurbo() then
            -- Turbo: chunk-based processing
            local chunk = D.limits.chunkProcess
            for start = 1, limit, chunk do
                if D.S.cancel then break end
                pcall(function()
                    local stop = math.min(start + chunk - 1, limit)
                    for i = start, stop do
                        local v = reg[i]
                        if type(v) == "function" then
                            pcall(function()
                                local e = getfenv(v)
                                if e then
                                    local s = rawget(e, "script")
                                    if s and typeof(s) == "Instance" and C.isScript(s) then
                                        C.enqueue(s, "registry")
                                    end
                                end
                            end)
                        elseif type(v) == "table" then
                            pcall(function()
                                local tc = 0
                                for _, v2 in pairs(v) do
                                    tc = tc + 1; if tc > 60 then break end
                                    if typeof(v2) == "Instance" then
                                        if C.isScript(v2) then C.enqueue(v2, "reg_tbl") end
                                        C.checkRemote(v2)
                                    end
                                end
                            end)
                        end
                    end
                end)
                C.tickBulk(chunk)
            end
        else
            for i = 1, limit do
                if D.S.cancel then break end
                pcall(function()
                    local v = reg[i]
                    if type(v) == "function" then
                        pcall(function()
                            local e = getfenv(v)
                            if e then
                                local s = rawget(e, "script")
                                if s and typeof(s) == "Instance" and C.isScript(s) then
                                    C.enqueue(s, "registry")
                                end
                            end
                        end)
                    elseif type(v) == "table" then
                        pcall(function()
                            local tc = 0
                            for _, v2 in pairs(v) do
                                tc = tc + 1; if tc > 40 then break end
                                if typeof(v2) == "Instance" then
                                    if C.isScript(v2) then C.enqueue(v2, "reg_tbl") end
                                    C.checkRemote(v2)
                                end
                            end
                        end)
                    end
                end)
                C.tick()
            end
        end
        reg = nil
    end)
end

-- ══════════════════════════════════
--  GC / INSTANCES / THREADS
-- ══════════════════════════════════

local function testGC()
    if not has.getgc then return false end
    local ok = pcall(function() local t = getgc(false); t = nil end)
    return ok
end

local function scanGC()
    if D.limits.skipGC then return end
    if not D.cfg.scanGC or not testGC() then return end
    C.safeScan("GC", function()
        D.UI:Log("  → getgc() (limit "..D.limits.gcLimit..")", "orange")
        local gc = getgc(true)
        local sz = math.min(#gc, D.limits.gcLimit)

        if isTurbo() then
            local chunk = D.limits.chunkProcess
            for start = 1, sz, chunk do
                if D.S.cancel then break end
                pcall(function()
                    local stop = math.min(start + chunk - 1, sz)
                    for i = start, stop do
                        local v = gc[i]
                        if type(v) == "function" then
                            pcall(function()
                                local e = getfenv(v)
                                if e then
                                    local s = rawget(e, "script")
                                    if s and typeof(s) == "Instance" and C.isScript(s) then
                                        C.enqueue(s, "gc")
                                    end
                                end
                            end)
                        elseif type(v) == "table" and has.getrawmetatable then
                            pcall(function()
                                local mt = getrawmetatable(v)
                                if mt then
                                    local idx = rawget(mt, "__index")
                                    if typeof(idx) == "Instance" and C.isScript(idx) then
                                        C.enqueue(idx, "gc_mt")
                                    end
                                end
                            end)
                        end
                    end
                end)
                C.tickBulk(chunk)
            end
        else
            for i = 1, sz do
                if D.S.cancel then break end
                pcall(function()
                    local v = gc[i]
                    if type(v) == "function" then
                        pcall(function()
                            local e = getfenv(v)
                            if e then
                                local s = rawget(e, "script")
                                if s and typeof(s) == "Instance" and C.isScript(s) then
                                    C.enqueue(s, "gc")
                                end
                            end
                        end)
                    elseif type(v) == "table" and has.getrawmetatable then
                        pcall(function()
                            local mt = getrawmetatable(v)
                            if mt then
                                local idx = rawget(mt, "__index")
                                if typeof(idx) == "Instance" and C.isScript(idx) then
                                    C.enqueue(idx, "gc_mt")
                                end
                            end
                        end)
                    end
                end)
                C.tick()
            end
        end
        gc = nil
        pcall(collectgarbage, "collect")
    end)
end

local function scanInstances()
    if not D.cfg.scanAll or not has.getinstances then return end
    C.safeScan("Instances", function()
        D.UI:Log("  → getinstances()", "orange")
        local all = getinstances()
        local sz = math.min(#all, D.limits.gcLimit)
        C.processObjList(all, "memory", sz)
        all = nil
        pcall(collectgarbage, "collect")
    end)
end

local function scanThreads()
    if D.limits.skipThreads then return end
    if not D.cfg.scanThreads or not has.getgc or not has.getscriptfromthread then return end
    C.safeScan("Threads", function()
        D.UI:Log("  → threads", "orange")
        local gc = getgc(true)
        local sz = math.min(#gc, D.limits.gcLimit)
        for i = 1, sz do
            if D.S.cancel then break end
            if type(gc[i]) == "thread" then
                pcall(function()
                    local s = getscriptfromthread(gc[i])
                    if s and C.isScript(s) then C.enqueue(s, "thread") end
                end)
            end
            C.tick()
        end
        gc = nil
        pcall(collectgarbage, "collect")
    end)
end

-- ══════════════════════════════════
--  ADVANCED: GC Function → Script Map
-- ══════════════════════════════════

local function gcFunctionMap()
    if not testGC() then return end
    local found = 0
    C.safeScan("GCFuncMap", function()
        D.UI:Log("  → gcFunctionMap()", "orange")
        local seen2 = {}
        local gc = getgc(false)
        local sz = math.min(#gc, D.limits.gcLimit)

        local chunk = isTurbo() and 500 or 200
        for start = 1, sz, chunk do
            if D.S.cancel then break end
            pcall(function()
                local stop = math.min(start + chunk - 1, sz)
                for i = start, stop do
                    if type(gc[i]) == "function" then
                        pcall(function()
                            local e = getfenv(gc[i])
                            if not e then return end
                            local s = rawget(e, "script")
                            if s and typeof(s) == "Instance" then
                                local id = tostring(s)
                                if not seen2[id] then
                                    seen2[id] = true
                                    if C.isScript(s) then C.enqueue(s, "gc_funcmap"); found = found + 1 end
                                end
                            end
                        end)
                    end
                end
            end)
            C.tickBulk(chunk)
        end
        gc = nil; seen2 = nil
    end)
    if found > 0 then D.UI:Log("    +"..found.." via funcmap", "green") end
end

-- ══════════════════════════════════
--  ADVANCED: Hidden Locations
-- ══════════════════════════════════

local function hiddenLocationScan()
    local found = 0
    C.safeScan("HiddenLocs", function()
        D.UI:Log("  → hiddenLocations()", "orange")
        local locs = {}
        pcall(function() locs[#locs+1] = {"Camera",   workspace.CurrentCamera} end)
        pcall(function() locs[#locs+1] = {"Terrain",  workspace.Terrain} end)
        pcall(function() locs[#locs+1] = {"CoreGui",  game:GetService("CoreGui")} end)
        pcall(function() locs[#locs+1] = {"Debris",   game:GetService("Debris")} end)
        pcall(function() locs[#locs+1] = {"Tween",    game:GetService("TweenService")} end)
        pcall(function() locs[#locs+1] = {"Content",  game:GetService("ContentProvider")} end)
        pcall(function() locs[#locs+1] = {"Network",  game:GetService("NetworkClient")} end)
        pcall(function() locs[#locs+1] = {"RunSvc",   game:GetService("RunService")} end)

        for _, loc in ipairs(locs) do
            if D.S.cancel then break end
            pcall(function()
                local ok, desc = pcall(function() return loc[2]:GetDescendants() end)
                if ok and desc and #desc > 0 then
                    for _, obj in ipairs(desc) do
                        if C.isScript(obj) then C.enqueue(obj, "hidden."..loc[1]); found = found + 1 end
                        C.checkRemote(obj)
                    end
                    desc = nil
                end
            end)
            C.tick()
        end
    end)
    if found > 0 then D.UI:Log("    +"..found.." hidden", "green") end
end

-- ══════════════════════════════════
--  ADVANCED: CollectionService Tags
-- ══════════════════════════════════

local function collectionServiceScan()
    local found = 0
    C.safeScan("Tags", function()
        D.UI:Log("  → collectionService()", "orange")
        local ok, tags = pcall(function() return C.Tags:GetAllTags() end)
        if not ok or not tags then return end
        D.UI:Log("    "..#tags.." tags", "gray")
        local maxTags = isTurbo() and 600 or 300
        for ti, tag in ipairs(tags) do
            if D.S.cancel or ti > maxTags then break end
            pcall(function()
                local tagged = C.Tags:GetTagged(tag)
                for _, obj in ipairs(tagged) do
                    if C.isScript(obj) then C.enqueue(obj, "tag:"..tag); found = found + 1 end
                end
            end)
            C.tick()
        end
    end)
    if found > 0 then D.UI:Log("    +"..found.." via tags", "green") end
end

-- ══════════════════════════════════
--  ADVANCED: Module Require Trace
-- ══════════════════════════════════

local function moduleRequireTrace()
    if not D.cfg.dumpModule or not has.getloadedmodules or not has.getconstants then return end
    local found = 0
    C.safeScan("RequireTrace", function()
        D.UI:Log("  → moduleRequireTrace()", "orange")
        local mods = getloadedmodules()
        if not mods then return end
        local maxMods = isTurbo() and 800 or 400
        for mi, mod in ipairs(mods) do
            if D.S.cancel or mi > maxMods then break end
            pcall(function()
                local fn
                if has.getscriptclosure then pcall(function() fn = getscriptclosure(mod) end) end
                if not fn then return end
                local ok2, consts = pcall(getconstants, fn)
                if not ok2 or not consts then return end
                local hasReq, paths = false, {}
                for ci, c in ipairs(consts) do
                    if ci > 200 then break end
                    if c == "require" then hasReq = true end
                    if type(c) == "string" and #c > 3 and #c < 120 then
                        if c:find("Module") or c:find("Shared") or c:find("Util")
                           or c:find("Config") or c:find("Manager") or c:find("Controller")
                           or c:find("Service") or c:find("Client") then
                            paths[#paths+1] = c
                        end
                    end
                end
                if hasReq and #paths > 0 then
                    local roots = {}
                    pcall(function() roots[#roots+1] = game:GetService("ReplicatedStorage") end)
                    pcall(function() roots[#roots+1] = mod.Parent end)
                    for _, path in ipairs(paths) do
                        for _, root in ipairs(roots) do
                            pcall(function()
                                local t = root:FindFirstChild(path, true)
                                if t and C.isScript(t) then C.enqueue(t, "require_trace"); found = found + 1 end
                            end)
                        end
                    end
                end
                if has.getupvalues then
                    pcall(function()
                        local ups = getupvalues(fn)
                        if ups then
                            for _, v in pairs(ups) do
                                if typeof(v) == "Instance" and C.isScript(v) then
                                    C.enqueue(v, "mod_upval"); found = found + 1
                                end
                            end
                        end
                    end)
                end
            end)
            C.tick()
        end
        mods = nil
    end)
    if found > 0 then D.UI:Log("    +"..found.." via require trace", "green") end
end

-- ══════════════════════════════════
--  ADVANCED: Deep Upvalue Chain (turbo only)
-- ══════════════════════════════════

local function deepUpvalueChain()
    if not testGC() or not has.getupvalues then return end
    local found, walked = 0, 0
    local maxWalk = D.limits.gcLimit
    local visited = {}

    local function walkFunc(fn, depth)
        if depth > 6 or walked > maxWalk or D.S.cancel then return end
        local id = tostring(fn)
        if visited[id] then return end
        visited[id] = true
        walked = walked + 1

        pcall(function()
            local e = getfenv(fn)
            if e then
                local s = rawget(e, "script")
                if s and typeof(s) == "Instance" and C.isScript(s) then
                    C.enqueue(s, "upval_chain"); found = found + 1
                end
            end
        end)
        pcall(function()
            local ups = getupvalues(fn)
            if not ups then return end
            for _, v in pairs(ups) do
                if typeof(v) == "Instance" and C.isScript(v) then
                    C.enqueue(v, "upval_inst"); found = found + 1
                elseif type(v) == "function" then
                    walkFunc(v, depth + 1)
                elseif type(v) == "table" then
                    local tc = 0
                    for _, tv in pairs(v) do
                        tc = tc + 1; if tc > 15 then break end
                        if typeof(tv) == "Instance" and C.isScript(tv) then
                            C.enqueue(tv, "upval_tbl"); found = found + 1
                        elseif type(tv) == "function" and depth < 3 then
                            walkFunc(tv, depth + 2)
                        end
                    end
                end
            end
        end)
        if walked % 150 == 0 then C.tickBulk(150) end
    end

    C.safeScan("UpvalChain", function()
        D.UI:Log("  → deepUpvalueChain()", "orange")
        local gc = getgc(false)
        local sz = math.min(#gc, maxWalk)
        for i = 1, sz do
            if D.S.cancel or walked > maxWalk then break end
            if type(gc[i]) == "function" then walkFunc(gc[i], 0) end
            if i % 500 == 0 then C.tickBulk(500) end
        end
        gc = nil
    end)
    visited = nil
    pcall(collectgarbage, "step", D.limits.gcStepSize)
    if found > 0 then D.UI:Log("    +"..found.." via upvalue chains", "green") end
end

-- ══════════════════════════════════
--  ORCHESTRATOR
-- ══════════════════════════════════

function M.collectAll()
    local m = mode()
    D.UI:SetPhase("collecting")
    D.UI:Log("Collecting ("..m:upper()..")...", "blue")
    task.wait(0.2)

    -- Services: safe skips heavy ones
    local services
    if isSafe() then
        services = {
            "ReplicatedStorage","ReplicatedFirst","Lighting",
            "StarterGui","StarterPack","StarterPlayer","Workspace",
        }
    else
        services = {
            "ReplicatedStorage","ReplicatedFirst","Lighting",
            "StarterGui","StarterPack","StarterPlayer",
            "Workspace","Chat","SoundService","TestService",
            "TextChatService","MaterialService","Teams",
        }
    end

    for _, name in ipairs(services) do
        if D.S.cancel then return end
        scanService(name)
        -- Safe: memory check after every service
        if isSafe() then
            if not C.memoryGuard() then
                D.UI:Log("⚠ Memory limit — stopping collection early", "red")
                return
            end
        end
    end

    if not D.S.cancel then scanCharacters() end
    if not D.S.cancel then scanPlayerTree() end
    if not D.S.cancel then scanBasicSources() end

    C.memoryGuard()

    if not D.S.cancel then scanNil() end
    if not D.S.cancel then scanConnScripts() end
    if not D.S.cancel then scanRegistry() end

    C.memoryGuard()

    if not D.S.cancel then scanGC() end
    if not D.S.cancel then scanInstances() end
    if not D.S.cancel then scanThreads() end

    -- Advanced (skip in safe mode)
    if not D.limits.skipAdvanced and not D.S.cancel then
        D.UI:Log("── Advanced Methods ──", "blue")
        task.wait(0.15)
        C.memoryGuard()
        if not D.S.cancel then gcFunctionMap() end
        if not D.S.cancel then hiddenLocationScan() end
        if not D.S.cancel then collectionServiceScan() end
        if not D.S.cancel then moduleRequireTrace() end
        if isTurbo() and not D.S.cancel then
            task.wait(0.1); C.memoryGuard()
            deepUpvalueChain()
        end
    end

    -- Sort: cache hits first (faster processing)
    table.sort(D.S.queue, function(a, b)
        local aH = a.bcHash and D.cache.bytecode[a.bcHash] and 0 or 1
        local bH = b.bcHash and D.cache.bytecode[b.bcHash] and 0 or 1
        return aH < bH
    end)

    D.S.stats.queued = #D.S.queue
    C.push()
    pcall(collectgarbage, "collect")

    D.UI:Log(string.format("Collected %d scripts (%d dedup, %d empty, %d server)",
        #D.S.queue, D.S.cacheStats.dedup, D.S.stats.empty_skip, D.S.stats.server_skip), "green")

    local srcStr = ""
    for m2, c in pairs(D.S.stats.sources) do srcStr = srcStr..m2..":"..c.." " end
    if #srcStr > 0 then D.UI:Log("  Sources: "..srcStr:sub(1,180), "gray") end
end

end