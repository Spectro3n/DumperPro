local BASE = ... or "https://raw.githubusercontent.com/Spectro3n/DumperPro/main/src/"

local UI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Spectro3n/DumperUI/refs/heads/main/DumperUI.lua"
))()

local D = { UI = UI }

local moduleStatus = {}

local function loadMod(name, required)
    local ok, err = pcall(function()
        local code = game:HttpGet(BASE..name..".lua")
        local fn = loadstring(code)()
        fn(D)
    end)
    moduleStatus[name] = ok
    if not ok then
        UI:Log("⚠ Module "..name.." failed: "..tostring(err):sub(1,80), "red")
        if required then UI:Log("CRITICAL — cannot continue without "..name, "red") end
    end
    task.wait(0.1)
    return ok
end

if not loadMod("core", true) then return end
if not loadMod("decompile", true) then return end
if not loadMod("collect", true) then return end
loadMod("hooks", false)
loadMod("output", false)

local C   = D.Core
local has = D.has

local processingThread = nil

local function onDone()
    if D.Output and D.Output.saveAll then D.Output.saveAll() end

    -- Unfreeze game after completion
    pcall(function() C.unfreezeGame() end)

    D.UI:SetPhase("done")
    D.UI:SetRunning(false)

    local stopped = D.S.cancel
    D.UI:SetBadge(stopped and "Stopped" or "Done", stopped and "red" or "green")
    D.UI:SetProgress(D.S.stats.ok+D.S.stats.fail, math.max(D.S.stats.queued,1))
    C.push()

    D.UI:Log("═══════════════════════════", "green")
    D.UI:Log(string.format("%s — %d/%d — cache:%d — aggressive:%d — %s",
        stopped and "STOPPED" or "DONE",
        D.S.stats.ok, D.S.stats.total,
        D.S.cacheStats.hits, D.S.stats.aggressive,
        C.elapsed()), "green")
    D.UI:Log("Folder: "..D.S.rootDir.."/", "green")
    D.UI:Log("═══════════════════════════", "green")
    D.UI:SetStatus("✓ "..D.S.stats.ok.."/"..D.S.stats.total.." · "..C.elapsed())
end

-- ══════════════════════════════════
--  v14: ANTI-CRASH PROCESSING LOOP
--  Micro-batch + adaptive throttle + emergency flush
-- ══════════════════════════════════

