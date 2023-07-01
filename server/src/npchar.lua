--, u8R"###(
--

-- event handlers
-- to support all kinds of quests, merchant scripts, etc

-- merchant event handler, optional, structured as
-- {
--     [SYS_ENTER] = function(uid, value)
--     end
--
--     ['npc_tag_1'] = function(uid, value)
--     end
-- }
local _RSVD_NAME_EPDEF_eventHandlers = nil

-- event handlers valid for all players
-- when player in this table clicks npc, handlers in this table will be evaludated, structured as
-- {
--     ['商人的灵魂'] = {
--         [SYS_CHECKACTIVE] = function(uid)
--             -- checks uid level, money, etc
--             -- return true if this quest can be activated for given uid
--         end
--
--         [SYS_ENTER] = function(uid, value)
--         end
--
--         ['npc_tag_1'] = function(uid, value)
--         end
--     }
--
--     ['王寡妇的剪刀'] = {
--         [SYS_CHECKACTIVE] = function(uid)
--             -- checks uid level, money, etc
--             -- return true if this quest can be activated for given uid
--         end
--
--         [SYS_ENTER] = function(uid, value)
--         end
--
--         ['npc_tag_1'] = function(uid, value)
--         end
--     }
-- }
--
-- when player clicks npc, all entries in this table will be iterated and geneartes chatboard content like
-- +----------------------------------------------------------------------+
-- | 你好我是王大人，我在比奇省见过很多年轻人，但是都没有你这么热情好学又 |
-- | 有才华，你想询问我什么事？                                           |
-- |                                                                      |
-- | 询问商人的灵魂                                                       |
-- | 询问王寡妇的剪刀                                                     |
-- | 随便聊聊                                                             | <-- display this line if _RSVD_NAME_EPDEF_eventHandlers valid
-- |                                                                      |
-- | 退出                                                                 |
-- +---------------------------------------------------------------------(x)
--
-- 1. this handler itself has no way to inform player when a quest becomes activated
--    need system message or other way to inform players
--
-- 2. dynamically generated by quest system
local _RSVD_NAME_EPQST_eventHandlers = {}

-- event handlers valid for specific player uids
-- when player clicks npc, handlers in this table will be evaludated, structured as
-- {
--     [1234567] = {
--         ['商人的灵魂'] = {
--             -- setup label for quest entry
--             -- can be a function or a string, or the quest name will be used as label if not assigned
--             [SYS_LABEL] = function(uid)
--                 return '回道馆向王大人复命'
--             end
--
--             [SYS_LABEL] = '回道馆向王大人复命'
--
--             [SYS_ENTER] = function(uid, value)
--             end
--
--             ['npc_tag_1'] = function(uid, value)
--             end
--         },
--
--         ['王寡妇的剪刀'] = {
--             [SYS_ENTER] = function(uid, value)
--             end
--
--             ['npc_tag_1'] = function(uid, value)
--             end
--         }
--     }
--
--     [1034297] = {
--         ['半兽人的传闻'] = {
--             [SYS_ENTER] = function(uid, value)
--             end
--
--             ['npc_tag_1'] = function(uid, value)
--             end
--         }
--     }
-- }
--
-- when player 1234567 clicks npc, all entries in corresponding table will be iterated and geneartes chatboard content like
-- +----------------------------------------------------------------------+
-- | 你好我是王大人，我在比奇省见过很多年轻人，但是都没有你这么热情好学又 |
-- | 有才华，你想询问我什么事？                                           |
-- |                                                                      |
-- | 询问商人的灵魂                                                       |
-- | 询问王寡妇的剪刀                                                     |
-- | 随便聊聊                                                             | <-- display this line if _RSVD_NAME_EPDEF_eventHandlers valid
-- |                                                                      |
-- | 退出                                                                 |
-- +---------------------------------------------------------------------(x)
--
-- 1. the table key like '商人的灵魂' may not be the quest name, just a quest tag, a quest
--    in different stages can use different tags
--
-- 2. all these tables of handlers are dynamically generated, and saved in this _RSVD_NAME_EPUID_eventHandlers, not in database
--    so when server reboot, all these tables of handlers need to be re-generated, this is done by quest system enter function
local _RSVD_NAME_EPUID_eventHandlers = {}

function uidSpaceMove(uid, map, x, y)
    local mapID = nil
    if type(map) == 'string' then
        mapID = getMapID(map)
    elseif math.type(map) == 'integer' and map >= 0 then
        mapID = map
    else
        fatalPrintf("Invalid argument: map = %s, x = %s, y = %s", map, x, y)
    end

    assertType(x, 'integer')
    assertType(y, 'integer')
    return uidExecute(uid, [[ return spaceMove(%d, %d, %d) ]], mapID, x, y)
