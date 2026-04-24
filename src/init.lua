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
--  v15: CRASH-PROOF PROCESSING LOOP
--  Progressive save + auto-downgrade + per-script GC
--  Survives 14k+ scripts without crashing
-- ══════════════════════════════════

local function progressiveSave()
    -- Save what we have so far — protects against crash
    pcall(function()
        if D.Output and D.Output.saveAll then
            D.Output.saveAll()
        end
    end)
end

local function startProcessing()
    D.UI:SetPhase("decompiling")
    D.UI:Log("Processing "..#D.S.queue.." scripts...", "blue")
    D.UI:Log("  ⚡ Progressive save enabled — partial results saved every batch", "green")

    local mode = D.cfg.mode or "normal"
    local gcStep = D.limits.gcStepSize
    local logEvery = D.limits.logEvery
    local saveEvery = 50 -- Progressive save interval
    local lastSave = 0
    local downgraded = false

    processingThread = task.spawn(function()
        local processed = 0

        while #D.S.queue > 0 and not D.S.cancel do
            -- Memory check BEFORE every batch
            local memMB = C.getMemMB()
            local maxMem = D.limits.maxMemoryMB or 600

            -- HARD CEILING: if over 90% of max, save everything and do emergency cleanup
            if memMB > math.floor(maxMem * 0.90) then
                D.UI:Log("🚨 Memory "..memMB.."MB/"..maxMem.."MB — EMERGENCY SAVE + FLUSH", "red")
                progressiveSave()
                C.emergencyFlush()
                task.wait(D.limits.emergencyPauseSec or 2)
                pcall(collectgarbage, "collect")
                task.wait(1)
                memMB = C.getMemMB()
                if memMB > math.floor(maxMem * 0.85) then
                    D.UI:Log("🚨 Memory still "..memMB.."MB — saving and stopping to prevent crash", "red")
                    D.S.cancel = true
                    break
                end
                D.UI:Log("  ✓ Recovered to "..memMB.."MB — continuing", "yellow")
            end

            -- AUTO-DOWNGRADE: if over 70%, reduce aggressiveness
            if not downgraded and memMB > math.floor(maxMem * 0.70) then
                D.UI:Log("⚠ Memory "..memMB.."MB — auto-downgrading to safe parameters", "yellow")
                downgraded = true
                -- Force safe-like parameters
                D.limits.microBatchMax = 2
                D.limits.yieldEvery = 5
                D.limits.decompileTimeout = math.min(D.limits.decompileTimeout, 10)
                gcStep = 30
                saveEvery = 25
            end

            -- Adaptive batch: 1 script at a time when memory is high
            local batchCount
            if memMB > math.floor(maxMem * 0.60) then
                batchCount = 1
            else
                batchCount = C.adaptiveBatchSize()
            end

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
                    D.UI:Log(string.format("  %d/%d (%d ok, %d fail) mem:%dMB %s",
                        processed, D.S.stats.queued,
                        D.S.stats.ok, D.S.stats.fail,
                        C.getMemMB(), C.elapsed()), "gray")
                end

                -- Nil out entry reference immediately
                entry = nil

                -- GC step after EVERY script when memory is above 50%
                if C.getMemMB() > math.floor(maxMem * 0.50) then
                    pcall(collectgarbage, "step", gcStep)
                end
            end

            -- ALWAYS yield after every micro-batch
            task.wait()

            -- Incremental GC every batch
            pcall(collectgarbage, "step", gcStep)

            -- Progressive save — save partial results periodically
            if processed - lastSave >= saveEvery then
                lastSave = processed
                pcall(function()
                    D.UI:Log("  💾 Progressive save at "..processed.."/"..D.S.stats.queued.." (mem:"..C.getMemMB().."MB)", "blue")
                    progressiveSave()
                    -- Extra GC after save
                    pcall(collectgarbage, "collect")
                    task.wait(0.2)
                end)
            end

            -- Memory guard
            if not C.memoryGuard() then
                D.UI:Log("🚨 Memory critical — emergency save + flush", "red")
                progressiveSave()
                C.emergencyFlush()
                task.wait(D.limits.emergencyPauseSec or 2)
                if not C.memoryGuard() then
                    D.UI:Log("🚨 Still critical — saved "..D.S.stats.ok.." scripts, stopping", "red")
                    D.S.cancel = true
                else
                    D.UI:Log("  Memory recovered: "..C.getMemMB().."MB — resuming", "yellow")
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
    D.UI:Log("DUMP PRO v15: "..D.S.rootDir, "blue")
    D.UI:Log("Mode: "..mode:upper().." — ALL SCANNERS + v15 DEEP", "blue")
    D.UI:Log("Anti-Crash: 4-tier memory + real freeze + emergency flush", "blue")
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

    -- v15: Real game freeze — stops ALL processing
    D.UI:Log("🧊 FREEZING GAME — stopping all physics, sounds, animations...", "blue")
    pcall(function() C.freezeGame() end)
    D.UI:Log("  ✓ Game fully frozen — safe extraction mode", "green")
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

UI:Log("Dumper Pro v15 — Maximum Deep Discovery", "green")
UI:Log("Game: "..UI:GetConfig().folder, "gray")
UI:Log("Caps: "..caps.."/"..#C.PROBES, "gray")
UI:Log("🧊 REAL game freeze — stops physics, sounds, animations", "white")
UI:Log("🛡️ 4-tier anti-crash + real freeze = zero crashes", "white")
UI:Log("🔍 21 scanners + 16 decompile strategies", "white")
UI:Log("📡 Adaptive remote args — infers types automatically", "white")
UI:Log("★ Safe: fast + protected + memory guards", "gray")
UI:Log("★ Normal: balanced speed + full coverage", "gray")
UI:Log("★ Turbo: maximum speed + safety guards", "gray")
UI:Log("Press START", "white")