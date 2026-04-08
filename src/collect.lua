return function(D)
local M = {}
D.Collect = M
local C, has = D.Core, D.has

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
                if isSafe() then
                    C.yieldNow()
                    if ci % D.limits.memCheckEvery == 0 then
                        if not C.memoryGuard() then return end
                    end
                elseif isTurbo() then
                    if ci % 15 == 0 then C.yieldNow() end
                else
                    if ci % 6 == 0 then C.yieldNow(); pcall(collectgarbage,"step",60) end
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
--  CHARACTERS — expanded containers
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

    -- Expanded container list
    local containers = {
        "Characters","Chars","PlayerCharacters","Entities","NPCs",
        "Mobs","Models","Units","Actors","Avatars","PlayerModels",
        "Enemies","Bots","AI","Minions","Pets","Companions",
        "Vehicles","Weapons","Tools","Items","Collectibles",
        "Systems","Managers","Controllers","Services","Modules",
        "Shared","Common","Lib","Library","Libraries","Utils",
        "Utility","Utilities","Packages","Framework","Client",
        "Assets","Resources","Data","Storage","Cache","Config",
        "Settings","Effects","Particles","Sounds","GUI","UI",
        "Interface","Screens","Menus","HUD","Notifications",
        "Events","Signals","Network","Remotes","Communication",
    }
    C.safeScan("Containers", function()
        local roots = {}
        pcall(function() roots[#roots+1] = workspace end)
        pcall(function() roots[#roots+1] = game:GetService("ReplicatedStorage") end)
        pcall(function() roots[#roots+1] = game:GetService("ReplicatedFirst") end)
        pcall(function() roots[#roots+1] = game:GetService("StarterPlayer") end)
        pcall(function() roots[#roots+1] = game:GetService("StarterGui") end)
        pcall(function() roots[#roots+1] = game:GetService("StarterPack") end)
        pcall(function() roots[#roots+1] = game:GetService("Lighting") end)

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
            if isSafe() then C.yieldNow() end
        end
    end)

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
            if not C.safeTick(ci) then return end
        end
        ch = nil
    end)

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
--  NIL INSTANCES — deep scan, all modes
-- ══════════════════════════════════

local function scanNil()
    if not D.cfg.scanNil or not has.getnilinstances then return end
    C.safeScan("nil", function()
        D.UI:Log("  → getnilinstances()", "orange")
        local nils = getnilinstances()
        D.UI:Log("    "..#nils.." nil objects", "gray")
        local maxDepth = D.limits.maxNilDepth

        local function scanChildren(parent, depth, label)
            if depth > maxDepth or D.S.cancel then return end
            pcall(function()
                local ch = parent:GetChildren()
                for _, child in ipairs(ch) do
                    if D.S.cancel then return end
                    if C.isScript(child) then C.enqueue(child, label.."_c"..depth) end
                    C.checkRemote(child)
                    if depth < maxDepth then
                        scanChildren(child, depth + 1, label)
                    end
                end
            end)
        end

        for i = 1, #nils do
            if D.S.cancel then break end
            pcall(function()
                local obj = nils[i]
                if C.isScript(obj) then C.enqueue(obj, "nil") end
                C.checkRemote(obj)
                scanChildren(obj, 1, "nil")
            end)
            if not C.safeTick(i) then break end
        end
        nils = nil
    end)
end

-- ══════════════════════════════════
--  CONNECTION → SCRIPTS — all modes
-- ══════════════════════════════════

local function scanConnScripts()
    if not D.cfg.scanConn or not has.getconnections then return end
    C.safeScan("ConnScripts", function()
        D.UI:Log("  → connection scripts", "orange")
        local sigs = {}
        pcall(function() sigs[#sigs+1] = C.Run.Heartbeat end)
        pcall(function() sigs[#sigs+1] = C.Run.Stepped end)
        pcall(function() sigs[#sigs+1] = C.UIS.InputBegan end)
        pcall(function() sigs[#sigs+1] = C.Players.PlayerAdded end)
        pcall(function() sigs[#sigs+1] = C.Run.RenderStepped end)
        pcall(function() sigs[#sigs+1] = C.UIS.InputEnded end)
        pcall(function() sigs[#sigs+1] = C.LP.CharacterAdded end)

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
--  REGISTRY — all modes
-- ══════════════════════════════════

local function scanRegistry()
    if not D.cfg.scanReg then return end
    C.safeScan("Registry", function()
        local reg
        if has.getreg then pcall(function() reg = getreg() end) end
        if not reg then return end
        D.UI:Log("  → registry ("..#reg..")", "orange")
        local limit = math.min(#reg, D.limits.gcLimit)

        if isTurbo() then
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
                                    tc = tc + 1; if tc > 80 then break end
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
                                tc = tc + 1; if tc > 50 then break end
                                if typeof(v2) == "Instance" then
                                    if C.isScript(v2) then C.enqueue(v2, "reg_tbl") end
                                    C.checkRemote(v2)
                                end
                            end
                        end)
                    end
                end)
                if not C.safeTick(i) then break end
            end
        end
        reg = nil
    end)
end

-- ══════════════════════════════════
--  GC / INSTANCES / THREADS — all modes
-- ══════════════════════════════════

local function testGC()
    if not has.getgc then return false end
    local ok = pcall(function() local t = getgc(false); t = nil end)
    return ok
end

local function scanGC()
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
                if not C.safeTick(i) then break end
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
        C.processObjList(all, "memory", D.limits.gcLimit)
        all = nil
        pcall(collectgarbage, "collect")
    end)
end

local function scanThreads()
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
            if not C.safeTick(i) then break end
        end
        gc = nil
        pcall(collectgarbage, "collect")
    end)
end

-- ══════════════════════════════════
--  ADVANCED: GC Function → Script Map — all modes
-- ══════════════════════════════════

local function gcFunctionMap()
    if not testGC() then return end
    local found = 0
    C.safeScan("GCFuncMap", function()
        D.UI:Log("  → gcFunctionMap()", "orange")
        local seen2 = {}
        local gc = getgc(false)
        local sz = math.min(#gc, D.limits.gcLimit)
        local chunk = isTurbo() and 500 or (isSafe() and 30 or 200)
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
            if isSafe() then
                C.yieldNow()
                if not C.memoryGuard() then break end
            else
                C.tickBulk(chunk)
            end
        end
        gc = nil; seen2 = nil
    end)
    if found > 0 then D.UI:Log("    +"..found.." via funcmap", "green") end
end

-- ══════════════════════════════════
--  ADVANCED: Hidden Locations — expanded, all modes
-- ══════════════════════════════════

local function hiddenLocationScan()
    local found = 0
    C.safeScan("HiddenLocs", function()
        D.UI:Log("  → hiddenLocations()", "orange")
        local locs = {}
        pcall(function() locs[#locs+1] = {"Camera",       workspace.CurrentCamera} end)
        pcall(function() locs[#locs+1] = {"Terrain",       workspace.Terrain} end)
        pcall(function() locs[#locs+1] = {"CoreGui",       game:GetService("CoreGui")} end)
        pcall(function() locs[#locs+1] = {"CorePkg",       game:GetService("CorePackages")} end)
        pcall(function() locs[#locs+1] = {"Debris",        game:GetService("Debris")} end)
        pcall(function() locs[#locs+1] = {"Tween",         game:GetService("TweenService")} end)
        pcall(function() locs[#locs+1] = {"Content",       game:GetService("ContentProvider")} end)
        pcall(function() locs[#locs+1] = {"Network",       game:GetService("NetworkClient")} end)
        pcall(function() locs[#locs+1] = {"RunSvc",        game:GetService("RunService")} end)
        pcall(function() locs[#locs+1] = {"Selection",     game:GetService("Selection")} end)
        pcall(function() locs[#locs+1] = {"HttpSvc",       game:GetService("HttpService")} end)
        pcall(function() locs[#locs+1] = {"LocalStorage",  game:GetService("LocalizationService")} end)
        pcall(function() locs[#locs+1] = {"PolicySvc",     game:GetService("PolicyService")} end)
        pcall(function() locs[#locs+1] = {"GuiSvc",        game:GetService("GuiService")} end)
        pcall(function() locs[#locs+1] = {"VR",            game:GetService("VRService")} end)
        pcall(function() locs[#locs+1] = {"Social",        game:GetService("SocialService")} end)
        pcall(function() locs[#locs+1] = {"Marketplace",   game:GetService("MarketplaceService")} end)
        pcall(function() locs[#locs+1] = {"GamePass",      game:GetService("GamePassService")} end)
        pcall(function() locs[#locs+1] = {"Badge",         game:GetService("BadgeService")} end)
        pcall(function() locs[#locs+1] = {"TextChat",      game:GetService("TextChatService")} end)
        pcall(function() locs[#locs+1] = {"Material",      game:GetService("MaterialService")} end)
        pcall(function() locs[#locs+1] = {"Anim",          game:GetService("KeyframeSequenceProvider")} end)
        pcall(function() locs[#locs+1] = {"Pathfinding",   game:GetService("PathfindingService")} end)
        pcall(function() locs[#locs+1] = {"Physics",       game:GetService("PhysicsService")} end)
        pcall(function() locs[#locs+1] = {"ProximityPrompt",game:GetService("ProximityPromptService")} end)

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
            if isSafe() then C.yieldNow() end
        end
    end)
    if found > 0 then D.UI:Log("    +"..found.." hidden", "green") end
end

-- ══════════════════════════════════
--  ADVANCED: CollectionService Tags — all modes
-- ══════════════════════════════════

local function collectionServiceScan()
    local found = 0
    C.safeScan("Tags", function()
        D.UI:Log("  → collectionService()", "orange")
        local ok, tags = pcall(function() return C.Tags:GetAllTags() end)
        if not ok or not tags then return end
        D.UI:Log("    "..#tags.." tags", "gray")
        local maxTags = D.limits.maxTags
        for ti, tag in ipairs(tags) do
            if D.S.cancel or ti > maxTags then break end
            pcall(function()
                local tagged = C.Tags:GetTagged(tag)
                for _, obj in ipairs(tagged) do
                    if C.isScript(obj) then C.enqueue(obj, "tag:"..tag); found = found + 1 end
                    C.checkRemote(obj)
                end
            end)
            if not C.safeTick(ti) then break end
        end
    end)
    if found > 0 then D.UI:Log("    +"..found.." via tags", "green") end
end

-- ══════════════════════════════════
--  ADVANCED: Module Require Trace — all modes
-- ══════════════════════════════════

local function moduleRequireTrace()
    if not D.cfg.dumpModule or not has.getloadedmodules or not has.getconstants then return end
    local found = 0
    C.safeScan("RequireTrace", function()
        D.UI:Log("  → moduleRequireTrace()", "orange")
        local mods = getloadedmodules()
        if not mods then return end
        local maxMods = D.limits.maxModTrace
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
                    if ci > 300 then break end
                    if c == "require" then hasReq = true end
                    if type(c) == "string" and #c > 2 and #c < 150 then
                        paths[#paths+1] = c
                    end
                end
                if hasReq and #paths > 0 then
                    local roots = {}
                    pcall(function() roots[#roots+1] = game:GetService("ReplicatedStorage") end)
                    pcall(function() roots[#roots+1] = game:GetService("ReplicatedFirst") end)
                    pcall(function() roots[#roots+1] = mod.Parent end)
                    pcall(function() if mod.Parent and mod.Parent.Parent then roots[#roots+1] = mod.Parent.Parent end end)
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
                                elseif type(v) == "table" then
                                    local tc = 0
                                    for _, tv in pairs(v) do
                                        tc = tc + 1; if tc > 30 then break end
                                        if typeof(tv) == "Instance" and C.isScript(tv) then
                                            C.enqueue(tv, "mod_upval_tbl"); found = found + 1
                                        end
                                    end
                                end
                            end
                        end
                    end)
                end
            end)
            if not C.safeTick(mi) then break end
        end
        mods = nil
    end)
    if found > 0 then D.UI:Log("    +"..found.." via require trace", "green") end
end

-- ══════════════════════════════════
--  ADVANCED: Deep Upvalue Chain — normal + turbo (safe with protection)
-- ══════════════════════════════════

local function deepUpvalueChain()
    if not testGC() or not has.getupvalues then return end
    local found, walked = 0, 0
    local maxWalk = D.limits.gcLimit
    local maxDepth = D.limits.upvalueDepth
    local visited = {}

    local function walkFunc(fn, depth)
        if depth > maxDepth or walked > maxWalk or D.S.cancel then return end
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
                        tc = tc + 1; if tc > 20 then break end
                        if typeof(tv) == "Instance" and C.isScript(tv) then
                            C.enqueue(tv, "upval_tbl"); found = found + 1
                        elseif type(tv) == "function" and depth < maxDepth - 1 then
                            walkFunc(tv, depth + 2)
                        end
                    end
                end
            end
        end)
        -- Safe: yield more often during walk
        if isSafe() then
            if walked % 20 == 0 then C.yieldNow() end
            if walked % 50 == 0 then C.memoryGuard() end
        elseif walked % 200 == 0 then
            C.tickBulk(200)
        end
    end

    C.safeScan("UpvalChain", function()
        D.UI:Log("  → deepUpvalueChain()", "orange")
        local gc = getgc(false)
        local sz = math.min(#gc, maxWalk)
        for i = 1, sz do
            if D.S.cancel or walked > maxWalk then break end
            if type(gc[i]) == "function" then walkFunc(gc[i], 0) end
            if isSafe() then
                if i % 100 == 0 then C.yieldNow() end
            elseif i % 500 == 0 then
                C.tickBulk(500)
            end
        end
        gc = nil
    end)
    visited = nil
    pcall(collectgarbage, "step", D.limits.gcStepSize)
    if found > 0 then D.UI:Log("    +"..found.." via upvalue chains", "green") end
end

-- ══════════════════════════════════
--  ADVANCED: GC table deep scan — find scripts in nested tables
-- ══════════════════════════════════

local function gcTableDeepScan()
    if not testGC() then return end
    local found = 0
    C.safeScan("GCTableDeep", function()
        D.UI:Log("  → gcTableDeepScan()", "orange")
        local gc = getgc(true)
        local sz = math.min(#gc, D.limits.gcLimit)
        local visited = {}
        local chunk = isTurbo() and 400 or (isSafe() and 30 or 150)

        for start = 1, sz, chunk do
            if D.S.cancel then break end
            pcall(function()
                local stop = math.min(start + chunk - 1, sz)
                for i = start, stop do
                    local v = gc[i]
                    if type(v) == "table" then
                        local tid = tostring(v)
                        if not visited[tid] then
                            visited[tid] = true
                            pcall(function()
                                local tc = 0
                                for k2, v2 in pairs(v) do
                                    tc = tc + 1; if tc > 60 then break end
                                    if typeof(v2) == "Instance" then
                                        if C.isScript(v2) then C.enqueue(v2, "gc_table_deep"); found = found + 1 end
                                        C.checkRemote(v2)
                                    elseif type(v2) == "table" then
                                        pcall(function()
                                            local tc2 = 0
                                            for _, v3 in pairs(v2) do
                                                tc2 = tc2 + 1; if tc2 > 20 then break end
                                                if typeof(v3) == "Instance" then
                                                    if C.isScript(v3) then C.enqueue(v3, "gc_tbl2"); found = found + 1 end
                                                end
                                            end
                                        end)
                                    end
                                    if typeof(k2) == "Instance" then
                                        if C.isScript(k2) then C.enqueue(k2, "gc_tbl_key"); found = found + 1 end
                                    end
                                end
                            end)
                        end
                    end
                end
            end)
            if isSafe() then
                C.yieldNow()
                if not C.memoryGuard() then break end
            else
                C.tickBulk(chunk)
            end
        end
        gc = nil; visited = nil
    end)
    if found > 0 then D.UI:Log("    +"..found.." via GC table deep", "green") end
end

-- ══════════════════════════════════
--  ADVANCED: Workspace recursive folder scan
-- ══════════════════════════════════

local function workspaceFolderScan()
    local found = 0
    C.safeScan("WSFolders", function()
        D.UI:Log("  → workspace folders deep scan", "orange")
        local ok, ch = pcall(function() return workspace:GetChildren() end)
        if not ok or not ch then return end
        for ci, child in ipairs(ch) do
            if D.S.cancel then break end
            pcall(function()
                if child:IsA("Folder") or child:IsA("Configuration") then
                    local ok2, desc = pcall(function() return child:GetDescendants() end)
                    if ok2 and desc then
                        for _, obj in ipairs(desc) do
                            if C.isScript(obj) then C.enqueue(obj, "ws_folder."..child.Name); found = found + 1 end
                            C.checkRemote(obj)
                        end
                        desc = nil
                    end
                end
            end)
            if not C.safeTick(ci) then break end
        end
        ch = nil
    end)
    if found > 0 then D.UI:Log("    +"..found.." via workspace folders", "green") end
end

-- ══════════════════════════════════
--  ORCHESTRATOR — EVERYTHING runs in ALL modes
-- ══════════════════════════════════

function M.collectAll()
    local m = mode()
    D.UI:SetPhase("collecting")
    D.UI:Log("Collecting ("..m:upper()..")...", "blue")
    D.UI:Log("★ ALL scanners active — "..m.." protection level", "blue")
    task.wait(0.2)

    -- ALL services, ALL modes
    local services = {
        "ReplicatedStorage","ReplicatedFirst","Lighting",
        "StarterGui","StarterPack","StarterPlayer",
        "Workspace","Chat","SoundService","TestService",
        "TextChatService","MaterialService","Teams",
    }
    for _, name in ipairs(services) do
        if D.S.cancel then return end
        scanService(name)
        if isSafe() then
            if not C.memoryGuard() then
                D.UI:Log("⚠ Memory pressure — pausing 1s", "yellow")
                task.wait(1)
                C.memoryGuard()
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

    C.memoryGuard()

    -- ADVANCED — runs in ALL modes
    D.UI:Log("── Advanced Methods ──", "blue")
    task.wait(0.15)

    if not D.S.cancel then gcFunctionMap() end
    if not D.S.cancel then hiddenLocationScan() end
    if not D.S.cancel then collectionServiceScan() end
    if not D.S.cancel then moduleRequireTrace() end
    if not D.S.cancel then gcTableDeepScan() end
    if not D.S.cancel then workspaceFolderScan() end

    C.memoryGuard()

    if not D.S.cancel then
        deepUpvalueChain()
    end

    -- Sort: cache hits first
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
    if #srcStr > 0 then D.UI:Log("  Sources: "..srcStr:sub(1,200), "gray") end
end

end