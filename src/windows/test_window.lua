local theme = require("giraffe.theme")
local windowStruct = require("giraffe.window")
local giraffe = require("giraffe")

local window = {}

-- TODO - Test window in window

window.title = "Window Test!"

window.x = 200
window.y = 200

window.width = 400
window.height = 300

window.theme = {
    window = {
        --background = {0.7, 0.7, 0.7},
        background = love.graphics.newImage("assetsTesting/hardened_clay_stained_light_blue.png"),
        backgroundImageMode = "tiling",

        titleBackground = love.graphics.newImage("assetsTesting/hardened_clay_stained_purple.png"),
        titleBackgroundImageMode = "tiling"
    }
}

window.widgets = {
    giraffe.button({
        x = 10,
        y = 10,

        width = 100,
        height = 100,

        content = "Foobar", --love.graphics.newImage("assetsTesting/hardened_clay_stained_purple.png"),

        pressed = function(self, x, y)
            print(":O", x, y)
        end,

        update = function(self)
            self.content = self._hovered and "Hi mouse :)" or "Come back D:"
        end
    })
}

function window:loaded()
    self.image = love.graphics.newImage("assets/logo-256.png")
end

function window:draw()
    love.graphics.draw(self.image, -20, -20)
    love.graphics.setColor(1.0, 0.7, 0.7)
    love.graphics.print(self._thingActive and "Hello there thing" or "Hello", 20, 256, 0, 4, 4)

    windowStruct.defaults.draw(self)
end

function window:mousepressed(x, y, button, istouch, presses)
    print(self.title, "mousepressed", x, y, button)

    windowStruct.defaults.mousepressed(self, x, y, button, istouch, presses)
end

function window:mousemoved(x, y, dx, dy)
    self._thingActive = x > 20 and x < 100

    windowStruct.defaults.mousemoved(self, x, y, dx, dy)
end

return window