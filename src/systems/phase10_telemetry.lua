-- Dev / Phase 10: last observed stress wall-clock sample (not authoritative gameplay metrics).

local M = {
    stress_run_duration_ms = nil,
    stress_run_label = nil,
}

function M.recordStressWallMs(ms, label)
    if type(ms) ~= "number" or ms < 0 then
        return
    end
    M.stress_run_duration_ms = math.floor(ms + 0.5)
    M.stress_run_label = label and tostring(label) or "unknown"
end

function M.getLastStressSample()
    return M.stress_run_duration_ms, M.stress_run_label
end

return M