end

function uidQueryName(uid)
    return uidExecute(uid, [[ return getName() ]])
end

function uidQueryRedName(uid)
    return false
end

function uidQueryLevel(uid)
    return uidExecute(uid, [[ return getLevel() ]])
end

function uidQueryGold(uid)
    return uidExecute(uid, [[ return getGold() ]])
end

function uidRemove(uid, item, count)
    local itemID, seqID = convItemSeqID(item)
    if itemID == 0 then
        fatalPrintf('invalid item: %s', tostring(item))
    end
    return uidExecute(uid, [[ return removeItem(%d, %d, %d) ]], itemID, seqID, argDefault(count, 1))
end

function uidRemoveGold(uid, count)
    return uidRemove(uid, SYS_GOLDNAME, count)
end

function uidSecureItem(uid, itemID, seqID)
    uidExecute(uid, [[ secureItem(%d, %d) ]], itemID, seqID)
end

function uidShowSecuredItemList(uid)
    uidExecute(uid, [[ reportSecuredItemList() ]])
end

function uidGrant(uid, item, count)
    local itemID = convItemSeqID(item)
    if itemID == 0 then
        fatalPrintf('invalid item: %s', tostring(item))
    end
    uidExecute(uid, [[ addItem(%d, %d) ]], itemID, argDefault(count, 1))
end

function uidGrantGold(uid, count)
    uidGrant(uid, '金币（小）', count)
end

function uidPostXML(uid, arg2, arg3, ...)
    assertType(uid, 'integer')

    local eventPath = nil
    local xmlString = nil

    if type(arg2) == 'table' then
        assertType(arg3, 'string')
        eventPath = arg2
        xmlString = string.format(arg3, ...)
    else
        assertType(arg2, 'string')
        eventPath = {SYS_EPDEF}
        xmlString = string.format(arg2, arg3, ...)
    end

    local eventPathStr = nil

        if eventPath[1] == SYS_EPDEF then eventPathStr = SYS_EPDEF
    elseif eventPath[1] == SYS_EPUID then eventPathStr = SYS_EPUID .. '/' .. eventPath[2]
    elseif eventPath[1] == SYS_EPQST then eventPathStr = SYS_EPQST .. '/' .. eventPath[2]
    else
        fatalPrintf('Invalid event path prefix: %s', eventPath[1])
    end

    uidPostXMLString(uid, eventPathStr, xmlString)
end

function setEventHandler(eventHandler)
    if _RSVD_NAME_EPDEF_eventHandlers ~= nil then
        fatalPrintf('Call setEventHandler() twice')
    end

    assertType(eventHandler, 'table')
    if eventHandler[SYS_ENTER] == nil then
        fatalPrintf('Event handler does not support SYS_ENTER')
    end

    if type(eventHandler[SYS_ENTER]) ~= 'function' then
        fatalPrintf('Event handler for SYS_ENTER is not callable')
    end

    _RSVD_NAME_EPDEF_eventHandlers = eventHandler
end

function deleteEventHandler()
    _RSVD_NAME_EPDEF_eventHandlers = nil
end

function hasEventHandler(event)
    if event == nil then
        return _RSVD_NAME_EPDEF_eventHandlers ~= nil
    end

    assertType(event, 'string')
    assert(hasChar(event))

    if _RSVD_NAME_EPDEF_eventHandlers == nil then
        return false
    end

    assertType(_RSVD_NAME_EPDEF_eventHandlers, 'table')
    if _RSVD_NAME_EPDEF_eventHandlers[event] == nil then
        return false
    end

    assertType(_RSVD_NAME_EPDEF_eventHandlers[event], 'function')
    return true
end

function setQuestHandler(quest, questHandler)
    assertType(quest, 'string')
    assertType(questHandler, 'table')
    assertType(questHandler[SYS_ENTER], 'function')
    assertType(questHandler[SYS_CHECKACTIVE], 'function', 'nil')
    _RSVD_NAME_EPQST_eventHandlers[quest] = questHandler
end

function deleteQuestHandler(quest)
    assertType(quest, 'string')
    _RSVD_NAME_EPQST_eventHandlers[quest] = nil
end

