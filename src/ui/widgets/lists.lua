local ui = require("ui")
local uiElements = require("ui.elements")
local uiUtils = require("ui.utils")

local widgetUtils = require("ui.widgets.utils")

local textSearching = require("utils.text_search")
local configs = require("configs")
local keyboard = require("utils.keyboard")
local utils = require("utils")

local listWidgets = {}

local function calculateWidthScrollable(orig, element)
    return element.inner.width
end

local function calculateWidthList(orig, element)
    local width = orig(element) or element.innerWidth

    if not configs.ui.lists.shrinkToFit then
        element._largestWidth = math.max(element._largestWidth or width, width)

        return element._largestWidth
    end

    return width
end

local function getCaseSensitive(search)
    local caseSensitive = configs.ui.searching.searchCaseSensitive

    if caseSensitive == "contextual" then
        caseSensitive = search ~= search:lower()

    elseif type(caseSensitive) == "string" then
        caseSensitive = caseSensitive == "always"
    end

    return caseSensitive
end

local function defaultFilterItems(items, search, options)
    local filtered = {}

    local scoreFunction = options.searchScore or textSearching.searchScore
    local searchPreprocessor = options.searchPreprocessor

    local fuzzy = configs.ui.searching.searchFuzzy
    local caseSensitive = getCaseSensitive(search)

    -- Enable fuzzy search if the term starts with ~
    if utils.startsWith(search, "~") then
        fuzzy = true
        search = string.sub(search, 2)
    end

    if searchPreprocessor then
        search = searchPreprocessor(search, caseSensitive, fuzzy)
    end

    for _, item in ipairs(items) do
        local score = nil

        if options.searchRawItem then
            score = scoreFunction(item, search, caseSensitive, fuzzy)

        else
            local text = item.text
            local textType = type(text)

            if textType == "string" then
                score = scoreFunction(text, search, caseSensitive, fuzzy)

                item._filterScore = score

            else
                -- Improve this for non string in the future

                score = math.huge
            end
        end

        item._filterScore = score

        if score then
            table.insert(filtered, item)
        end
    end

    return filtered
end

function listWidgets.clearSelection(list)
    local magicList = list._magicList

    if magicList then
        list._selectedIndex = nil

    else
        list.selectedIndex = nil
    end
end

function listWidgets.setSelection(list, target, preventCallback, callbackRequiresChange)
    -- Select first item as default, callback if it exists
    -- If target is defined attempt to select this instead of the first item

    local selectedTarget = false
    local selectedIndex = 1
    local previousSelection = list.selected and list.selected.data
    local newSelection
    local magicList = list._magicList

    if target ~= false then
        local dataList = magicList and list.data or list.children

        for i, item in ipairs(dataList) do
            local index = magicList and item._magicIndex or i

            if item == target or item.data == target or item.text == target or index == target then
                newSelection = item
                selectedTarget = true
                selectedIndex = index

                break
            end
        end

        if not newSelection then
            newSelection = dataList[1]
        end
    end

    -- Magic lists call its callback when changing index, normal lists don't

    if newSelection then
        list.selected = newSelection

        if list.selectedIndex ~= selectedIndex then
            if magicList then
                list._selectedIndex = selectedIndex

            else
                list.selectedIndex = selectedIndex
            end
        end

        if not preventCallback then
            local dataChanged = newSelection.data ~= previousSelection

            if callbackRequiresChange and dataChanged or not callbackRequiresChange then
                local listCallback = list.cb

                if listCallback then
                    local data = list.selected

                    if not magicList then
                        data = data and data.data
                    end

                    if magicList then
                        list.selectedIndex = selectedIndex

                    else
                        listCallback(list, data)
                    end
                end
            end
        end
    end

    listWidgets.scrollSelectionVisible(list)

    return selectedTarget, selectedIndex
end

local function findChildIndex(parent, child)
    for i, c in ipairs(parent.children or {}) do
        if child == c then
            return i
        end
    end
end

local function findListParent(element)
    local target = element

    while target and (target.__type ~= "magicList" and target.__type ~= "list") do
        target = target.parent
    end

    return target
end

local function getListDropTarget(element, x, y)
    local elementList = findListParent(element)

    if not elementList or not elementList.draggable then
        return false, false, false
    end

    local hovered = ui.root and ui.root:getChildAt(x, y)

    if hovered then
        local hoveredList = findListParent(hovered)

        if hoveredList then
            if elementList == hoveredList then
                return hoveredList, hovered
            end

            if elementList.draggableTag and elementList.draggableTag == hoveredList.draggableTag then
                return hoveredList, hovered
            end
        end
    end

    return false, false, false
