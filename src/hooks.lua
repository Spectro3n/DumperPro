return function(D)
local M = {}
D.Hooks = M
local C, has = D.Core, D.has
local Decomp = D.Decompile

local decompBudget, decompUsed = 0, 0

local function budgetDecomp(fn, timeout)
    if decompUsed >= decompBudget or not has.decompile then return nil end
    if has.iscclosure then
        local isC = false
        pcall(function() isC = iscclosure(fn) end)
        if isC then return nil end
    end
    decompUsed = decompUsed + 1
    local ok, src = C.timedCall(decompile, timeout or 3, fn)
    if ok and type(src) == "string" and #src > 4 then
        return src:gsub("%z","\\0"):sub(1,5000)
    end
    return nil
end

local function testGetConnections()
    if not has.getconnections then return false end
    local ok = pcall(function()
        local be = Instance.new("BindableEvent")
        local conn = be.Event:Connect(function() end)
        local _ = getconnections(be.Event)
        conn:Disconnect()
        be:Destroy()
    end)
    return ok
end

local function safeIdentify(fn)
    if not fn then return "~nil","nil","?" end
    if has.iscclosure then
        local isC = false
        pcall(function() isC = iscclosure(fn) end)
        if isC then return "~C_closure","C_closure","C" end
    end
    local p,n,cl = "unknown","unknown","?"
    pcall(function() p,n,cl = Decomp.identifyScript(fn) end)
    return p,n,cl
end

