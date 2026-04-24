return function(D)
local C = {}
D.Core = C

C.Players = game:GetService("Players")
C.Run     = game:GetService("RunService")
C.Http    = game:GetService("HttpService")
C.UIS     = game:GetService("UserInputService")
C.Tags    = game:GetService("CollectionService")
C.LP      = C.Players.LocalPlayer

-- ══════════════════════════════════
--  v15: REAL GAME FREEZE SYSTEM
--  Stops ALL game processing to prevent
--  crashes from bullets, physics, NPCs, etc.
-- ══════════════════════════════════

local frozenState = {
    frozen = false,
    gravity = nil,
    anchoredParts = {},
    humanoidData = {},
    stoppedAnims = {},
    pausedSounds = {},
    rsConnections = {},
    controlsDisabled = false,
    physicsPaused = false,
}

function C.freezeGame()
    if frozenState.frozen then return end
    frozenState.frozen = true

    -- 1. Pause physics — set gravity to 0
    pcall(function()
        frozenState.gravity = workspace.Gravity
        workspace.Gravity = 0
    end)

    -- 2. Anchor ALL unanchored BaseParts in workspace (stops bullets, projectiles, NPCs, vehicles)
    pcall(function()
        local ok, desc = pcall(function() return workspace:GetDescendants() end)
        if ok and desc then
            for i = 1, #desc do
                pcall(function()
                    local p = desc[i]
                    if p:IsA("BasePart") and not p.Anchored then
                        frozenState.anchoredParts[p] = true
                        p.Anchored = true
                    end
                end)
            end
            desc = nil
        end
    end)

    -- 3. Freeze ALL humanoids (WalkSpeed, JumpPower, AutoRotate, PlatformStand)
    pcall(function()
        local ok, desc = pcall(function() return workspace:GetDescendants() end)
        if ok and desc then
            for i = 1, #desc do
                pcall(function()
                    local h = desc[i]
                    if h:IsA("Humanoid") then
                        frozenState.humanoidData[h] = {
                            ws = h.WalkSpeed,
                            jp = h.JumpPower,
                            ar = h.AutoRotate,
                        }
                        h.WalkSpeed = 0
                        h.JumpPower = 0
                        h.AutoRotate = false
                    end
                end)
            end
            desc = nil
        end
    end)

    -- 4. Stop all playing AnimationTracks
    pcall(function()
        local ok, desc = pcall(function() return workspace:GetDescendants() end)
        if ok and desc then
            for i = 1, #desc do
                pcall(function()
                    local h = desc[i]
                    if h:IsA("Humanoid") or h:IsA("AnimationController") then
                        pcall(function()
                            local animator = h:FindFirstChildOfClass("Animator")
                            if animator then
                                local tracks = animator:GetPlayingAnimationTracks()
                                for _, track in ipairs(tracks) do
                                    pcall(function()
                                        frozenState.stoppedAnims[#frozenState.stoppedAnims+1] = track
                                        track:AdjustSpeed(0)
                                    end)
                                end
                            end
                        end)
                    end
                end)
            end
            desc = nil
        end
    end)

    -- 5. Pause all playing sounds
    pcall(function()
        local function pauseSoundsIn(container)
            pcall(function()
                local ok, desc = pcall(function() return container:GetDescendants() end)
                if ok and desc then
                    for i = 1, #desc do
                        pcall(function()
                            local s = desc[i]
                            if s:IsA("Sound") and s.Playing then
                                frozenState.pausedSounds[s] = true
                                s:Pause()
                            end
                        end)
                    end
                end
            end)
        end
        pauseSoundsIn(workspace)
        pcall(function() pauseSoundsIn(game:GetService("SoundService")) end)
        pcall(function() pauseSoundsIn(C.LP:FindFirstChild("PlayerGui")) end)
    end)

    -- 6. Disconnect RunService signals to stop game loops
    pcall(function()
        local run = C.Run
        local sigs = {}
        pcall(function() sigs[#sigs+1] = {"Heartbeat", run.Heartbeat} end)
        pcall(function() sigs[#sigs+1] = {"Stepped", run.Stepped} end)
        pcall(function() sigs[#sigs+1] = {"RenderStepped", run.RenderStepped} end)
        if has.getconnections then
            for _, sigDef in ipairs(sigs) do
                pcall(function()
                    local conns = getconnections(sigDef[2])
                    if conns then
                        for _, conn in ipairs(conns) do
                            pcall(function()
                                if conn.Enabled ~= false then
                                    conn:Disable()
                                    frozenState.rsConnections[#frozenState.rsConnections+1] = conn
                                end
                            end)
                        end
                    end
                end)
            end
        end
    end)

    -- 7. Disable player controls
    pcall(function()
        local pGui = C.LP:FindFirstChild("PlayerGui")
        if pGui then
            local pm = pGui:FindFirstChild("PlayerModule")
            if pm then
                local ctrl = require(pm):GetControls()
                if ctrl and ctrl.Disable then ctrl:Disable(); frozenState.controlsDisabled = true end
            end
        end
    end)

    -- 8. Disable particle emitters and beams
    pcall(function()
        local ok, desc = pcall(function() return workspace:GetDescendants() end)
        if ok and desc then
            for i = 1, #desc do
                pcall(function()
                    local p = desc[i]
                    if p:IsA("ParticleEmitter") or p:IsA("Fire") or p:IsA("Smoke") or p:IsA("Sparkles") then
                        if p.Enabled then
                            p.Enabled = false
                            frozenState.anchoredParts[p] = "particle"
                        end
                    end
                end)
            end
            desc = nil
        end
    end)
end

function C.unfreezeGame()
    if not frozenState.frozen then return end

    -- 1. Restore gravity
    pcall(function() if frozenState.gravity then workspace.Gravity = frozenState.gravity end end)

    -- 2. Unanchor parts & re-enable particles
    for obj, val in pairs(frozenState.anchoredParts) do
        pcall(function()
            if val == "particle" then
                obj.Enabled = true
            else
                obj.Anchored = false
            end
        end)
    end
    frozenState.anchoredParts = {}

    -- 3. Restore humanoids
    for hum, data in pairs(frozenState.humanoidData) do
        pcall(function()
            hum.WalkSpeed = data.ws
            hum.JumpPower = data.jp
            hum.AutoRotate = data.ar
        end)
    end
    frozenState.humanoidData = {}

    -- 4. Resume animations
    for _, track in ipairs(frozenState.stoppedAnims) do
        pcall(function() track:AdjustSpeed(1) end)
    end
    frozenState.stoppedAnims = {}

    -- 5. Resume sounds
    for snd in pairs(frozenState.pausedSounds) do
        pcall(function() snd:Resume() end)
    end
    frozenState.pausedSounds = {}

    -- 6. Re-enable RunService connections
    for _, conn in ipairs(frozenState.rsConnections) do
        pcall(function() conn:Enable() end)
    end
    frozenState.rsConnections = {}

    -- 7. Re-enable controls
    if frozenState.controlsDisabled then
        pcall(function()
            local pGui = C.LP:FindFirstChild("PlayerGui")
            if pGui then
                local pm = pGui:FindFirstChild("PlayerModule")
                if pm then
                    local ctrl = require(pm):GetControls()
                    if ctrl and ctrl.Enable then ctrl:Enable() end
                end
            end
        end)
        frozenState.controlsDisabled = false
    end

    frozenState.frozen = false
end

-- ══════════════════════════════════
--  MODES — v15 speed optimized
--  Safe: faster but protected
--  Normal: balanced
--  Turbo: maximum speed + safety guards
-- ══════════════════════════════════

C.MODES = {
    safe = {
        yieldEvery       = 8,
        gcLimit          = 90000,
        decompileTimeout = 18,
        maxNilDepth      = 3,
        hooksPerService  = 600,
        connLimit        = 15,
        hookDecompBudget = 15,
        maxDescendants   = 60000,
        batchSize        = 3,
        memCheckEvery    = 5,
        gcStepSize       = 50,
        chunkProcess     = 80,
        cacheHitBatch    = 12,
        upvalueDepth     = 4,
        maxTags          = 500,
        maxModTrace      = 700,
        logEvery         = 12,
        dangerousWait    = 0.5,
        dangerousTimeout = 10,
        maxMemoryMB      = 520,
        emergencyPauseSec= 2.5,
        microBatchMax    = 6,
    },
    normal = {
        yieldEvery       = 15,
        gcLimit          = 70000,
        decompileTimeout = 12,
        maxNilDepth      = 3,
        hooksPerService  = 700,
        connLimit        = 15,
        hookDecompBudget = 30,
        maxDescendants   = 40000,
        batchSize        = 4,
        memCheckEvery    = 7,
        gcStepSize       = 120,
        chunkProcess     = 200,
        cacheHitBatch    = 25,
        upvalueDepth     = 5,
        maxTags          = 600,
        maxModTrace      = 700,
        logEvery         = 10,
        dangerousWait    = 0.25,
        dangerousTimeout = 8,
        maxMemoryMB      = 560,
        emergencyPauseSec= 2.5,
        microBatchMax    = 10,
    },
    turbo = {
        yieldEvery       = 120,
        gcLimit          = 180000,
        decompileTimeout = 8,
        maxNilDepth      = 4,
        hooksPerService  = 1500,
        connLimit        = 40,
        hookDecompBudget = 100,
        maxDescendants   = 120000,
        batchSize        = 12,
        memCheckEvery    = 8,
        gcStepSize       = 500,
        chunkProcess     = 800,
        cacheHitBatch    = 80,
        upvalueDepth     = 7,
        maxTags          = 1000,
        maxModTrace      = 1200,
        logEvery         = 20,
        dangerousWait    = 0.08,
        dangerousTimeout = 6,
        maxMemoryMB      = 600,
        emergencyPauseSec= 2,
        microBatchMax    = 25,
    },
}

C.PROBES = {
    "decompile","saveinstance","getgc","getnilinstances",
    "getinstances","getscripts","getrunningscripts","getloadedmodules",
    "getreg","getconnections","getscriptbytecode","getscriptfunction",
    "getscriptfromthread","getconstants","getupvalues","getrawmetatable",
    "writefile","makefolder","isfolder","iscclosure","getscripthash",
    "identifyexecutor","getscriptclosure","getsenv","getcallbackvalue",
    "hookmetamethod","hookfunction","newcclosure","firesignal",
    "getnamecallmethod","checkcaller","getprotos","getupvalue",
    "setupvalue","debug.getinfo","getthreadidentity",
}

D.has = {}
for _, n in ipairs(C.PROBES) do
    local ok, val = pcall(function()
        if n:find(".",1,true) then
            local p = n:split(".")
            local t = getfenv()[p[1]] or _G[p[1]]
            return t and t[p[2]]
        end
        return getfenv()[n] or _G[n]
    end)
    D.has[n] = ok and val ~= nil
end

D.hasCrypt = false
pcall(function() if type(crypt)=="table" and crypt.hash then D.hasCrypt=true end end)

D.base64enc = nil
pcall(function()
    if D.hasCrypt then D.base64enc = crypt.base64encode or (crypt.base64 and crypt.base64.encode) end
end)
if not D.base64enc then pcall(function() D.base64enc = getfenv().base64encode end) end

D.cache = D.cache or { bytecode={}, linked={} }

local REM_CLS = {
    RemoteEvent=true, RemoteFunction=true, BindableEvent=true,
    BindableFunction=true, UnreliableRemoteEvent=true,
}
C.REM_CLS = REM_CLS

function C.resetState()
    local cfg = D.cfg
    local mode = cfg.mode or "normal"
    D.limits = {}
    local base = C.MODES[mode] or C.MODES.normal
    for k,v in pairs(base) do D.limits[k] = v end

    local folder = (cfg.folder or ""):gsub("[^%w%-_ ]","_"):gsub("_+","_"):sub(1,60)
    if folder == "" then folder = "Dump_"..game.PlaceId end

    D.S = {
        queue={}, seen={}, seenHash={}, usedFiles={},
        remotes={}, remoteSeen={}, hooks={}, fails={},
        skipped={}, connections={}, scanErrors={},
        singleBuffer={}, rootDir=folder,
        cancel=false, isSingleFile = cfg.singleFile==true,
        dumpSkipped = cfg.dumpSkipped~=false, yc=0,
        stats = {
            total=0, ok=0, fail=0, skip=0, remotes=0, hooks=0,
            t0=os.clock(), queued=0, cache_hits=0, dedup=0, linked=0,
            server_skip=0, empty_skip=0, aggressive=0,
            methods={}, sources={},
        },
        cacheStats = {hits=0, misses=0, dedup=0, linked=0},
    }
    C.ensureDir(folder)
end

-- ══════════════════════════════════
--  4-TIER ANTI-CRASH MEMORY SYSTEM
-- ══════════════════════════════════

function C.getMemKB()
    local ok,m = pcall(gcinfo); return ok and m or 0
end

function C.getMemMB()
    return math.floor(C.getMemKB() / 1024)
end

function C.emergencyFlush()
    D.UI:Log("🚨 EMERGENCY FLUSH — clearing caches", "red")
    -- Multiple GC passes
    for i = 1, 3 do
        pcall(collectgarbage, "collect")
        task.wait(0.5)
    end
    -- Trim bytecode cache to last 200 entries
    local cacheCount = 0
    local toRemove = {}
    for k in pairs(D.cache.bytecode) do
        cacheCount = cacheCount + 1
        if cacheCount > 200 then toRemove[#toRemove+1] = k end
    end
    for _, k in ipairs(toRemove) do D.cache.bytecode[k] = nil end
    toRemove = nil
    pcall(collectgarbage, "collect")
    task.wait(1)
    D.UI:Log("  Flushed to "..C.getMemMB().."MB", "yellow")
end

function C.memoryGuard()
    local memMB = C.getMemMB()
    local maxMem = D.limits.maxMemoryMB or 550

    if memMB > maxMem then
        -- TIER 4: EMERGENCY
        D.UI:Log("🚨 Memory CRITICAL: "..memMB.."MB — emergency flush", "red")
        C.emergencyFlush()
        task.wait(D.limits.emergencyPauseSec or 3)
        memMB = C.getMemMB()
        if memMB > maxMem - 50 then return false end
    elseif memMB > math.floor(maxMem * 0.82) then
        -- TIER 3: Full GC + wait
        pcall(collectgarbage, "collect")
        task.wait(0.5)
        pcall(collectgarbage, "collect")
        task.wait(0.3)
    elseif memMB > math.floor(maxMem * 0.55) then
        -- TIER 2: Incremental GC
        pcall(collectgarbage, "step", (D.limits.gcStepSize or 100) * 3)
        task.wait(0.15)
    elseif memMB > math.floor(maxMem * 0.36) then
        -- TIER 1: Light step
        pcall(collectgarbage, "step", D.limits.gcStepSize or 100)
    end
    return true
end

function C.adaptiveBatchSize()
    local memMB = C.getMemMB()
    local maxMem = D.limits.maxMemoryMB or 550
    local maxBatch = D.limits.microBatchMax or 8
    local ratio = memMB / maxMem
    if ratio > 0.85 then return 1
    elseif ratio > 0.7 then return math.max(1, math.floor(maxBatch * 0.25))
    elseif ratio > 0.5 then return math.max(2, math.floor(maxBatch * 0.5))
    else return maxBatch end
end

-- Force full cleanup — use before dangerous calls
function C.deepClean()
    pcall(collectgarbage, "collect")
    task.wait(D.limits.dangerousWait)
    pcall(collectgarbage, "collect")
    task.wait(0.1)
end

-- ══ YIELD ══
function C.tick()
    D.S.yc = D.S.yc + 1
    if D.S.yc >= D.limits.yieldEvery then
        D.S.yc = 0; task.wait()
    end
end

function C.yieldNow()
    D.S.yc = 0; task.wait()
end

function C.tickBulk(n)
    D.S.yc = D.S.yc + (n or 1)
    if D.S.yc >= D.limits.yieldEvery then
        D.S.yc = 0; task.wait()
    end
end

function C.safeTick(counter)
    C.tick()
    if counter and counter % D.limits.memCheckEvery == 0 then
        return C.memoryGuard()
    end
    return true
end

-- ══ SAFE SCAN ══
function C.safeScan(label, fn)
    local ok, err = xpcall(fn, function(e)
        local t = ""
        pcall(function() t = debug.traceback(tostring(e),2) end)
        return t ~= "" and t or tostring(e)
    end)
    if not ok then
        pcall(function()
            D.UI:Log("  ⚠ "..label..": "..tostring(err):sub(1,100),"red")
            D.S.scanErrors[#D.S.scanErrors+1] = {section=label, error=tostring(err):sub(1,150)}
        end)
    end
    pcall(C.yieldNow)
    pcall(collectgarbage,"step", D.limits.gcStepSize)
    return ok
end

-- ══ TIMED CALL ══
function C.timedCall(fn, timeout, ...)
    local args, rok, rval, done = {...}, nil, nil, false
    task.spawn(function()
        rok, rval = pcall(fn, unpack(args))
        done = true
    end)
    local t0 = os.clock()
    while not done do
        if os.clock()-t0 > timeout then return false, "Timeout" end
        task.wait(0.08)
    end
    return rok, rval
end

-- ══ DANGEROUS CALL ══
function C.dangerousCall(label, fn, ...)
    D.UI:Log("    ⟐ "..label.." (protected)", "gray")
    C.deepClean()
    if not C.memoryGuard() then
        D.UI:Log("    ⚠ "..label..": memory too high, cleaning harder", "yellow")
        C.emergencyFlush()
        task.wait(2)
        if not C.memoryGuard() then
            D.UI:Log("    ⚠ "..label..": skipping (memory critical)", "red")
            return false, nil
        end
    end
    local ok, result = C.timedCall(fn, D.limits.dangerousTimeout, ...)
    if not ok then
        D.UI:Log("    ⚠ "..label..": failed or timed out", "red")
        pcall(collectgarbage, "collect")
        return false, nil
    end
    return true, result
end

-- ══ HELPERS ══
function C.safeName(obj)
    local ok,n = pcall(function() return obj:GetFullName() end)
    return ok and n or "<nil>"
end

function C.elapsed()
    return string.format("%.1fs", os.clock() - D.S.stats.t0)
end

function C.trackMethod(m)
    D.S.stats.methods[m] = (D.S.stats.methods[m] or 0) + 1
end

function C.trackSource(s)
    D.S.stats.sources[s] = (D.S.stats.sources[s] or 0) + 1
end

function C.push()
    D.UI:SetStats({
        total=D.S.stats.total, ok=D.S.stats.ok,
        fail=D.S.stats.fail, remotes=D.S.stats.remotes,
        hooks=D.S.stats.hooks,
    })
    D.UI:SetProgress(D.S.stats.ok+D.S.stats.fail, math.max(D.S.stats.queued,1))
end

-- ══ HASH ══
function C.computeHash(data)
    if not data or #data==0 then return nil end
    if D.hasCrypt then
        local ok,h = pcall(crypt.hash, data, "sha384")
        if ok and h and #h>0 then return h end
    end
    local h1,h2,h3 = 0x811c9dc5, 0x01000193, 0x9e3779b9
    local len = #data
    local step = len > 80000 and math.floor(len/30000) or 1
    for i = 1, len, step do
        local b = string.byte(data,i)
        h1 = bit32.bxor(h1,b); h1 = bit32.band(h1*0x01000193, 0xFFFFFFFF)
        h2 = h2 + b*(i%256)
        h3 = bit32.bxor(h3, bit32.lrotate(h1+b, 13))
    end
    return string.format("%08x%08x%08x_%d", h1%0xFFFFFFFF, h2%0xFFFFFFFF, h3%0xFFFFFFFF, len)
end

function C.getScriptHash(obj)
    if not D.has.getscriptbytecode then return nil end
    local ok,bc = pcall(getscriptbytecode, obj)
    if not ok or not bc then return nil end
    return #bc==0 and "EMPTY" or C.computeHash(bc)
end

-- ══ FILTERS ══
function C.isServerScript(obj)
    local okC,cn = pcall(function() return obj.ClassName end)
    if not okC then return false end
    local okR,rc = pcall(function() return obj.RunContext end)
    if not okR then return false end
    if cn=="LocalScript" then return rc==Enum.RunContext.Server end
    if cn=="Script" then return rc~=Enum.RunContext.Client end
    return false
end

function C.isScript(obj)
    if not obj then return false end
    local ok,cn = pcall(function() return obj.ClassName end)
    if not ok then return false end
    if cn=="LocalScript" then
        if not D.cfg.dumpLocal then return false end
        if not D.cfg.dumpDisabled then
            local ok2,en = pcall(function() return obj.Enabled end)
            if ok2 and not en then return false end
        end
        return true
    end
    return cn=="ModuleScript" and D.cfg.dumpModule
end

-- ══ FILE SYSTEM ══
function C.ensureDir(p)
    if not D.has.makefolder or not D.has.isfolder then return end
    pcall(function() if not isfolder(p) then makefolder(p) end end)
end

function C.writeFile(p,d)
    if not D.has.writefile then return end
    pcall(writefile, p, d)
end

local function sanitize(s)
    return s:gsub("[^%w%-_]","_"):gsub("_+","_"):sub(1,50)
end

function C.buildFilePath(obj)
    local ok,full = pcall(function() return obj:GetFullName() end)
    if not ok or not full then return D.S.rootDir.."/Other","unknown" end
    local segs = {}
    for s in full:gmatch("[^%.]+") do segs[#segs+1]=sanitize(s) end
    if #segs==0 then return D.S.rootDir.."/Other","unknown" end
    local fileName = table.remove(segs)
    local folder = D.S.rootDir
    for _,s in ipairs(segs) do folder=folder.."/"..s; C.ensureDir(folder) end
    local path = folder.."/"..fileName..".lua"
    if D.S.usedFiles[path] then
        local n=2
        while D.S.usedFiles[folder.."/"..fileName.."_"..n..".lua"] do n=n+1 end
        fileName=fileName.."_"..n; path=folder.."/"..fileName..".lua"
    end
    D.S.usedFiles[path]=true
    return folder, fileName
end

-- ══ ENQUEUE ══
function C.enqueue(obj, from)
    local idOk, id = pcall(tostring, obj)
    if not idOk or not id then return end
    if D.S.seen[id] then D.S.stats.skip=D.S.stats.skip+1; return end
    D.S.seen[id] = true

    local skipReason
    pcall(function()
        if C.isServerScript(obj) then
            skipReason="server"; D.S.stats.server_skip=D.S.stats.server_skip+1
        end
    end)

    local bcHash
    if D.has.getscriptbytecode and not skipReason then
        bcHash = C.getScriptHash(obj)
        if bcHash=="EMPTY" then
            skipReason="empty"; D.S.stats.empty_skip=D.S.stats.empty_skip+1
        elseif bcHash and D.S.seenHash[bcHash] then
            D.S.cacheStats.dedup=D.S.cacheStats.dedup+1
            D.S.stats.dedup=(D.S.stats.dedup or 0)+1
        end
        if bcHash and bcHash~="EMPTY" then D.S.seenHash[bcHash]=true end
    end

    D.S.stats.total=D.S.stats.total+1
    C.trackSource(from)

    if skipReason and not D.S.dumpSkipped then
        D.S.skipped[#D.S.skipped+1] = {
            name=pcall(function() return obj.Name end) and obj.Name or "?",
            path=C.safeName(obj),
            class=pcall(function() return obj.ClassName end) and obj.ClassName or "?",
            reason=skipReason, from=from,
        }
        return
    end
    D.S.queue[#D.S.queue+1] = {inst=obj, from=from, bcHash=bcHash}
end

-- ══ CHECK REMOTE — v15 adaptive arg analysis ══
function C.checkRemote(obj)
    if not D.cfg.dumpRemotes then return end
    local ok,cn = pcall(function() return obj.ClassName end)
    if not ok or not REM_CLS[cn] then return end
    local idOk, id = pcall(tostring, obj)
    if not idOk then return end
    if D.S.remoteSeen[id] then return end
    D.S.remoteSeen[id]=true
    pcall(function()
        local info = {
            class=cn, name=obj.Name, path=C.safeName(obj),
            parent=obj.Parent and C.safeName(obj.Parent) or "nil",
            callbacks={}, connectionCount=0, argInfo={},
        }

        -- Helper: infer argument types from constants list
        local function inferArgTypes(consts, numParams)
            local args = {}
            if not consts or not numParams or numParams == 0 then return args end

            -- Build a set of all string constants for pattern matching
            local constSet = {}
            local constStrs = {}
            for _, v in ipairs(consts) do
                if type(v) == "string" then
                    constSet[v] = true
                    constStrs[#constStrs+1] = v
                end
            end

            -- Type indicators from constants
            local indicators = {
                number = {"tonumber","math","floor","ceil","abs","clamp","random","min","max","huge","inf"},
                string = {"tostring","string","sub","find","match","gmatch","gsub","lower","upper","split","len","format","byte","char","rep"},
                boolean = {"true","false"},
                Instance = {"FindFirstChild","FindFirstChildOfClass","WaitForChild","IsA","GetChildren","GetDescendants","Clone","Destroy","Parent","Instance"},
                CFrame = {"CFrame","lookAt","Angles","fromEulerAngles","fromMatrix","fromOrientation"},
                Vector3 = {"Vector3","magnitude","unit","Lerp","Cross","Dot"},
                Color3 = {"Color3","fromRGB","fromHSV","fromHex"},
                table = {"table","insert","remove","sort","concat","unpack","pack"},
                Player = {"Player","UserId","Character","Backpack","leaderstats","DisplayName"},
                Enum = {"Enum","KeyCode","Material","HumanoidStateType"},
            }

            -- Score each type
            local scores = {}
            for typeName, keywords in pairs(indicators) do
                scores[typeName] = 0
                for _, kw in ipairs(keywords) do
                    if constSet[kw] then
                        scores[typeName] = scores[typeName] + 1
                    end
                end
            end

            -- Assign types to each parameter based on score + position heuristics
            for i = 1, numParams do
                local argType = "any"
                local bestScore = 0

                -- First arg often relates to the strongest signal
                for typeName, score in pairs(scores) do
                    if score > bestScore then
                        bestScore = score
                        argType = typeName
                    end
                end

                -- Positional heuristics
                if numParams == 1 then
                    -- Single arg: use best match
                    if bestScore > 0 then
                        args[i] = {type=argType, confidence="medium"}
                    else
                        args[i] = {type="any", confidence="low"}
                    end
                else
                    -- Multiple args: distribute types
                    -- Remove used type from scores for variety
                    if bestScore > 0 and i <= 3 then
                        args[i] = {type=argType, confidence=bestScore >= 2 and "high" or "medium"}
                        scores[argType] = 0 -- don't reuse
                    else
                        args[i] = {type="any", confidence="low"}
                    end
                end
            end
            return args
        end

        -- Callback analysis with deep arg inference
        if D.has.getcallbackvalue then
            local cbNames = ({
                BindableEvent={"Event"}, BindableFunction={"OnInvoke"},
                RemoteEvent={"OnClientEvent"}, RemoteFunction={"OnClientInvoke"},
                UnreliableRemoteEvent={"OnClientEvent"},
            })[cn] or {}
            for _,cbN in ipairs(cbNames) do
                pcall(function()
                    local cb = getcallbackvalue(obj,cbN)
                    if cb then
                        local cbInfo = {
                            name=cbN,
                            type=D.has.iscclosure and (iscclosure(cb) and "C" or "Lua") or "?",
                        }

                        -- debug.getinfo for param count
                        if D.has["debug.getinfo"] then
                            pcall(function()
                                local di = debug.getinfo(cb)
                                if di then
                                    cbInfo.numParams = di.numparams or di.nparams
                                    cbInfo.isVararg = di.is_vararg or di.isvararg
                                end
                            end)
                        end

                        -- Get constants for type inference
                        local allConsts = {}
                        if D.has.getconstants then
                            pcall(function()
                                local consts = getconstants(cb)
                                if consts then
                                    local strs = {}
                                    for _, v in ipairs(consts) do
                                        if type(v) == "string" and #v > 0 and #v < 80 then
                                            strs[#strs+1] = v
                                            allConsts[#allConsts+1] = v
                                        end
                                    end
                                    if #strs > 0 then cbInfo.constants = strs end
                                end
                            end)
                        end

                        -- Get proto constants too for deeper inference
                        if D.has.getprotos and D.has.getconstants then
                            pcall(function()
                                local protos = getprotos(cb)
                                if protos then
                                    for pi = 1, math.min(#protos, 10) do
                                        pcall(function()
                                            local pc = getconstants(protos[pi])
                                            if pc then
                                                for _, v in ipairs(pc) do
                                                    if type(v) == "string" and #v > 0 and #v < 80 then
                                                        allConsts[#allConsts+1] = v
                                                    end
                                                end
                                            end
                                        end)
                                    end
                                end
                            end)
                        end

                        -- Get upvalue types for inference
                        if D.has.getupvalues then
                            pcall(function()
                                local ups = getupvalues(cb)
                                if ups then
                                    local uvTypes = {}
                                    local tc = 0
                                    for k, v in pairs(ups) do
                                        tc = tc + 1; if tc > 20 then break end
                                        uvTypes[#uvTypes+1] = {
                                            index = tostring(k),
                                            valType = type(v),
                                            val = type(v) == "string" and v:sub(1,60) or tostring(v):sub(1,60),
                                        }
                                    end
                                    if #uvTypes > 0 then cbInfo.upvalueTypes = uvTypes end
                                end
                            end)
                        end

                        -- Infer argument types adaptively
                        if cbInfo.numParams and cbInfo.numParams > 0 then
                            cbInfo.inferredArgs = inferArgTypes(allConsts, cbInfo.numParams)
                        end

                        info.callbacks[#info.callbacks+1] = cbInfo
                    end
                end)
            end
        end

        -- Connection count via getconnections + handler analysis
        if D.has.getconnections then
            pcall(function()
                local sig
                if cn == "RemoteEvent" or cn == "UnreliableRemoteEvent" then
                    sig = obj.OnClientEvent
                elseif cn == "BindableEvent" then
                    sig = obj.Event
                end
                if sig then
                    local conns = getconnections(sig)
                    info.connectionCount = conns and #conns or 0

                    -- Analyze connected handler functions for more arg info
                    if conns and #conns > 0 then
                        local handlerArgs = {}
                        for ci = 1, math.min(#conns, 5) do
                            pcall(function()
                                local fn = conns[ci].Function
                                if not fn then return end
                                if D.has["debug.getinfo"] then
                                    pcall(function()
                                        local di = debug.getinfo(fn)
                                        if di then
                                            handlerArgs[#handlerArgs+1] = {
                                                params = di.numparams or di.nparams,
                                                vararg = di.is_vararg or di.isvararg,
                                            }
                                        end
                                    end)
                                end
                            end)
                        end
                        if #handlerArgs > 0 then info.handlerArgs = handlerArgs end
                    end
                end
            end)
        end
        D.S.remotes[#D.S.remotes+1]=info
        D.S.stats.remotes=D.S.stats.remotes+1
    end)
end

-- ══ PROCESS LIST — safe single-item processing ══
function C.processListSafe(list, from, maxCount)
    if not list or #list == 0 then return end
    local max = math.min(#list, maxCount or D.limits.maxDescendants)
    local dumpRemotes = D.cfg.dumpRemotes
    for i = 1, max do
        if D.S.cancel then return end
        local itemOk = pcall(function()
            local obj = list[i]
            if not obj then return end
            pcall(function()
                if C.isScript(obj) then C.enqueue(obj, from) end
            end)
            if dumpRemotes then
                pcall(function() C.checkRemote(obj) end)
            end
        end)
        if not C.safeTick(i) then return end
    end
end

-- ══ PROCESS LIST — mode-adaptive ══
function C.processObjList(list, from, maxCount)
    if not list or #list == 0 then return end
    local max = math.min(#list, maxCount or D.limits.maxDescendants)
    local mode = D.cfg.mode or "normal"
    local dumpRemotes = D.cfg.dumpRemotes

    if mode == "turbo" then
        local chunk = D.limits.chunkProcess
        for start = 1, max, chunk do
            if D.S.cancel then return end
            pcall(function()
                local stop = math.min(start + chunk - 1, max)
                for i = start, stop do
                    local obj = list[i]
                    if obj then
                        pcall(function()
                            if C.isScript(obj) then C.enqueue(obj, from) end
                            if dumpRemotes then C.checkRemote(obj) end
                        end)
                    end
                end
            end)
            C.tickBulk(chunk)
        end
    elseif mode == "safe" then
        C.processListSafe(list, from, max)
    else
        for i = 1, max do
            if D.S.cancel then return end
            pcall(function()
                local obj = list[i]
                if C.isScript(obj) then C.enqueue(obj, from) end
                if dumpRemotes then C.checkRemote(obj) end
            end)
            C.tick()
        end
    end
end

end