end

-- TODO - Currently only moves the child elements, nothing else
local function moveListItem(fromList, fromListItem, toList, toListItem, fromIndex, toIndex)
    local sameList = fromList == toList

    -- Invalid indices
    if not fromIndex or not toIndex then
        return false
    end

    -- No change
    if sameList and fromIndex == toIndex then
        return false
    end

    local toChildren = toList.children or {}
    local fromChildren = fromList.children or {}

    local shouldMove = true

    if fromList.listItemDragged then
        shouldMove = shouldMove and fromList.listItemDragged(fromList, fromListItem, toList, toListItem, fromIndex, toIndex)
    end

    if not sameList and toList.listItemDragged then
        shouldMove = shouldMove and toList.listItemDragged(fromList, fromListItem, toList, toListItem, fromIndex, toIndex)
    end

    if shouldMove == false then
        return false
    end

    -- Make sure we don't shift around the indices when moving in same list
    if fromIndex < toIndex then
        table.insert(toChildren, toIndex, fromListItem)
        table.remove(fromChildren, fromIndex)

    else
        table.remove(fromChildren, fromIndex)
        table.insert(toChildren, toIndex, fromListItem)
    end

    return true
end

local function moveListItemInDirection(list, direction)
    local index = list.selectedIndex
    local targetIndex = index + direction
    local listItem = list.children[index]
    local allowed = true

    -- Needs one extra to move downwards
    if direction > 0 then
        targetIndex += 1
    end

    if list.listItemCanInsert then
        allowed = list.listItemCanInsert(list, listItem, list, listItem, index, targetIndex)
    end

    if not allowed then
        return false
    end

    moveListItem(list, listItem, list, listItem, index, targetIndex)

    list:reflow()
    list:redraw()
end

local function handleItemDrag(item, x, y)
    local ourList, ourListItem = findListParent(item), item
    local hoveredList, hoveredListItem = getListDropTarget(item, x, y)

    if hoveredList then
        local ourIndex = findChildIndex(ourList, ourListItem)
        local hoveredIndex = findChildIndex(hoveredList, hoveredListItem)

        if not hoveredIndex or not ourIndex then
            return false
        end

        local sameList = ourList == hoveredList
        local centerDeltaX, centerDeltaY = widgetUtils.cursorDeltaFromElementCenter(hoveredListItem, x, y)
        local insertAfter = centerDeltaY >= 0

        if insertAfter then
            hoveredIndex += 1
        end

        local previousList = item._previousHovered
        local previousIndex

        if previousList then
            previousIndex = previousList._dragHoveredIndex

            previousList._dragHoveredIndex = nil
        end

        -- Redraw if new list or the index changed on the same list
        if previousList and previousList ~= hoveredList then
            previousList:reflow()
            previousList:redraw()
        end

        if previousList == hoveredList and previousIndex ~= hoveredIndex then
            hoveredList:reflow()
            hoveredList:redraw()
        end

        if hoveredList._dragHoveredIndex ~= hoveredIndex then
            if hoveredList.listItemCanInsert then
                local allowed = hoveredList.listItemCanInsert(ourList, ourListItem, hoveredList, hoveredListItem, ourIndex, hoveredIndex)

                hoveredList._dragInsertionAllowed = allowed

            else
                hoveredList._dragInsertionAllowed = true
            end
        end

        hoveredList._dragHoveredIndex = hoveredIndex
        item._previousHovered = hoveredList

        return true
    end
end

local function handleItemDragFinish(item, x, y)
    local ourList, ourListItem = findListParent(item), item
    local hoveredList = item._previousHovered

    if hoveredList then
        local ourIndex = findChildIndex(ourList, ourListItem)
        local hoveredIndex = hoveredList._dragHoveredIndex
        local moved = moveListItem(ourList, ourListItem, hoveredList, hoveredListItem, ourIndex, hoveredIndex)
        local sameList = ourList == hoveredList

        hoveredList._previousHovered = nil
        hoveredList._dragHoveredIndex = nil

        ourList:reflow()
        ourList:redraw()

        if not sameList then
            hoveredList:reflow()
            hoveredList:redraw()
        end

        return moved
    end
end

