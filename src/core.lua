return function(D)
local C = {}
D.Core = C

C.Players = game:GetService("Players")
C.Run     = game:GetService("RunService")
C.Http    = game:GetService("HttpService")
C.UIS     = game:GetService("UserInputService")
C.Tags    = game:GetService("CollectionService")
C.LP      = C.Players.LocalPlayer

-- ══ MODE CONFIG — nothing is skipped, only protection level changes ══
C.MODES = {
    safe = {
        yieldEvery       = 2,       -- yield very often
        gcLimit          = 80000,   -- still scan a LOT
        decompileTimeout = 30,      -- patient decompile
        maxNilDepth      = 3,       -- 3 levels deep
        hooksPerService  = 500,     -- scan all hooks
        connLimit        = 15,      -- all connections
        hookDecompBudget = 10,      -- some decompile budget
        maxDescendants   = 50000,   -- large scan
        batchSize        = 1,       -- process 1 at a time
        memCheckEvery    = 3,       -- very frequent mem checks
        gcStepSize       = 30,      -- gentle GC
        chunkProcess     = 30,      -- small chunks with pcall each
        cacheHitBatch    = 4,       -- yield often even on cache
        upvalueDepth     = 4,       -- upvalue chain depth
        maxTags          = 500,     -- tag scan limit
        maxModTrace      = 600,     -- module trace limit
        logEvery         = 8,       -- log frequency
    },
    normal = {
        yieldEvery       = 12,
        gcLimit          = 60000,
        decompileTimeout = 12,
        maxNilDepth      = 3,
        hooksPerService  = 600,
        connLimit        = 12,
        hookDecompBudget = 25,
        maxDescendants   = 30000,
        batchSize        = 3,
        memCheckEvery    = 15,
        gcStepSize       = 100,
        chunkProcess     = 150,
        cacheHitBatch    = 20,
        upvalueDepth     = 5,
        maxTags          = 500,
        maxModTrace      = 600,
        logEvery         = 10,
    },
    turbo = {
        yieldEvery       = 80,
        gcLimit          = 150000,
        decompileTimeout = 5,
        maxNilDepth      = 4,
        hooksPerService  = 1200,
        connLimit        = 30,
        hookDecompBudget = 80,
        maxDescendants   = 100000,
        batchSize        = 12,
        memCheckEvery    = 60,
        gcStepSize       = 250,
        chunkProcess     = 500,
        cacheHitBatch    = 60,
        upvalueDepth     = 7,
        maxTags          = 800,
        maxModTrace      = 1000,
        logEvery         = 25,
    },
}

-- ══ PROBES ══
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

local SCRIPT_CLS = {LocalScript=true, ModuleScript=true, Script=true}
C.SCRIPT_CLS = SCRIPT_CLS

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

-- ══ MEMORY ══
function C.getMemKB()
    local ok,m = pcall(gcinfo); return ok and m or 0
end

function C.memoryGuard()
    local mem = C.getMemKB()
    if mem > 800000 then
        pcall(collectgarbage,"collect"); task.wait(1.2)
        D.UI:Log("⚠ Mem critical: "..math.floor(mem/1024).."MB — cleaning","red")
        mem = C.getMemKB()
        if mem > 750000 then return false end
    elseif mem > 500000 then
        pcall(collectgarbage,"step", D.limits.gcStepSize * 3); task.wait(0.3)
    elseif mem > 350000 then
        pcall(collectgarbage,"step", D.limits.gcStepSize)
    end
    return true
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

-- Safe: yield + memory check combo
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
    task.spawn(function() rok, rval = pcall(fn, unpack(args)); done = true end)
    local t0 = os.clock()
    while not done do
        if os.clock()-t0 > timeout then return false, "Timeout" end
        task.wait(0.08)
    end
    return rok, rval
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
    local id = tostring(obj)
    if D.S.seen[id] then D.S.stats.skip=D.S.stats.skip+1; return end
    D.S.seen[id] = true

    local skipReason
    if C.isServerScript(obj) then
        skipReason="server"; D.S.stats.server_skip=D.S.stats.server_skip+1
    end

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

-- ══ CHECK REMOTE ══
function C.checkRemote(obj)
    if not D.cfg.dumpRemotes then return end
    local ok,cn = pcall(function() return obj.ClassName end)
    if not ok or not REM_CLS[cn] then return end
    local id = tostring(obj)
    if D.S.remoteSeen[id] then return end
    D.S.remoteSeen[id]=true
    pcall(function()
        local info = {
            class=cn, name=obj.Name, path=C.safeName(obj),
            parent=obj.Parent and C.safeName(obj.Parent) or "nil",
            callbacks={}, connectionCount=0,
        }
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
                        info.callbacks[#info.callbacks+1] = {
                            name=cbN,
                            type=D.has.iscclosure and (iscclosure(cb) and "C" or "Lua") or "?",
                        }
                    end
                end)
            end
        end
        D.S.remotes[#D.S.remotes+1]=info
        D.S.stats.remotes=D.S.stats.remotes+1
    end)
end

-- ══ PROCESS LIST — mode-adaptive, NEVER skips ══
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
                        if C.isScript(obj) then C.enqueue(obj, from) end
                        if dumpRemotes then C.checkRemote(obj) end
                    end
                end
            end)
            C.tickBulk(chunk)
        end
    elseif mode == "safe" then
        for i = 1, max do
            if D.S.cancel then return end
            pcall(function()
                local obj = list[i]
                if C.isScript(obj) then C.enqueue(obj, from) end
                if dumpRemotes then C.checkRemote(obj) end
            end)
            if not C.safeTick(i) then return end
        end
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