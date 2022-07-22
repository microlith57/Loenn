local ui = require("ui")
local uiElements = require("ui.elements")
local uiUtils = require("ui.utils")

local loadedState = require("loaded_state")
local languageRegistry = require("language_registry")
local utils = require("utils")
local form = require("ui.forms.form")
local configs = require("configs")
local enums = require("consts.celeste_enums")
local stylegroundEditor = require("ui.styleground_editor")
local listWidgets = require("ui.widgets.lists")
local widgetUtils = require("ui.widgets.utils")
local formHelper = require("ui.forms.form")
local parallax = require("parallax")
local effects = require("effects")
local formUtils = require("ui.utils.forms")
local atlases = require("atlases")

local stylegroundWindow = {}

local activeWindows = {}
local windowPreviousX = 0
local windowPreviousY = 0

local stylegroundWindowGroup = uiElements.group({}):with({

})

local function getStylegroundItems(targets, fg, items, parent)
    local language = languageRegistry.getLanguage()

    items = items or {}

    for _, style in ipairs(targets) do
        local styleType = utils.typeof(style)

        if styleType == "parallax" then
            local displayName = parallax.displayName(language, style)

            table.insert(items, {
                text = displayName,
                data = {
                    style = style,
                    parentStyle = parent
                }
            })

        elseif styleType == "effect" then
            print(style)
            local displayName = effects.displayName(language, style)

            table.insert(items, {
                text = displayName,
                data = {
                    style = style,
                    parentStyle = parent
                }
            })

        elseif styleType == "apply" then
            -- TODO - Support later
            if style.children then
                --getStylegroundItems(style.children, fg, items, style)
            end
        end
    end

    return items
end

local function getHandler(style)
    local styleType = utils.typeof(style)

    if styleType == "parallax" then
        return parallax

    elseif styleType == "effect" then
        return effects
    end
end

local function getOptions(style)
    local handler = getHandler(style)
    local prepareOptions = {
        namePath = {"attribute"},
        tooltipPath = {"description"}
    }
    local dummyData, fieldInformation, fieldOrder = formUtils.prepareFormData(handler, style, prepareOptions, {style})
    local options = {
        fields = fieldInformation,
        fieldOrder = fieldOrder
    }

    return options, dummyData
end

-- TODO - Localization
local function getStylegroundPreview(interactionData)
    local style = interactionData.listTarget and interactionData.listTarget.style or {}
    local styleType = utils.typeof(style)

    if styleType == "parallax" then
        local texture = style.texture
        local sprite = atlases.getResource(texture)

        if sprite then
            local color = style.color
            local imageElement = uiElements.image(sprite.image, sprite.quad, sprite.layer)

            if color then
                local success, r, g, b, a = utils.parseHexColor(color)

                if success then
                    imageElement.style.color = {r, g, b, a}
                end
            end

            return imageElement

        else
            return uiElements.label("Could not find texture")
        end
    end

    return uiElements.label(style.texture or style._name or "No preview")
end

-- TODO - Improve in the future
-- We can most likely reuse a previous image or label, but this works for now
local function updateStylegroundPreview(interactionData)
    local previewContainer = interactionData.stylegroundPreviewGroup
    local newPreview = getStylegroundPreview(interactionData)

    if previewContainer.children[1] then
        previewContainer:removeChild(previewContainer.children[1])
    end

    if newPreview then
        previewContainer:addChild(newPreview)
    end
end

local function getStylegroundForm(interactionData)
    local listTarget = interactionData.listTarget
    local formData = listTarget and listTarget.style or {}
    local formOptions, dummyData = getOptions(formData)

    -- TODO - Add to config file?
    formOptions.columns = 8
    formOptions.formFieldChanged = function(formFields, field)
        local style = interactionData.listTarget.style
        local newData = form.getFormData(formFields)

        for k, v in pairs(newData) do
            style[k] = v
        end

        updateStylegroundPreview(interactionData)
    end

    return formHelper.getFormBody(dummyData, formOptions)
end

local function updateStylegroundForm(interactionData)
    local formContainer = interactionData.formContainerGroup
    local newForm = getStylegroundForm(interactionData)

    if formContainer.children[1] then
        formContainer:removeChild(formContainer.children[1])
    end

    formContainer:addChild(newForm)
end

local function getStylegroundList(map, interactionData)
    local items = {}
    local listItems = {}

    getStylegroundItems(map.stylesFg or {}, true, items)
    getStylegroundItems(map.stylesBg or {}, false, items)

    if items[1] then
        interactionData.listTarget = {
            style = items[1].data.style
        }
    end

    for i, s in ipairs(items) do
        local item = uiElements.listItem({
            text = s,
            data = map.stylesBg[i]
        })

        listItems[i] = item
    end

    local column, list = listWidgets.getList(function(element, data)
        interactionData.listTarget = data

        print(utils.serialize(data))
        updateStylegroundForm(interactionData)
        updateStylegroundPreview(interactionData)
    end, items, {initialItem = 1})

    return column, list
end

local function getWindowContent(map)
    local interactionData = {}

    local stylegroundFormGroup = uiElements.group({}):with(uiUtils.bottombound)
    local stylegroundListColumn, stylegroundList = getStylegroundList(map, interactionData)
    local stylegroundPreview = uiElements.group({
        getStylegroundPreview(interactionData)
    })
    local stylegroundForm = getStylegroundForm(interactionData)

    stylegroundFormGroup:addChild(stylegroundForm)

    interactionData.formContainerGroup = stylegroundFormGroup
    interactionData.stylegroundPreviewGroup = stylegroundPreview

    local stylegroundListPreviewRow = uiElements.row({
        stylegroundListColumn:with(uiUtils.fillHeight(false)),
        stylegroundPreview
    }):with(uiUtils.fillHeight(true))

    local layout = uiElements.column({
        stylegroundListPreviewRow,
        stylegroundFormGroup
    }):with(uiUtils.fillHeight(true))

    layout:reflow()

    return layout, interactionData
end

function stylegroundWindow.editStylegrounds(map)
    local window
    local layout, interactionData = getWindowContent(map)

    -- Figure out some smart sizing things here, this is too hardcoded
    -- Still doesn't fit all the elements, good enough for now
    window = uiElements.window("Styleground Window", layout):with({
        width = 1200,
        height = 600
    })

    table.insert(activeWindows, window)
    stylegroundWindowGroup.parent:addChild(window)
    widgetUtils.addWindowCloseButton(window)

    return window
end

-- Group to get access to the main group and sanely inject windows in it
function stylegroundWindow.getWindow()
    stylegroundEditor.stylegroundWindow = stylegroundWindow

    return stylegroundWindowGroup
end

return stylegroundWindow