local function startProcessing()
    D.UI:SetPhase("decompiling")
    D.UI:Log("Processing "..#D.S.queue.." scripts...", "blue")

    local mode = D.cfg.mode or "normal"
    local gcStep = D.limits.gcStepSize
    local logEvery = D.limits.logEvery
    local memCheckEvery = D.limits.memCheckEvery

    processingThread = task.spawn(function()
        local processed = 0

        while #D.S.queue > 0 and not D.S.cancel do
            -- Adaptive batch: shrinks as memory grows
            local batchCount = C.adaptiveBatchSize()

            for b = 1, batchCount do
                if #D.S.queue == 0 or D.S.cancel then break end
                local entry = table.remove(D.S.queue, 1)

                -- Per-item pcall: protects against crash
                local processOk = pcall(function()
                    D.Decompile.processOne(entry)
                end)

                if not processOk then
                    D.S.stats.fail = D.S.stats.fail + 1
                end

                processed = processed + 1

                -- Progress logging
                if processed % logEvery == 0 then
                    D.UI:Log(string.format("  %d/%d (%d cached, %d fail) mem:%dMB %s",
                        D.S.stats.ok+D.S.stats.fail, D.S.stats.queued,
                        D.S.cacheStats.hits, D.S.stats.fail,
                        C.getMemMB(), C.elapsed()), "gray")
                end

                -- Nil out entry reference immediately
                entry = nil
            end

            -- ALWAYS yield after every micro-batch
            task.wait()

            -- Incremental GC every batch
            pcall(collectgarbage, "step", gcStep)

            -- Full memory check periodically
            if processed % memCheckEvery == 0 then
                if not C.memoryGuard() then
                    -- Emergency: pause, flush, retry
                    D.UI:Log("🚨 Memory critical at "..processed.."/"..D.S.stats.queued.." — emergency pause", "red")
                    C.emergencyFlush()
                    task.wait(D.limits.emergencyPauseSec or 3)
                    if not C.memoryGuard() then
                        D.UI:Log("🚨 Still critical — saving and stopping", "red")
                        D.S.cancel = true
                    else
                        D.UI:Log("  Memory recovered: "..C.getMemMB().."MB — resuming", "yellow")
                    end
                end
            end
        end

        onDone()
        processingThread = nil
    end)
end

local function startDump()
    D.cfg = UI:GetConfig()
    C.resetState()

    D.UI:SetRunning(true)
    D.UI:ClearLog()
    D.UI:SetProgress(0, 1)

    local mode = D.cfg.mode or "normal"

    D.UI:Log("═══════════════════════════", "blue")
    D.UI:Log("DUMP PRO v14: "..D.S.rootDir, "blue")
    D.UI:Log("Mode: "..mode:upper().." — ALL SCANNERS + v14 DEEP", "blue")
    D.UI:Log("Anti-Crash: 4-tier memory + adaptive batch + emergency flush", "blue")
    D.UI:Log("Limits: batch="..D.limits.microBatchMax
        .." gc="..D.limits.gcStepSize
        .." timeout="..D.limits.decompileTimeout.."s"
        .." maxMem="..D.limits.maxMemoryMB.."MB", "blue")
    D.UI:Log("Cache: "..(next(D.cache.bytecode) and "WARM" or "cold"), "blue")
    D.UI:Log("Memory: "..C.getMemMB().."MB", "blue")

    local mods = {}
    for name, ok in pairs(moduleStatus) do mods[#mods+1] = name..(ok and "✓" or "✗") end
    D.UI:Log("Modules: "..table.concat(mods," "), "blue")
    D.UI:Log("═══════════════════════════", "blue")

    -- v14: Freeze game before extraction
    D.UI:Log("🧊 Freezing game for clean extraction...", "blue")
    pcall(function() C.freezeGame() end)
    D.UI:Log("  Game frozen — extracting safely", "green")
    task.wait(0.3)

    -- Collect
    D.Collect.collectAll()

    if D.S.cancel then
        pcall(function() C.unfreezeGame() end)
        D.UI:SetRunning(false); D.UI:SetBadge("Stopped","red"); return
    end

    -- Hooks
    if D.Hooks and D.Hooks.analyze then
        C.memoryGuard(); task.wait(0.15)
        C.safeScan("Hooks", function() D.Hooks.analyze() end)
    end

    if D.S.cancel then
        pcall(function() C.unfreezeGame() end)
        D.UI:SetRunning(false); D.UI:SetBadge("Stopped","red"); return
    end

    if #D.S.queue == 0 then
        D.UI:Log("No scripts found", "yellow")
        onDone(); return
    end

    startProcessing()
end

UI.OnStart = function()
    if processingThread then return end
    task.spawn(startDump)
end

UI.OnStop = function()
    D.S.cancel = true
    D.UI:Log("Stopping...", "yellow")
    pcall(function() C.unfreezeGame() end)
end

UI.OnSaveInstance = function()
    if not has.saveinstance then D.UI:Log("saveinstance unavailable","red"); return end
    D.UI:Log("Running saveinstance...","blue")
    D.UI:SetBadge("Saving","yellow")
    task.spawn(function()
        local ok, err = pcall(saveinstance, {
            ExcludePlayerGui=false, DecompileTimeout=30,
            NilInstances=true, RemovePlayerNames=true,
        })
        if ok then D.UI:Log("Done","green"); D.UI:SetBadge("Done","green")
        else D.UI:Log("Error: "..tostring(err),"red"); D.UI:SetBadge("Error","red") end
    end)
end

local caps = 0
for _, v in pairs(has) do if v then caps = caps + 1 end end

UI:Log("Dumper Pro v14 — Maximum Deep Discovery", "green")
UI:Log("Game: "..UI:GetConfig().folder, "gray")
UI:Log("Caps: "..caps.."/"..#C.PROBES, "gray")
UI:Log("🧊 Game freezes on start for clean extraction", "white")
UI:Log("🛡️ 4-tier anti-crash: adaptive batch + emergency flush", "white")
UI:Log("🔍 21 scanners + 11 decompile strategies", "white")
UI:Log("★ Safe: protected + memory guards (still finds everything)", "gray")
UI:Log("★ Normal: balanced speed + full coverage", "gray")
UI:Log("★ Turbo: max speed, adaptive throttle, crash-proof", "gray")
UI:Log("Press START", "white")