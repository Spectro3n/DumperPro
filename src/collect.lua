return function(D)
local M = {}
D.Collect = M
local C, has = D.Core, D.has

local function mode() return D.cfg.mode or "normal" end
local function isTurbo() return mode() == "turbo" end
local function isSafe() return mode() == "safe" end

-- ══════════════════════════════════
--  SCAN ALL SERVICES — iterate game:GetChildren()
--  No hardcoded names. Scans EVERYTHING that exists.
-- ══════════════════════════════════

local function scanWorkspace()
    C.safeScan("Workspace", function()
        D.UI:Log("  → Workspace (per-child)", "gray")
        local ok, ch = pcall(function() return workspace:GetChildren() end)
        if not ok or not ch then return end

        for ci, child in ipairs(ch) do
            if D.S.cancel then return end

            -- The child itself
            pcall(function()
                if C.isScript(child) then C.enqueue(child, "Workspace") end
                C.checkRemote(child)
            end)

            -- All descendants of this child
            pcall(function()
                local ok2, desc = pcall(function() return child:GetDescendants() end)
                if ok2 and desc then
                    C.processObjList(desc, "Workspace", D.limits.maxDescendants)
                    desc = nil
                end
            end)

            -- Yield strategy per child
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
    end)
end

local function scanAllServices()
    D.UI:Log("── Scanning ALL services ──", "blue")

    -- Get every single child of game — these are all services
    local ok, gameChildren = pcall(function() return game:GetChildren() end)
    if not ok or not gameChildren then
        D.UI:Log("  ⚠ Cannot get game children", "red")
        return
    end

    D.UI:Log("  Found "..#gameChildren.." services/roots", "gray")

    for _, svc in ipairs(gameChildren) do
        if D.S.cancel then return end

        local svcName = "?"
        pcall(function() svcName = svc.Name end)

        -- Workspace: handled separately (per-child for memory)
        if svc == workspace then
            scanWorkspace()
        else
            -- Every other service: scan all descendants
            C.safeScan("Svc:"..svcName, function()
                D.UI:Log("  → "..svcName, "gray")
                local ok2, desc = pcall(function() return svc:GetDescendants() end)
                if ok2 and desc then
                    C.processObjList(desc, svcName, D.limits.maxDescendants)
                    desc = nil
                end
            end)
        end

        -- Memory guard between services
        if isSafe() then
            if not C.memoryGuard() then
                D.UI:Log("⚠ Memory pressure — pausing", "yellow")
                task.wait(1)
                C.memoryGuard()
            end
        end
    end

    gameChildren = nil
end

-- ══════════════════════════════════
--  DEEP PLAYER SCAN
--  Finds where humanoid is, scans around it,
--  tools, accessories, backpack, everything
-- ══════════════════════════════════

local function scanPlayerDeep()
    D.UI:Log("  → Deep Player Scan", "orange")

    -- Helper: scan every child and descendant of a container
    local function scanContainer(container, label)
        if not container then return end
        pcall(function()
            -- Direct scripts
            for _, child in ipairs(container:GetChildren()) do
                pcall(function()
                    if C.isScript(child) then C.enqueue(child, label) end
                    C.checkRemote(child)
                end)
            end
            -- All descendants
            local ok, desc = pcall(function() return container:GetDescendants() end)
            if ok and desc then
                C.processObjList(desc, label)
                desc = nil
            end
        end)
    end

    -- Helper: scan a character model deeply (humanoid location, tools, accessories)
    local function scanCharacterDeep(char, label)
        if not char then return end
        pcall(function()
            -- All descendants first
            local ok, desc = pcall(function() return char:GetDescendants() end)
            if ok and desc then
                C.processObjList(desc, label)
                desc = nil
            end

            -- Find humanoid — scan siblings (scripts near humanoid)
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Parent then
                for _, sibling in ipairs(hum.Parent:GetChildren()) do
                    pcall(function()
                        if C.isScript(sibling) then
                            C.enqueue(sibling, label..".HumSibling")
                        end
                        C.checkRemote(sibling)
                        -- Also scan inside each sibling
                        local ok2, sd = pcall(function() return sibling:GetDescendants() end)
                        if ok2 and sd then
                            C.processObjList(sd, label..".HumChild")
                            sd = nil
                        end
                    end)
                end
            end

            -- Every child category
            for _, child in ipairs(char:GetChildren()) do
                pcall(function()
                    -- Tools held by character
                    if child:IsA("Tool") or child:IsA("BackpackItem") then
                        scanContainer(child, label..".Tool."..child.Name)
                    end
                    -- Accessories
                    if child:IsA("Accessory") or child:IsA("Hat") then
                        scanContainer(child, label..".Acc."..child.Name)
                    end
                    -- Any Model inside character
                    if child:IsA("Model") then
                        scanContainer(child, label..".Model."..child.Name)
                    end
                    -- Any Folder inside character
                    if child:IsA("Folder") or child:IsA("Configuration") then
                        scanContainer(child, label..".Folder."..child.Name)
                    end
                end)
            end
        end)
    end

    -- 1. LocalPlayer containers
    C.safeScan("LP_Containers", function()
        if not C.LP then return end
        -- Scan every child of the player object
        pcall(function()
            for _, child in ipairs(C.LP:GetChildren()) do
                if D.S.cancel then break end
                local childName = "?"
                pcall(function() childName = child.Name end)
                D.UI:Log("    Player/"..childName, "gray")
                scanContainer(child, "Player."..childName)
                C.yieldNow()
            end
        end)
    end)

    -- 2. LocalPlayer character — deep humanoid scan
    C.safeScan("LP_Character", function()
        if not C.LP then return end
        pcall(function()
            local char = C.LP.Character
            if char then
                D.UI:Log("    LP Character: "..char.Name, "gray")
                scanCharacterDeep(char, "LP.Char")
            end
        end)
    end)

    -- 3. ALL players — character + every container
    C.safeScan("AllPlayers", function()
        D.UI:Log("    All players", "gray")
        for _, player in ipairs(C.Players:GetPlayers()) do
            if D.S.cancel then break end
            pcall(function()
                -- Scan every child of the player object
                for _, child in ipairs(player:GetChildren()) do
                    pcall(function()
                        scanContainer(child, "P."..player.Name.."."..child.Name)
                    end)
                end
                -- Character deep scan
                if player.Character then
                    scanCharacterDeep(player.Character, "Char."..player.Name)
                end
            end)
            C.tick()
        end
    end)

    -- 4. ALL humanoid-containing models in workspace
    C.safeScan("AllHumanoids", function()
        D.UI:Log("    All humanoid models in workspace", "gray")
        local count = 0
        pcall(function()
            local ok, ch = pcall(function() return workspace:GetChildren() end)
            if not ok or not ch then return end
            for ci, child in ipairs(ch) do
                if D.S.cancel then break end
                pcall(function()
                    if child:IsA("Model") then
                        local hum = child:FindFirstChildOfClass("Humanoid")
                        if hum then
                            count = count + 1
                            scanCharacterDeep(child, "Humanoid."..child.Name)
                        end
                    end
                end)
                if not C.safeTick(ci) then return end
            end
            ch = nil
        end)
        if count > 0 then D.UI:Log("      "..count.." humanoid models", "gray") end
    end)

    -- 5. Workspace player-named models
    C.safeScan("WS_PlayerModels", function()
        pcall(function()
            for _, player in ipairs(C.Players:GetPlayers()) do
                if D.S.cancel then break end
                pcall(function()
                    local model = workspace:FindFirstChild(player.Name)
                    if model and model:IsA("Model") then
                        scanCharacterDeep(model, "WS_Player."..player.Name)
                    end
                end)
            end
        end)
    end)
end

-- ══════════════════════════════════
--  BASIC SOURCES — CRASH-SAFE
-- ══════════════════════════════════

local function scanBasicSources()
    -- ── getscripts ──
    if not D.S.cancel and has.getscripts then
        C.safeScan("getscripts", function()
            D.UI:Log("  → getscripts()", "orange")
            local ok, s = C.dangerousCall("getscripts", getscripts)
            if not ok or not s then return end
            D.UI:Log("    "..#s.." total scripts", "gray")
            C.processListSafe(s, "getscripts")
            s = nil
        end)
        C.yieldNow()
        C.memoryGuard()
    end

    -- ── getrunningscripts — protected ──
    if not D.S.cancel and D.cfg.scanRunning and has.getrunningscripts then
        C.safeScan("running", function()
            D.UI:Log("  → getrunningscripts() [protected]", "orange")
            C.deepClean()

            local ok, s = C.dangerousCall("getrunningscripts", getrunningscripts)
            if not ok or not s then
                D.UI:Log("    ⚠ getrunningscripts failed — continuing", "yellow")
                return
            end

            D.UI:Log("    "..#s.." running scripts", "gray")

            -- Process ONE AT A TIME, triple protection
            for i = 1, #s do
                if D.S.cancel then break end
                pcall(function()
                    local obj = s[i]
                    if not obj then return end
                    pcall(function()
                        if C.isScript(obj) then C.enqueue(obj, "running") end
                    end)
                    pcall(function() C.checkRemote(obj) end)
                end)
                if i % 3 == 0 then task.wait() end
                if i % 10 == 0 then
                    if not C.memoryGuard() then
                        D.UI:Log("    ⚠ memory limit at "..i.."/"..#s, "yellow")
                        break
                    end
                end
            end
            s = nil
        end)
        C.yieldNow()
        pcall(collectgarbage, "collect")
        task.wait(0.3)
    end

    -- ── getloadedmodules ──
    if not D.S.cancel and D.cfg.scanLoaded and has.getloadedmodules then
        C.safeScan("loaded", function()
            D.UI:Log("  → getloadedmodules() [protected]", "orange")
            C.deepClean()

            local ok, m = C.dangerousCall("getloadedmodules", getloadedmodules)
            if not ok or not m then
                D.UI:Log("    ⚠ getloadedmodules failed", "yellow")
                return
            end

            D.UI:Log("    "..#m.." loaded modules", "gray")
            C.processListSafe(m, "loaded")
            m = nil
        end)
        C.yieldNow()
        C.memoryGuard()
    end
end

-- ══════════════════════════════════
--  NIL INSTANCES — recursive
-- ══════════════════════════════════

local function scanNil()
    if not D.cfg.scanNil or not has.getnilinstances then return end
    C.safeScan("nil", function()
        D.UI:Log("  → getnilinstances() [protected]", "orange")
        C.deepClean()

        local ok, nils = C.dangerousCall("getnilinstances", getnilinstances)
        if not ok or not nils then
            D.UI:Log("    ⚠ getnilinstances failed", "yellow")
            return
        end

        D.UI:Log("    "..#nils.." nil objects", "gray")
        local maxDepth = D.limits.maxNilDepth

        local function scanChildren(parent, depth, label)
            if depth > maxDepth or D.S.cancel then return end
            pcall(function()
                local ch = parent:GetChildren()
                for _, child in ipairs(ch) do
                    if D.S.cancel then return end
                    pcall(function()
                        if C.isScript(child) then C.enqueue(child, label.."_c"..depth) end
                        C.checkRemote(child)
                    end)
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
                if not obj then return end
                pcall(function()
                    if C.isScript(obj) then C.enqueue(obj, "nil") end
                    C.checkRemote(obj)
                end)
                scanChildren(obj, 1, "nil")
            end)
            if not C.safeTick(i) then break end
        end
        nils = nil
    end)
end

-- ══════════════════════════════════
--  CONNECTION → SCRIPTS
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
        pcall(function() sigs[#sigs+1] = C.LP.Chatted end)

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
    if not D.cfg.scanReg then return end
    C.safeScan("Registry", function()
        if not has.getreg then return end
        C.deepClean()
        local ok, reg = C.dangerousCall("getreg", getreg)
        if not ok or not reg then
            D.UI:Log("    ⚠ getreg failed", "yellow")
            return
        end

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
--  GC / INSTANCES / THREADS
-- ══════════════════════════════════

local function testGC()
    if not has.getgc then return false end
    local ok = pcall(function() local t = getgc(false); t = nil end)
    return ok
end

local function scanGC()
    if not D.cfg.scanGC or not testGC() then return end
    C.safeScan("GC", function()
        C.deepClean()
        D.UI:Log("  → getgc() [protected]", "orange")

        local ok, gc = C.dangerousCall("getgc", getgc, true)
        if not ok or not gc then
            D.UI:Log("    ⚠ getgc failed", "yellow")
            return
        end

        local sz = math.min(#gc, D.limits.gcLimit)
        D.UI:Log("    "..sz.." GC items", "gray")

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
        C.deepClean()
        D.UI:Log("  → getinstances() [protected]", "orange")

        local ok, all = C.dangerousCall("getinstances", getinstances)
        if not ok or not all then
            D.UI:Log("    ⚠ getinstances failed", "yellow")
            return
        end

        D.UI:Log("    "..#all.." instances", "gray")
        C.processObjList(all, "memory", D.limits.gcLimit)
        all = nil
        pcall(collectgarbage, "collect")
    end)
end

local function scanThreads()
    if not D.cfg.scanThreads or not has.getgc or not has.getscriptfromthread then return end
    C.safeScan("Threads", function()
        C.deepClean()
        D.UI:Log("  → threads [protected]", "orange")

        local ok, gc = C.dangerousCall("getgc_threads", getgc, true)
        if not ok or not gc then return end

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
--  ADVANCED: GC Function Map
-- ══════════════════════════════════

local function gcFunctionMap()
    if not testGC() then return end
    local found = 0
    C.safeScan("GCFuncMap", function()
        D.UI:Log("  → gcFunctionMap()", "orange")
        C.deepClean()

        local ok, gc = C.dangerousCall("gcFuncMap", getgc, false)
        if not ok or not gc then return end

        local seen2 = {}
        local sz = math.min(#gc, D.limits.gcLimit)
        local chunk = isTurbo() and 500 or (isSafe() and 40 or 200)

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
--  ADVANCED: CollectionService Tags
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
                    pcall(function()
                        if C.isScript(obj) then C.enqueue(obj, "tag:"..tag); found = found + 1 end
                        C.checkRemote(obj)
                    end)
                end
            end)
            if not C.safeTick(ti) then break end
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
        C.deepClean()

        local ok, mods = C.dangerousCall("mods_trace", getloadedmodules)
        if not ok or not mods then return end

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
                    pcall(function()
                        if mod.Parent and mod.Parent.Parent then
                            roots[#roots+1] = mod.Parent.Parent
                        end
                    end)
                    for _, path in ipairs(paths) do
                        for _, root in ipairs(roots) do
                            pcall(function()
                                local t = root:FindFirstChild(path, true)
                                if t and C.isScript(t) then
                                    C.enqueue(t, "require_trace"); found = found + 1
                                end
                            end)
                        end
                    end
                end

                if has.getupvalues then
                    pcall(function()
                        local ups = getupvalues(fn)
                        if not ups then return end
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
--  ADVANCED: GC Table Deep Scan
-- ══════════════════════════════════

local function gcTableDeepScan()
    if not testGC() then return end
    local found = 0
    C.safeScan("GCTableDeep", function()
        D.UI:Log("  → gcTableDeepScan()", "orange")
        C.deepClean()

        local ok, gc = C.dangerousCall("gc_tbl_deep", getgc, true)
        if not ok or not gc then return end

        local sz = math.min(#gc, D.limits.gcLimit)
        local visited = {}
        local chunk = isTurbo() and 400 or (isSafe() and 40 or 150)

        for start = 1, sz, chunk do
            if D.S.cancel then break end
            pcall(function()
                local stop = math.min(start + chunk - 1, sz)
                for i = start, stop do
                    local v = gc[i]
                    if type(v) == "table" then
                        local tidOk, tid = pcall(tostring, v)
                        if tidOk and not visited[tid] then
                            visited[tid] = true
                            pcall(function()
                                local tc = 0
                                for k2, v2 in pairs(v) do
                                    tc = tc + 1; if tc > 60 then break end
                                    if typeof(v2) == "Instance" then
                                        pcall(function()
                                            if C.isScript(v2) then
                                                C.enqueue(v2, "gc_tbl_deep"); found = found + 1
                                            end
                                            C.checkRemote(v2)
                                        end)
                                    elseif type(v2) == "table" then
                                        pcall(function()
                                            local tc2 = 0
                                            for _, v3 in pairs(v2) do
                                                tc2 = tc2 + 1; if tc2 > 20 then break end
                                                if typeof(v3) == "Instance" and C.isScript(v3) then
                                                    C.enqueue(v3, "gc_tbl2"); found = found + 1
                                                end
                                            end
                                        end)
                                    end
                                    if typeof(k2) == "Instance" and C.isScript(k2) then
                                        C.enqueue(k2, "gc_tbl_key"); found = found + 1
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
--  ADVANCED: Deep Upvalue Chain
-- ══════════════════════════════════

local function deepUpvalueChain()
    if not testGC() or not has.getupvalues then return end
    local found, walked = 0, 0
    local maxWalk = D.limits.gcLimit
    local maxDepth = D.limits.upvalueDepth
    local visited = {}

    local function walkFunc(fn, depth)
        if depth > maxDepth or walked > maxWalk or D.S.cancel then return end
        local idOk, id = pcall(tostring, fn)
        if not idOk then return end
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
        if isSafe() then
            if walked % 25 == 0 then C.yieldNow() end
            if walked % 60 == 0 then C.memoryGuard() end
        elseif walked % 200 == 0 then
            C.tickBulk(200)
        end
    end

    C.safeScan("UpvalChain", function()
        D.UI:Log("  → deepUpvalueChain()", "orange")
        C.deepClean()

        local ok, gc = C.dangerousCall("upval_gc", getgc, false)
        if not ok or not gc then return end

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
--  ORCHESTRATOR
-- ══════════════════════════════════

function M.collectAll()
    local m = mode()
    D.UI:SetPhase("collecting")
    D.UI:Log("Collecting ("..m:upper()..")...", "blue")
    D.UI:Log("★ ALL scanners active — scanning every service in game", "blue")
    task.wait(0.2)

    -- 1. Scan EVERY service — no hardcoded list
    if not D.S.cancel then scanAllServices() end
    C.memoryGuard()

    -- 2. Deep player scan
    if not D.S.cancel then scanPlayerDeep() end
    C.memoryGuard()

    -- 3. Basic sources (protected)
    if not D.S.cancel then scanBasicSources() end
    C.memoryGuard()

    -- 4. Nil
    if not D.S.cancel then scanNil() end
    C.memoryGuard()

    -- 5. Connections
    if not D.S.cancel then scanConnScripts() end
    C.memoryGuard()

    -- 6. Registry
    if not D.S.cancel then scanRegistry() end
    C.memoryGuard()

    -- 7. GC
    if not D.S.cancel then scanGC() end
    C.memoryGuard()

    -- 8. Instances
    if not D.S.cancel then scanInstances() end
    C.memoryGuard()

    -- 9. Threads
    if not D.S.cancel then scanThreads() end
    C.memoryGuard()

    -- 10. Advanced
    D.UI:Log("── Advanced Methods ──", "blue")
    task.wait(0.15)

    if not D.S.cancel then gcFunctionMap() end
    C.memoryGuard()

    if not D.S.cancel then collectionServiceScan() end
    C.memoryGuard()

    if not D.S.cancel then moduleRequireTrace() end
    C.memoryGuard()

    if not D.S.cancel then gcTableDeepScan() end
    C.memoryGuard()

    if not D.S.cancel then deepUpvalueChain() end
    C.memoryGuard()

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