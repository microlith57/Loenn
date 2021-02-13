local drawableSprite = require("structs.drawable_sprite")

local checkpoint = {}

checkpoint.name = "checkpoint"
checkpoint.depth = 9990

function checkpoint.sprite(room, entity)
    local bg = entity.bg

    if not bg or bg == "" then
        bg = "1"
    end

    local texture = string.format("objects/checkpoint/bg/%s", bg)
    local sprite = drawableSprite.spriteFromTexture(texture, entity)

    sprite:setJustification(0.5, 1.0)

    return sprite
end

return checkpoint