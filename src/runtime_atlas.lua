local utils = require("utils")
local configs = require("configs")
local logging = require("logging")

local textureAtlas = {}

textureAtlas.atlases = {}
textureAtlas._MT = {}

textureAtlas.width = 4096
textureAtlas.height = 4096

textureAtlas.canvases = nil
textureAtlas.canvasArray = nil

-- Set up canvasArray
-- Love2d on windows doesn't report how many layers are actually supported due to a bug
-- Test a few, worst case default to 0
function textureAtlas.init()
    local layerCounts = {8, 4}

    for _, count in ipairs(layerCounts) do
        local success, canvas = pcall(love.graphics.newCanvas, textureAtlas.width, textureAtlas.height, count, {type="array"})

        if success then
            textureAtlas.canvases = count
            textureAtlas.canvasArray = canvas

            if configs.debug.logImageLoading then
                local message = string.format("Initialized runtime atlases with up to %s layers", count)

                logging.info(message)
            end

            return count
        end
    end

    if configs.debug.logImageLoading then
        local message = string.format("Unable to initialize runtime atlases with layers, using normal canvases")

        logging.info(message)
    end

    textureAtlas.canvases = 0
end

function textureAtlas.clearCanvasArea(canvas, layer, x, y, width, height)
    local previousCanvas = love.graphics.getCanvas()
    local scissorX, scissorY, scissorWidth, scissorHeight = love.graphics.getScissor()

    love.graphics.setCanvas(canvas, layer)
    love.graphics.push()
    love.graphics.origin()
    love.graphics.setScissor(x, y, width, height)
    love.graphics.clear(0.0, 0.0, 0.0, 0.0)
    love.graphics.pop()
    love.graphics.setCanvas(previousCanvas)
    love.graphics.setScissor(scissorX, scissorY, scissorWidth, scissorHeight)
end

function textureAtlas.clear()
    for i, atlas in ipairs(textureAtlas.atlases) do
        -- Clear canvas arrays, release normal canvases
        if i <= textureAtlas.canvases then
            local canvas = textureAtlas.canvasArray

            textureAtlas.clearCanvasArea(canvas, i, 0, 0, textureAtlas.width, textureAtlas.height)

        else
            if atlas.image then
                atlas.image:release()
            end
        end
    end

    textureAtlas.atlases = {}
end

-- Set up as layer in canvasArray if possible, otherwise use a new normal canvas
function textureAtlas.addAtlas(layer)
    local atlasNumber = #textureAtlas.atlases + 1
    local atlasName = string.format("Runtime Atlas #%s", atlasNumber)
    local canvas = textureAtlas.canvasArray

    if atlasNumber > textureAtlas.canvases then
        canvas = love.graphics.newCanvas(textureAtlas.width, textureAtlas.height)
        layer = nil
    end

    local atlas = {
        image = canvas,
        layer = layer,
        width = textureAtlas.width,
        height = textureAtlas.height,
        filename = atlasName,
        dataName = atlasName,
        rectangles = {utils.rectangle(0, 0, textureAtlas.width, textureAtlas.height)}
    }

    table.insert(textureAtlas.atlases, atlas)
end

function sortAtlasRectangles(atlas)
    -- TODO merge adjacent rectangles
    -- TODO overlap rectangles

    table.sort(atlas.rectangles, function(r1, r2)
        return r1.width == r2.width and r1.height < r2.height or r1.width < r2.width
    end)
end

-- TODO - Check if added already?
function textureAtlas.addImage(atlas, image, filename, layer)
    local width, height = image:getDimensions()

    for i = 1, #atlas.rectangles do
        local rectangle = atlas.rectangles[i]

        -- Find free space
        if width <= rectangle.width and height <= rectangle.height then
            local x, y = rectangle.x, rectangle.y

            -- Find remaining free space after inserting the new image
            local remainingSpace = utils.subtractRectangle(rectangle, utils.rectangle(x, y, width, height))

            table.remove(atlas.rectangles, i)

            for _, remaining in ipairs(remainingSpace) do
                table.insert(atlas.rectangles, remaining)
            end

            sortAtlasRectangles(atlas)

            -- Add the image on the canvas

            local previousCanvas = love.graphics.getCanvas()

            if layer <= textureAtlas.canvases then
                love.graphics.setCanvas(atlas.image, layer)

            else
                love.graphics.setCanvas(atlas.image)
            end

            love.graphics.push()
            love.graphics.origin()
            love.graphics.draw(image, x, y)
            love.graphics.pop()
            love.graphics.setCanvas(previousCanvas)

            if configs.debug.logImageLoading then
                local message = string.format("Loaded image '%s' to atlas layer %s at (%s, %s) with size %sx%s", filename, atlas.layer or layer, x, y, width, height)

                logging.info(message)
            end

            return true, atlas.image, x, y, atlas.layer
        end
    end

    return false, nil, 0, 0, -1
end

function textureAtlas.removeImage(image, quad, layer)
    local x, y, width, height = quad:getViewport()

    local atlas = textureAtlas.atlases[layer]

    if atlas then
        textureAtlas.clearCanvasArea(image, layer, x, y, width, height)

        table.insert(atlas.rectangles, utils.rectangle(x, y, width, height))
        sortAtlasRectangles(atlas)

    else
        image:release()
    end
end

function textureAtlas.addImageFirstAtlas(image, filename, createIfNeeded, onlyCheck)
    for i, atlas in ipairs(textureAtlas.atlases) do
        if not onlyCheck or onlyCheck and onlyCheck == i then
            local fit, atlasImage, x, y, layer = textureAtlas.addImage(atlas, image, filename, i)

            if fit then
                return atlasImage, x, y, layer
            end
        end
    end

    if createIfNeeded ~= false then
        if configs.debug.logImageLoading then
            local message = string.format("Added another runtime atlas number %s", #textureAtlas.atlases + 1)

            logging.info(message)
        end

        textureAtlas.addAtlas(#textureAtlas.atlases + 1)

        return textureAtlas.addImageFirstAtlas(image, filename, false, #textureAtlas.atlases)
    end

    return image, 0, 0
end

function textureAtlas.dumpCanvasImages()
    for i = 1, #textureAtlas.atlases do
        local data = textureAtlas.canvasArray:newImageData(i)

        data:encode("png", "canvas_dump_" .. tostring(i) .. ".png")
        data:release()
    end
end

textureAtlas.init()

return textureAtlas