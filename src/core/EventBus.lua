-- EventBus.lua - Minimal pub/sub for decoupling systems

local EventBus = {}
EventBus.__index = EventBus

function EventBus:new()
    local self = setmetatable({}, EventBus)
    self._listeners = {}
    return self
end

-- Subscribe to an event. Returns an unsubscribe function.
function EventBus:on(eventName, listener)
    if not eventName or type(listener) ~= 'function' then return function() end end
    local list = self._listeners[eventName]
    if not list then
        list = {}
        self._listeners[eventName] = list
    end
    list[#list + 1] = listener
    local removed = false
    return function()
        if removed then return end
        removed = true
        for i = #list, 1, -1 do
            if list[i] == listener then
                table.remove(list, i)
                break
            end
        end
    end
end

-- Emit an event synchronously.
function EventBus:emit(eventName, ...)
    local list = self._listeners[eventName]
    if not list or #list == 0 then return end
    -- copy to avoid mutation during iteration
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end
    for i = 1, #snapshot do
        local fn = snapshot[i]
        if type(fn) == 'function' then
            fn(...)
        end
    end
end

return EventBus