function hasQuestHandler(quest, event)
    assertType(quest, 'string')
    assertType(event, 'string')

    if tableEmpty(_RSVD_NAME_EPQST_eventHandlers, false) then
        return false
    end

    if tableEmpty(_RSVD_NAME_EPQST_eventHandlers[quest], true) then
        return false
    end

    if _RSVD_NAME_EPQST_eventHandlers[quest][event] == nil then
        return false
    end

    assertType(_RSVD_NAME_EPQST_eventHandlers[quest][event], 'function')
    return true
end

function setUIDQuestHandler(uid, quest, questHandler)
    assertType(uid, 'integer')
    assertType(quest, 'string')
    assertType(questHandler, 'table')
    assertType(questHandler[SYS_ENTER], 'function')

    if _RSVD_NAME_EPUID_eventHandlers[uid] == nil then
        _RSVD_NAME_EPUID_eventHandlers[uid] = {}
    end

    _RSVD_NAME_EPUID_eventHandlers[uid][quest] = questHandler
end

function deleteUIDQuestHandler(uid, quest)
    assertType(uid, 'integer')
    assertType(quest, 'string')

    if tableEmpty(_RSVD_NAME_EPUID_eventHandlers, false) then
        return
    end

    if tableEmpty(_RSVD_NAME_EPUID_eventHandlers[uid], false) then
        return
    end

    _RSVD_NAME_EPUID_eventHandlers[uid][quest] = nil
    if tableEmpty(_RSVD_NAME_EPUID_eventHandlers[uid], false) then
        _RSVD_NAME_EPUID_eventHandlers[uid] = nil
    end
end

function hasUIDQuestHandler(uid, quest, event)
    assertType(uid, 'integer')
    assertType(quest, 'string')
    assertType(event, 'string')

    if tableEmpty(_RSVD_NAME_EPUID_eventHandlers, false) then
        return false
    end

    if tableEmpty(_RSVD_NAME_EPUID_eventHandlers[uid], true) then
        return false
    end

    if tableEmpty(_RSVD_NAME_EPUID_eventHandlers[uid][quest], true) then
        return false
    end

    if _RSVD_NAME_EPUID_eventHandlers[uid][quest][event] == nil then
        return false
    end

    assertType(_RSVD_NAME_EPUID_eventHandlers[uid][quest][event], 'function')
    return true
end

-- entry coroutine for event handling
-- it's event driven, i.e. if the event sink has no event, this coroutine won't get scheduled

