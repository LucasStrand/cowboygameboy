local CombatEvents = {
    _listeners = {},
}

function CombatEvents.subscribe(name, fn)
    if type(fn) ~= "function" then
        error("[combat_events] subscribe expects a function", 0)
    end
    CombatEvents._listeners[name] = CombatEvents._listeners[name] or {}
    table.insert(CombatEvents._listeners[name], fn)
    return fn
end

function CombatEvents.emit(name, payload)
    local listeners = CombatEvents._listeners[name]
    if not listeners then
        return
    end
    for _, fn in ipairs(listeners) do
        fn(payload or {})
    end
end

function CombatEvents.clear()
    CombatEvents._listeners = {}
end

return CombatEvents