local function prepareListDragHook()
    return {
        draw = function(orig, self)
            orig(self)

            local renderInsertLine = self._dragInsertionAllowed

            if not renderInsertLine then
                return
            end

            -- Index 0 means before any items, index 2 is between item two and three
            local hovered = self._dragHoveredIndex
            local children = self.children

            -- TODO - Work with empty lists
            if hovered and #children > 0 then
                local drawX = self.screenX
                local drawY = self.screenY

                local width = children[1].width
                local height = math.min(self.style.spacing, 1)

                local item = children[hovered]

                if item then
                    drawX = item.screenX
                    drawY = item.screenY

                    if hovered > 1 then
                        drawY -= height
                    end

                else
                    local lastChild = children[#children]

                    drawX = lastChild.screenX
                    drawY = lastChild.screenY + lastChild.height
                end

                local lineColor = self.style:get("dragLineColor") or {1.0, 1.0, 1.0, 1.0}
                local previousColor = {love.graphics.getColor()}

                love.graphics.setColor(lineColor)
                love.graphics.rectangle("fill", drawX, drawY, width, height)
                love.graphics.setColor(previousColor)
            end
        end,
        onPress = function(orig, self, x, y, button, dragging)
            -- Make sure all children have the hook
            listWidgets.addDraggableHooks(self)

            orig(self, x, y, button, dragging)
        end
    }
end

local function prepareItemDragHook()
    return {
        onPress = function(orig, self, x, y, button, dragging)
            if button == 1 then
                self.dragging = dragging

            else
                orig(self, x, y, button, dragging)
            end
        end,
        onDrag = function(orig, self, x, y)
            if self.dragging then
                handleItemDrag(self, x, y)

            else
                orig(self, x, y)
            end
        end,
        onRelease = function(orig, self, x, y, button, dragging)
            if button == 1 or not dragging then
                self.dragging = dragging

                handleItemDragFinish(self, x, y)

            else
                orig(self, x, y, button, dragging)
            end
        end
    }
end

function listWidgets.addDraggableHooks(list)
    local draggable = list.draggable

    if draggable then
        if not list._addedDraggableHook then
            list:hook(prepareListDragHook())

            list._addedDraggableHook = true
        end

        for _, item in ipairs(list.children or {}) do
            if not item._addedDraggableHook then
                item:hook(prepareItemDragHook())

                item._addedDraggableHook = true
            end
        end
    end
end

local function defaultItemSort(lhs, rhs)
    if configs.ui.searching.sortByScore and lhs._filterScore and rhs._filterScore then
        if lhs._filterScore ~= rhs._filterScore then
            return lhs._filterScore > rhs._filterScore
        end
    end

    return lhs.text < rhs.text
end

local function sortItems(list, items)
    local options = list.options or list
    local sortedItems = table.shallowcopy(items)

    table.sort(sortedItems, options.sortingFunction or defaultItemSort)

    return sortedItems
end

function listWidgets.updateItems(list, items, target, fromFilter, preventCallback, callbackRequiresChange, forceSort)
    local options = list.options
    local filterItems = options.filterItems or defaultFilterItems
    local previousSelection = list.selected and list.selected.data
    local newSelection

    local processedItems = items

    if not fromFilter and list.searchField then
        local search = list.searchField:getText() or ""

        processedItems = filterItems(processedItems, search, list.options)
    end

    if options.sort or forceSort then
        processedItems = sortItems(list, processedItems)
    end

    for _, item in ipairs(processedItems) do
        if item.data == previousSelection then
            newSelection = item
        end

        if fromFilter and not list._magicList then
            item:reflow()
        end
    end

    if list._magicList then
        list:invalidate()

        list.data = processedItems

    else
        list.children = processedItems
    end

    ui.runLate(function()
        listWidgets.setSelection(list, target or newSelection, preventCallback, callbackRequiresChange)
    end)

    list:reflow()
    ui.root:recollect()

    if not fromFilter then
        list.unfilteredItems = items
    end

    listWidgets.addDraggableHooks(list)
end

function listWidgets.sortList(list)
    local unfilteredItems = list.unfilteredItems
    local target = list:getSelectedData()

    if list._magicList then
        target = target.data or target
    end

    listWidgets.updateItems(list, unfilteredItems, target, false, true, true, true)
end

function listWidgets.filterList(list, search, preventCallback)
    local unfilteredItems = list.unfilteredItems
    local filteredItems = list.filterItems(unfilteredItems, search, list.options)

    listWidgets.updateItems(list, filteredItems, nil, true, preventCallback or false, true)
end

local function getSearchFieldChanged(onChange)
    return function(element, new, old)
        listWidgets.filterList(element.list, new)
        listWidgets.addDraggableHooks(element.list)

        if onChange then
            onChange(element, new, old)
        end
    end
end

function listWidgets.setFilterText(list, text, preventCallback)
    preventCallback = preventCallback ~= false

    local searchField = list.searchField

    if searchField then
        local searchCallback = searchField.cb

        if preventCallback then
            searchField.cb = nil
        end

        searchField:setText(text)
        searchField.index = #text

        if preventCallback then
            searchField.cb = searchCallback

        else
            listWidgets.filterList(list, text)
        end
    end
end

function listWidgets.scrollSelectionVisible(list)
    if not list or not list.parent then
        return
    end

    -- Not supported in normal lists
    if not list._magicList then
        return
    end

    local scrollbox = list.parent
    local scrollHandle = scrollbox.handleY

    if scrollHandle then
        local column = list.scrolledList
        local scrollTop = math.abs(list.y)
        local scrollBottom = scrollTop + column.height

        local selectedIndex = list.selectedIndex or 1

        local itemTop = listWidgets.getMagicListHeight(list, selectedIndex - 1)
        local itemBottom = listWidgets.getMagicListHeight(list, selectedIndex)
        local threshold = listWidgets.getMagicListHeight(list, 3)
        local smallScrollAmount = listWidgets.getMagicListHeight(list, 1)

        local offsetTop = itemTop - scrollTop
        local offsetBottom = scrollBottom - itemBottom
        local smallScrollUp = offsetTop >= 0 and offsetTop <= threshold
        local smallScrollDown = offsetBottom >= 0 and offsetBottom <= threshold
        local itemOffScreen = offsetTop < 0 or offsetBottom < 0

        if smallScrollUp then
            scrollbox:onScroll(0, 0, 0, -smallScrollAmount, true)

        elseif smallScrollDown then
            scrollbox:onScroll(0, 0, 0, smallScrollAmount, true)

        elseif itemOffScreen then
            -- Attempt to put in center of list
            local centerOffset = math.floor(offsetTop - column.height / 2)

            scrollbox:onScroll(0, 0, 0, centerOffset, true)
        end
    end
end

-- Get the height of magic list, default to whole list
function listWidgets.getMagicListHeight(list, itemCount)
    itemCount = itemCount or #list.data

    if itemCount <= 0 then
        return 0
    end

    local elementSize = list:getElementSize()
    local spacing = list.style.spacing
    local listHeight = elementSize * itemCount + spacing * (itemCount - 2)

    return listHeight
end

local function handleListKeyboardNavigation(list, key, hookOptions)
    local nextResultKey = configs.ui.searching.searchNextResultKey
    local previousResultKey = configs.ui.searching.searchPreviousResultKey
    local rearrangeModifier = configs.ui.searching.searchRearrangeModifier

    local direction = 0

    local magicList = list._magicList
    local dataList = magicList and list.data or list.children
    local selectedIndex = list.selectedIndex or 0
    local handled = key == nextResultKey or key == previousResultKey

    local preventCallback = hookOptions.preventCallback or false

    -- Set direction if move is allowed
    if key == nextResultKey and selectedIndex < #dataList then
        direction = 1

    elseif key == previousResultKey and selectedIndex > 1 then
        direction = -1
    end

    if direction ~= 0 then
        local rearrangeHeld = keyboard.modifierHeld(rearrangeModifier)

        -- Rearrange not supported on magic lists
        if rearrangeHeld then
            if list.draggable and not magicList then
                moveListItemInDirection(list, direction)
                listWidgets.scrollSelectionVisible(list)

            else
                -- Don't consume if the list isn't rearrangable
                handled = false
            end

        else
            listWidgets.setSelection(list, list.selectedIndex + direction, preventCallback)
            listWidgets.scrollSelectionVisible(list)
        end
    end

    return handled
end

local function searchFieldKeyRelease(list, hookOptions)
    hookOptions = hookOptions or {}

    return function(orig, self, key, ...)
        if hookOptions.skipHooksPredicate and not hookOptions.skipHooksPredicate() then
            return orig(self, key, ...)
        end

        local exitKey = configs.ui.searching.searchExitKey
        local exitClearKey = configs.ui.searching.searchExitAndClearKey
        local selectKey = configs.ui.searching.searchSelectKey

        if key == exitClearKey then
            self:setText("")
            widgetUtils.focusMainEditor()

        elseif key == exitKey then
            widgetUtils.focusMainEditor()

        elseif key == selectKey then
            listWidgets.setSelection(list, list.selectedIndex)
            widgetUtils.focusMainEditor()

        else
            orig(self, key, ...)
        end
    end
end

local function listCommonKeyPress(list, isSearchField, hookOptions)
    hookOptions = hookOptions or {}

    return function(orig, self, key, ...)
        if hookOptions.skipHooksPredicate and not hookOptions.skipHooksPredicate() then
            return orig(self, key, ...) or isSearchField
        end

        local handled = handleListKeyboardNavigation(list, key, hookOptions)

        if not handled then
            return orig(self, key, ...) or isSearchField
        end
    end
end

function listWidgets.addSearchFieldHooks(list, searchField, hookOptions)
    searchField:hook({
        onKeyRelease = searchFieldKeyRelease(list, hookOptions),
        onKeyPress = listCommonKeyPress(list, true, hookOptions)
    })
end

local function addListHooks(list)
    list.interactive = 1

    list:hook({
        onKeyPress = listCommonKeyPress(list, false)
    })
end

local function getColumnForList(searchField, scrolledList, mode)
    local columnItems

    if mode == "below" then
        columnItems = {
            scrolledList,
            searchField:with(uiUtils.bottombound)
        }

    elseif mode == "above" then
        columnItems = {
            searchField,
            scrolledList
        }

    else
        columnItems = {scrolledList}
    end

    return uiElements.column(columnItems):with(uiUtils.fillHeight(false))
end

-- Magic lists return the item rather than item.data by default
-- Wrap it such that it is consistent with normal lists, but provide the item as 3rd argument
local function magicListCallbackWrapper(callback)
    return function(self, item)
        callback(self, item and item.data, item)
    end
end

local function getListCommon(magicList, callback, items, options)
    options = options or {}
    items = items or {}

    local filterItems = options.filterItems or defaultFilterItems

    if options.sort then
        sortItems(options, items)
    end

    local initialSearch = options.initialSearch or ""
    local filteredItems = filterItems(items, initialSearch, options)

    local list
    local listData = {
        unfilteredItems = items,
        filterItems = filterItems,
        minWidth = options.minimumWidth or 128,
        draggable = options.draggable or false,
        draggableTag = options.draggableTag or false,
        listItemDragged = options.listItemDragged,
        listItemCanInsert = options.listItemCanInsert,
    }

    if magicList then
        list = uiElements.magicList(
            filteredItems,
            options.dataToElement,
            magicListCallbackWrapper(callback)
        ):with(listData)

    else
        list = uiElements.list(filteredItems, callback):with(listData)
    end

    list:with(uiUtils.hook({
        calcWidth = calculateWidthList
    }))
    listWidgets.addDraggableHooks(list)

    ui.runLate(function()
        listWidgets.setSelection(list, list.options.initialItem)
    end)

    local scrolledList = uiElements.scrollbox(list):with(uiUtils.hook({
        calcWidth = calculateWidthScrollable
    })):with(uiUtils.fillHeight(true))

    local searchFieldCallback = getSearchFieldChanged(options.searchBarCallback)
    local searchField = uiElements.field(initialSearch, searchFieldCallback):with({
        list = list
    }):with(uiUtils.fillWidth)

    listWidgets.addSearchFieldHooks(list, searchField)

    list.options = options
    list.searchField = searchField
    list.scrolledList = scrolledList
    list._magicList = magicList

    -- Add utility functions, can't use a metatable
    list.sort = listWidgets.sortList
    list.filter = listWidgets.filterList
    list.updateItems = listWidgets.updateItems
    list.setFilterText = listWidgets.setFilterText
    list.setSelection = listWidgets.setSelection
    list.clearSelection = listWidgets.clearSelection

    addListHooks(list)

    local column = getColumnForList(searchField, scrolledList, options.searchBarLocation)

    return column, list, searchField
end

function listWidgets.getList(callback, items, options)
    return getListCommon(false, callback, items, options)
end

function listWidgets.getMagicList(callback, items, options)
    return getListCommon(true, callback, items, options)
end

return listWidgets
