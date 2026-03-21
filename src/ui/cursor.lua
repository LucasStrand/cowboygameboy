local Cursor = {}

function Cursor.setGameplay()
    love.mouse.setCursor(love.mouse.getSystemCursor("crosshair"))
end

function Cursor.setDefault()
    love.mouse.setCursor(love.mouse.getSystemCursor("arrow"))
end

return Cursor