function _RSVD_NAME_npc_main(from, path, event, value)
    getTLSTable().uid = from
    getTLSTable().startTime = getNanoTstamp()

    assertType(from, 'integer')
    assertType(path, 'string', 'nil')
    assertType(event, 'string')
    assertType(value, 'string', 'nil')

    local fnPostInvalidChat = function()
        uidPostXML(from,
        [[
            <layout>
                <par>我听不懂你在说什么。。。</par>
                <par></par>
                <par><event id="%s">关闭</event></par>
            </layout>
        ]], SYS_EXIT)
    end

    local fnPostRedNameChat = function()
        uidPostXML(from,
        [[
            <layout>
                <par>和你这样的人我无话可说。</par>
                <par></par>
                <par><event id="%s">关闭</event></par>
            </layout>
        ]], SYS_EXIT)
    end

    local fnGetEntryLabel = function(funcTable, labelDefault)
        assertType(funcTable, 'table')
        assertType(labelDefault, 'string')

        if funcTable[SYS_LABEL] == nil then
            return labelDefault
        elseif type(funcTable[SYS_LABEL]) == 'string' then
            return funcTable[SYS_LABEL]
        elseif type(funcTable[SYS_LABEL]) == 'function' then
            return funcTable[SYS_LABEL](from)
        else
            fatalPrintf([[Invalid [SYS_LABEL] type: %s]], type(funcTable[SYS_LABEL]))
        end
    end

    if path == nil and event == SYS_ENTER then
        -- click to NPC
        -- need to check all possible event handlers

        local uidEntryList = {}
        if not tableEmpty(_RSVD_NAME_EPUID_eventHandlers) and not tableEmpty(_RSVD_NAME_EPUID_eventHandlers[from], true) then
            for questName, questHandler in pairs(_RSVD_NAME_EPUID_eventHandlers[from]) do
                if type(questHandler[SYS_LABEL]) == 'string' then
                    uidEntryList[questName] = questHandler[SYS_LABEL]
                elseif type(questHandler[SYS_LABEL]) == 'function' then
                    uidEntryList[questName] = questHandler[SYS_LABEL](from)
                elseif questHandler[SYS_LABEL] == nil then
                    uidEntryList[questName] = questName
                else
                    fatalPrintf([[Invalid quest '%s' handler[SYS_LABEL] type: %s]], questName, type(questHandler[SYS_LABEL]))
                end
            end
        end

        -- uid quest handler overwrites quest handler
        -- usually quest handler is used for uid quest entry point

        local qstEntryList = {}
        if not tableEmpty(_RSVD_NAME_EPQST_eventHandlers) then
            for k, v in pairs(_RSVD_NAME_EPQST_eventHandlers) do
                if (not tableEmpty(v)) and (v[SYS_CHECKACTIVE] == nil or v[SYS_CHECKACTIVE](from) == true) and (uidEntryList[k] == nil) then
                    table.insert(qstEntryList, k)
                end
            end
        end

        local entryCount = tableSize(qstEntryList) + tableSize(uidEntryList)

        if hasEventHandler(SYS_ENTER) then
            entryCount = entryCount + 1
        end

        if entryCount == 0 then
            fnPostInvalidChat()

        elseif entryCount == 1 then
            -- only one entry
            -- no need to create menu, just redirect to corresponding entry function
            local funcTable = nil
            if not tableEmpty(qstEntryList) then
                funcTable = _RSVD_NAME_EPQST_eventHandlers[qstEntryList[1]]
            elseif not tableEmpty(uidEntryList) then
                funcTable = _RSVD_NAME_EPUID_eventHandlers[from][next(uidEntryList)]
            else
                funcTable = _RSVD_NAME_EPDEF_eventHandlers
            end

            if uidQueryRedName(from) then
                local allowRedName = false
                if funcTable[SYS_ALLOWREDNAME] then
                    if type(funcTable[SYS_ALLOWREDNAME]) == 'boolean' then
                        allowRedName = funcTable[SYS_ALLOWREDNAME]
                    elseif type(funcTable[SYS_ALLOWREDNAME]) == 'function' then
                        allowRedName = funcTable[SYS_ALLOWREDNAME](from)
                    else
                        fatalPrintf("Invalid SYS_ALLOWREDNAME type: %s", type(funcTable[SYS_ALLOWREDNAME]))
                    end
                end

                if allowRedName then
                    funcTable[SYS_ENTER](from, value)
                else
                    fnPostRedNameChat()
                end
            else
                funcTable[SYS_ENTER](from, value)
            end

        else
            -- more than one entry
            -- create menu for user to choose
            -- this menu comes from neither default script nor quest script
            local xmlStrs = {}
            table.insert(xmlStrs, string.format([[
                <layout>
                    <par>你好我是%s，你想询问我什么事？</par>
                    <par></par>
            ]], getNPCName()))

            for _, v in ipairs(qstEntryList) do
                table.insert(xmlStrs, string.format([[
                    <par><event id="%s" path="%s/%s">%s</event></par>
                ]], SYS_ENTER, SYS_EPQST, v, v))
            end

            for k, v in pairs(uidEntryList) do
                table.insert(xmlStrs, string.format([[
                    <par><event id="%s" path="%s/%s">%s</event></par>
                ]], SYS_ENTER, SYS_EPUID, k, v))
            end

            if hasEventHandler(SYS_ENTER) then
                table.insert(xmlStrs, string.format([[
                    <par><event id="%s">随便聊聊</event></par>
                ]], SYS_ENTER))
            end

            table.insert(xmlStrs, string.format([[
                    <par></par>
                    <par><event id="%s">退出</event></par>
                </layout>
            ]], SYS_EXIT))

            uidPostXML(from, table.concat(xmlStrs))
        end

    elseif event ~= SYS_EXIT then
        -- not initial click to NPC
        -- needs to parse event path to find correct event handler

        pathTokens = splitString(path, '/')
        if pathTokens[1] == SYS_EPDEF then
            if hasEventHandler(event) then
                _RSVD_NAME_EPDEF_eventHandlers[event](from, value)
            else
                fnPostInvalidChat()
            end

        elseif pathTokens[1] == SYS_EPQST then
            if hasQuestHandler(pathTokens[2], event) then
                _RSVD_NAME_EPQST_eventHandlers[pathTokens[2]][event](from, value)
            else
                fnPostInvalidChat()
            end

        elseif pathTokens[1] == SYS_EPUID then
            if hasUIDQuestHandler(from, pathTokens[2], event) then
                _RSVD_NAME_EPUID_eventHandlers[from][pathTokens[2]][event](from, value)
            else
                fnPostInvalidChat()
            end

        else
            fnPostInvalidChat()
        end
    end

    -- event process done
    -- clean the call stack itself, next event needs another call stack
    clearTLSTable()
end

--
-- )###"
