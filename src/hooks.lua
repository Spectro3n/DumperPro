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
        return src:gsub("%z", "\\0"):sub(1, 2000)
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
    if not fn then return "~nil", "nil", "?" end
    if has.iscclosure then
        local isC = false
        pcall(function() isC = iscclosure(fn) end)
        if isC then return "~C_closure", "C_closure", "C" end
    end
    local p, n, cl = "unknown", "unknown", "?"
    pcall(function() p, n, cl = Decomp.identifyScript(fn) end)
    return p, n, cl
end

-- ══ METATABLE HOOKS ══
local function analyzeMetatable()
    if not has.getrawmetatable then return end
    C.safeScan("MT_Hooks", function()
        local ok, mt = pcall(getrawmetatable, game)
        if not ok or not mt then return end
        for _, mn in ipairs({"__namecall","__index","__newindex","__tostring","__eq"}) do
            pcall(function()
                local fn = rawget(mt, mn)
                if not fn or type(fn) ~= "function" then return end
                local h = { type="game."..mn, status="?", detail=tostring(fn) }
                if has.iscclosure then
                    pcall(function() h.status = iscclosure(fn) and "original" or "HOOKED" end)
                end
                if h.status == "HOOKED" then
                    h.source = budgetDecomp(fn, 4)
                    if has.getconstants then
                        pcall(function()
                            local c = getconstants(fn)
                            if not c then return end
                            local strs = {}
                            for _, v in ipairs(c) do
                                if type(v) == "string" and #v > 0 and #v < 60 then
                                    strs[#strs+1] = v
                                end
                            end
                            if #strs > 0 then h.constants = strs end
                        end)
                    end
                    local p = safeIdentify(fn)
                    if p ~= "unknown" and not p:find("^~") then h.scriptSource = p end
                end
                D.S.hooks[#D.S.hooks+1] = h
                D.S.stats.hooks = D.S.stats.hooks + 1
            end)
        end
    end)
end

-- ══ REMOTE CALLBACKS ══
local function analyzeRemoteCallbacks()
    if not has.getcallbackvalue then return end
    if D.limits.skipHooks then return end

    local svcs = {"ReplicatedStorage","Workspace","StarterGui"}
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
                    local h = { type=obj.ClassName:sub(1,2)..":"..obj.Name, status="?", detail=C.safeName(obj) }
                    if has.iscclosure then
                        pcall(function() h.status = iscclosure(cb) and "C" or "HOOKED" end)
                    end
                    if h.status == "HOOKED" then
                        h.source = budgetDecomp(cb, 3)
                        local p = safeIdentify(cb)
                        if p ~= "unknown" and not p:find("^~") then h.scriptSource = p end
                    end
                    D.S.hooks[#D.S.hooks+1] = h
                    D.S.stats.hooks = D.S.stats.hooks + 1
                end)
                if batch % 30 == 0 then C.yieldNow() end
                C.tick()
            end
            desc = nil
        end)
        C.yieldNow()
    end
end

-- ══ CONNECTION SPY ══
local function analyzeConnections()
    if D.limits.skipConnSpy then return end

    local gcOk = testGetConnections()
    if not gcOk then
        D.UI:Log("    ⚠ getconnections pre-flight failed", "yellow")
        D.S.scanErrors[#D.S.scanErrors+1] = { section="ConnSpy", error="pre-flight failed" }
        return
    end

    local m = D.cfg.mode or "normal"
    local signals = {}
    pcall(function() signals[#signals+1] = {name="Heartbeat",   sig=C.Run.Heartbeat} end)
    pcall(function() signals[#signals+1] = {name="Stepped",     sig=C.Run.Stepped} end)
    pcall(function() signals[#signals+1] = {name="PlayerAdded", sig=C.Players.PlayerAdded} end)

    if m == "normal" or m == "turbo" then
        pcall(function() signals[#signals+1] = {name="RenderStepped", sig=C.Run.RenderStepped} end)
        pcall(function() signals[#signals+1] = {name="InputBegan",    sig=C.UIS.InputBegan} end)
        pcall(function() signals[#signals+1] = {name="InputEnded",    sig=C.UIS.InputEnded} end)
        pcall(function() signals[#signals+1] = {name="CharAdded",     sig=C.LP.CharacterAdded} end)
        pcall(function() signals[#signals+1] = {name="Chatted",       sig=C.LP.Chatted} end)
    end

    if m == "turbo" then
        pcall(function() signals[#signals+1] = {name="InputChanged",   sig=C.UIS.InputChanged} end)
        pcall(function() signals[#signals+1] = {name="CharRemoving",   sig=C.LP.CharacterRemoving} end)
        pcall(function() signals[#signals+1] = {name="WS.ChildAdded",  sig=workspace.ChildAdded} end)
        pcall(function() signals[#signals+1] = {name="PlayerRemoving", sig=C.Players.PlayerRemoving} end)
        pcall(function()
            signals[#signals+1] = {name="RS.ChildAdded", sig=game:GetService("ReplicatedStorage").ChildAdded}
        end)
    end

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
                    local sPath, sName, sCls = "unknown", "unknown", "?"
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
    -- Safe mode: skip hooks entirely
    if D.limits.skipHooks and D.limits.skipConnSpy then
        D.UI:Log("  → hooks skipped (safe mode)", "gray")
        return
    end

    D.UI:Log("  → hooks & connections", "orange")

    if not C.memoryGuard() then
        D.UI:Log("  ⚠ Memory too high, skipping hooks", "red")
        return
    end

    decompBudget = D.limits.hookDecompBudget
    decompUsed = 0

    analyzeMetatable()
    C.yieldNow()
    analyzeRemoteCallbacks()
    C.yieldNow()
    analyzeConnections()

    D.UI:Log(string.format("    %d hooks, %d connections, budget %d/%d",
        #D.S.hooks, #D.S.connections, decompUsed, decompBudget), "green")
end

end