-- Build detailed hook entry
local function buildHookEntry(hookType, fn, detail)
    local h = { type=hookType, status="?", detail=detail or tostring(fn) }

    if has.iscclosure then
        pcall(function() h.status = iscclosure(fn) and "original" or "HOOKED" end)
    end

    if h.status == "HOOKED" or h.status == "?" then
        -- Decompile source
        h.source = budgetDecomp(fn, 4)

        -- Constants
        if has.getconstants then
            pcall(function()
                local c = getconstants(fn)
                if not c then return end
                local strs = {}
                for _, v in ipairs(c) do
                    if type(v) == "string" and #v > 0 and #v < 80 then strs[#strs+1] = v end
                end
                if #strs > 0 then h.constants = strs end
            end)
        end

        -- Upvalues
        if has.getupvalues then
            pcall(function()
                local ups = getupvalues(fn)
                if ups then
                    local upInfo = {}
                    local count = 0
                    for k, v in pairs(ups) do
                        count = count + 1
                        if count > 20 then break end
                        upInfo[#upInfo+1] = string.format("[%s] %s = %s", tostring(k), type(v), tostring(v):sub(1,80))
                    end
                    if #upInfo > 0 then h.upvalues = upInfo end
                end
            end)
        end

        -- Debug info
        if has["debug.getinfo"] then
            pcall(function()
                local di = debug.getinfo(fn)
                if di then
                    h.debugInfo = {
                        name = di.name,
                        source = di.source or di.short_src,
                        numParams = di.numparams or di.nparams,
                        lineStart = di.linedefined,
                        lineEnd = di.lastlinedefined,
                    }
                end
            end)
        end

        -- Script origin
        local p = safeIdentify(fn)
        if p ~= "unknown" and not p:find("^~") then h.scriptSource = p end
    end

    return h
end

-- ══ METATABLE HOOKS — all modes ══
local function analyzeMetatable()
    if not has.getrawmetatable then return end
    C.safeScan("MT_Hooks", function()
        local ok, mt = pcall(getrawmetatable, game)
        if not ok or not mt then return end
        for _, mn in ipairs({"__namecall","__index","__newindex","__tostring","__eq","__len","__call"}) do
            pcall(function()
                local fn = rawget(mt, mn)
                if not fn or type(fn) ~= "function" then return end
                local h = buildHookEntry("game."..mn, fn, tostring(fn))
                D.S.hooks[#D.S.hooks+1] = h
                D.S.stats.hooks = D.S.stats.hooks + 1
            end)
        end
    end)
end

-- ══ GLOBAL FUNCTION HOOKS — detect replaced globals ══
local function analyzeGlobalHooks()
    C.safeScan("GlobalHooks", function()
        D.UI:Log("    → Checking global function hooks", "gray")
        local globals = {
            "print","warn","error","require","spawn","delay",
            "tick","time","wait","typeof","type","tostring",
            "tonumber","select","pcall","xpcall","rawget","rawset",
            "setmetatable","getmetatable","coroutine.wrap","coroutine.resume",
        }
        for _, gName in ipairs(globals) do
            pcall(function()
                local fn
                if gName:find(".",1,true) then
                    local parts = gName:split(".")
                    local t = getfenv()[parts[1]] or _G[parts[1]]
                    if t then fn = t[parts[2]] end
                else
                    fn = getfenv()[gName] or _G[gName]
                end
                if not fn or type(fn) ~= "function" then return end
                if has.iscclosure then
                    local isC = false
                    pcall(function() isC = iscclosure(fn) end)
                    if not isC then
                        -- This global was replaced with a Lua closure = HOOKED
                        local h = buildHookEntry("global."..gName, fn, "Global function replaced")
                        h.status = "HOOKED"
                        D.S.hooks[#D.S.hooks+1] = h
                        D.S.stats.hooks = D.S.stats.hooks + 1
                    end
                end
            end)
        end
    end)
end

-- ══ REMOTE CALLBACKS — enhanced with arg analysis ══
local function analyzeRemoteCallbacks()
    if not has.getcallbackvalue then return end
    local svcs = {"ReplicatedStorage","Workspace","StarterGui","Lighting","StarterPack","StarterPlayer","Chat","SoundService"}
    for _, svcName in ipairs(svcs) do
        if D.S.cancel then break end
        C.safeScan("RemCB:"..svcName, function()
            local svc = game:GetService(svcName)
            local ok, desc = pcall(function() return svc:GetDescendants() end)
            if not ok or not desc then return end
            local limit = math.min(#desc, D.limits.hooksPerService)
            local batch = 0
            for i = 1, limit do
                if D.S.cancel then break end
                batch = batch + 1
                pcall(function()
                    local obj = desc[i]
                    local cbName
                    if obj:IsA("RemoteEvent") or obj:IsA("UnreliableRemoteEvent") then
                        cbName = "OnClientEvent"
                    elseif obj:IsA("RemoteFunction") then
                        cbName = "OnClientInvoke"
                    end
                    if not cbName then return end
                    local cbOk, cb = pcall(getcallbackvalue, obj, cbName)
                    if not cbOk or not cb then return end
                    local h = buildHookEntry(obj.ClassName:sub(1,2)..":"..obj.Name, cb, C.safeName(obj))
                    D.S.hooks[#D.S.hooks+1] = h
                    D.S.stats.hooks = D.S.stats.hooks + 1
                end)
                if batch % 20 == 0 then C.yieldNow() end
                C.tick()
            end
            desc = nil
        end)
        C.yieldNow()
    end
end

-- ══ PROPERTY HOOKS — check common instances ══
local function analyzePropertyHooks()
    if not has.getrawmetatable then return end
    C.safeScan("PropHooks", function()
        D.UI:Log("    → Checking property hooks", "gray")
        local targets = {}
        pcall(function() targets[#targets+1] = {name="Workspace", obj=workspace} end)
        pcall(function() targets[#targets+1] = {name="Camera", obj=workspace.CurrentCamera} end)
        pcall(function() targets[#targets+1] = {name="Players", obj=C.Players} end)
        pcall(function() targets[#targets+1] = {name="LP", obj=C.LP} end)
        pcall(function()
            if C.LP.Character then
                targets[#targets+1] = {name="Character", obj=C.LP.Character}
                local hrp = C.LP.Character:FindFirstChild("HumanoidRootPart")
                if hrp then targets[#targets+1] = {name="HRP", obj=hrp} end
            end
        end)

        for _, tgt in ipairs(targets) do
            pcall(function()
                local mt = getrawmetatable(tgt.obj)
                if not mt then return end
                for _, mn in ipairs({"__index","__newindex","__namecall"}) do
                    pcall(function()
                        local fn = rawget(mt, mn)
                        if fn and type(fn) == "function" then
                            local h = buildHookEntry(tgt.name.."."..mn, fn, tgt.name.." metatable")
                            D.S.hooks[#D.S.hooks+1] = h
                            D.S.stats.hooks = D.S.stats.hooks + 1
                        end
                    end)
                end
            end)
        end
    end)
end

-- ══ HTTP HOOKS — check request functions ══
local function analyzeHttpHooks()
    C.safeScan("HttpHooks", function()
        D.UI:Log("    → Checking HTTP hooks", "gray")
        local httpFns = {
            {name="HttpGet", obj=game, method="HttpGet"},
            {name="HttpPost", obj=game, method="HttpPost"},
        }

        -- Check request/syn/http_request
        local reqFn
        pcall(function() reqFn = getfenv().request or getfenv().http_request or (syn and syn.request) end)
        if reqFn and type(reqFn) == "function" then
            pcall(function()
                if has.iscclosure then
                    local isC = false
                    pcall(function() isC = iscclosure(reqFn) end)
                    if not isC then
                        local h = buildHookEntry("http.request", reqFn, "HTTP request function")
                        h.status = "HOOKED"
                        D.S.hooks[#D.S.hooks+1] = h
                        D.S.stats.hooks = D.S.stats.hooks + 1
                    end
                end
            end)
        end
    end)
end

-- ══ GC FUNCTION COMPARISON — detect wrapped closures ══
local function analyzeGCFunctionHooks()
    if not has.getgc or not has.iscclosure then return end
    C.safeScan("GCFuncHooks", function()
        D.UI:Log("    → Scanning GC for hook wrappers", "gray")
        C.deepClean()
        local ok, gc = C.dangerousCall("gc_hook_scan", getgc, false)
        if not ok or not gc then return end

        local found = 0
        local sz = math.min(#gc, 5000)
        for i = 1, sz do
            if D.S.cancel or found > 30 then break end
            pcall(function()
                local fn = gc[i]
                if type(fn) ~= "function" then return end
                local isC = false
                pcall(function() isC = iscclosure(fn) end)
                if isC then return end

                -- Check if this Lua function wraps a known pattern
                if has.getupvalues then
                    pcall(function()
                        local ups = getupvalues(fn)
                        if not ups then return end
                        for _, uv in pairs(ups) do
                            if type(uv) == "function" then
                                local uvC = false
                                pcall(function() uvC = iscclosure(uv) end)
                                if uvC then
                                    -- Lua function wrapping C closure = possible hook
                                    local p, n, cl = safeIdentify(fn)
                                    if p ~= "unknown" and not p:find("^~") then
                                        local h = buildHookEntry("wrapper:"..n, fn, "Lua wrapper around C closure at "..p)
                                        h.status = "HOOKED"
                                        h.wrappedOriginal = tostring(uv)
                                        D.S.hooks[#D.S.hooks+1] = h
                                        D.S.stats.hooks = D.S.stats.hooks + 1
                                        found = found + 1
                                    end
                                end
                            end
                        end
                    end)
                end
            end)
            if i % 200 == 0 then C.yieldNow() end
        end
        gc = nil
        if found > 0 then D.UI:Log("      Found "..found.." wrapper hooks", "green") end
    end)
end

-- ══ CONNECTION SPY — enhanced with more signals ══
local function analyzeConnections()
    local gcOk = testGetConnections()
    if not gcOk then
        D.UI:Log("    ⚠ getconnections pre-flight failed","yellow")
        D.S.scanErrors[#D.S.scanErrors+1] = {section="ConnSpy", error="pre-flight failed"}
        return
    end

    local signals = {}
    pcall(function() signals[#signals+1] = {name="Heartbeat",      sig=C.Run.Heartbeat} end)
    pcall(function() signals[#signals+1] = {name="Stepped",        sig=C.Run.Stepped} end)
    pcall(function() signals[#signals+1] = {name="PlayerAdded",    sig=C.Players.PlayerAdded} end)
    pcall(function() signals[#signals+1] = {name="RenderStepped",  sig=C.Run.RenderStepped} end)
    pcall(function() signals[#signals+1] = {name="InputBegan",     sig=C.UIS.InputBegan} end)
    pcall(function() signals[#signals+1] = {name="InputEnded",     sig=C.UIS.InputEnded} end)
    pcall(function() signals[#signals+1] = {name="InputChanged",   sig=C.UIS.InputChanged} end)
    pcall(function() signals[#signals+1] = {name="CharAdded",      sig=C.LP.CharacterAdded} end)
    pcall(function() signals[#signals+1] = {name="CharRemoving",   sig=C.LP.CharacterRemoving} end)
    pcall(function() signals[#signals+1] = {name="Chatted",        sig=C.LP.Chatted} end)
    pcall(function() signals[#signals+1] = {name="WS.ChildAdded",  sig=workspace.ChildAdded} end)
    pcall(function() signals[#signals+1] = {name="WS.ChildRemoved",sig=workspace.ChildRemoved} end)
    pcall(function() signals[#signals+1] = {name="PlayerRemoving", sig=C.Players.PlayerRemoving} end)
    pcall(function() signals[#signals+1] = {name="RS.ChildAdded",  sig=game:GetService("ReplicatedStorage").ChildAdded} end)
    pcall(function() signals[#signals+1] = {name="WS.DescAdded",   sig=workspace.DescendantAdded} end)
    pcall(function() signals[#signals+1] = {name="WS.DescRemoved", sig=workspace.DescendantRemoving} end)

    for _, def in ipairs(signals) do
        if D.S.cancel then break end
        pcall(function()
            local connOk, conns = pcall(getconnections, def.sig)
            if not connOk or not conns then return end
            local limit = math.min(#conns, D.limits.connLimit)
            for ci = 1, limit do
                pcall(function()
                    local conn = conns[ci]
                    if not conn then return end
                    local sPath, sName, sCls = "unknown","unknown","?"
                    local fType, enabled = "nil", true
                    pcall(function() enabled = conn.Enabled ~= false end)
                    if conn.Function then
                        sPath, sName, sCls = safeIdentify(conn.Function)
                        fType = sCls == "C" and "C" or "Lua"
                    end
                    D.S.connections[#D.S.connections+1] = {
                        signal=def.name, enabled=enabled, script=sPath,
                        scriptName=sName, scriptClass=sCls, funcType=fType,
                    }
                end)
            end
        end)
        C.yieldNow()
    end
end

-- ══ ENTRY POINT ══
function M.analyze()
    D.UI:Log("  → hooks & connections (ALL modes — v14 deep scan)", "orange")

    if not C.memoryGuard() then
        D.UI:Log("  ⚠ Memory too high — pausing 2s","red")
        task.wait(2)
        C.memoryGuard()
    end

    decompBudget = D.limits.hookDecompBudget
    decompUsed = 0

    analyzeMetatable()
    C.yieldNow()
    analyzeGlobalHooks()
    C.yieldNow()
    analyzePropertyHooks()
    C.yieldNow()
    analyzeHttpHooks()
    C.yieldNow()
    analyzeRemoteCallbacks()
    C.yieldNow()
    analyzeGCFunctionHooks()
    C.yieldNow()
    analyzeConnections()

    D.UI:Log(string.format("    %d hooks, %d connections, budget %d/%d",
        #D.S.hooks, #D.S.connections, decompUsed, decompBudget), "green")
end

end