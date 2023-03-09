--, u8R"###(
--

-- event handlers
-- to support all kinds of quests, merchant scripts, etc

-- merchant event handler, optional, structured as
-- {
--     [SYS_NPCINIT] = function(uid, value)
--     end
--
--     ['npc_tag_1'] = function(uid, value)
--     end
-- }
local _RSVD_NAME_defaultChatEventHandlers = nil

-- event handlers valid for all players
-- when player in this table clicks npc, handlers in this table will be evaludated, structured as
-- {
--     ['商人的灵魂'] = {
--         [SYS_CHECKACTIVE] = function(uid)
--             -- checks uid level, money, etc
--             -- return true if this quest can be activated for given uid
--         end
--
--         [SYS_NPCINIT] = function(uid, value)
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
--         [SYS_NPCINIT] = function(uid, value)
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
-- | 随便聊聊                                                             | <-- display this line if _RSVD_NAME_defaultChatEventHandlers valid
-- |                                                                      |
-- | 退出                                                                 |
-- +---------------------------------------------------------------------(x)
--
-- 1. this handler itself has no way to inform player when a quest becomes activated
--    need system message or other way to inform players
--
-- 2. dynamically generated by quest system
local _RSVD_NAME_passiveQuestEventHandlers = nil

-- event handlers valid for specific player uids
-- when player clicks npc, handlers in this table will be evaludated, structured as
-- {
--     [1234567] = {
--         ['商人的灵魂'] = {
--             [SYS_NPCINIT] = function(uid, value)
--             end
--
--             ['npc_tag_1'] = function(uid, value)
--             end
--         },
--
--         ['王寡妇的剪刀'] = {
--             [SYS_NPCINIT] = function(uid, value)
--             end
--
--             ['npc_tag_1'] = function(uid, value)
--             end
--         }
--     }
--
--     [1034297] = {
--         ['半兽人的传闻'] = {
--             [SYS_NPCINIT] = function(uid, value)
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
-- | 随便聊聊                                                             | <-- display this line if _RSVD_NAME_defaultChatEventHandlers valid
-- |                                                                      |
-- | 退出                                                                 |
-- +---------------------------------------------------------------------(x)
--
-- 1. the table key like '商人的灵魂' may not be the quest name, just a quest tag, a quest
--    in different stages can use different tags
--
-- 2. all these tables of handlers are dynamically generated, and saved in this _RSVD_NAME_uidActivedEventHandlers, not in database
--    so when server reboot, all these tables of handlers need to be re-generated, this is done by quest system enter function
local _RSVD_NAME_uidActivedEventHandlers = nil

local function _RSVD_NAME_waitEvent()
    while true do
        local resList = {_RSVD_NAME_pollCallStackEvent(getTLSTable().uid)}
        if next(resList) == nil then
            coroutine.yield()
        else
            local from  = resList[1]
            local event = resList[2]

            assertType(from, 'integer')
            assertType(event, 'string')

            return table.unpack(resList)
        end
    end
end

-- send lua code to uid to execute
-- used to support complicated logic through actor message
function uidExecuteString(uid, code)
    assertType(uid, 'integer')
    assertType(code, 'string')
    _RSVD_NAME_sendCallStackRemoteCall(getTLSTable().uid, uid, code, false)

    local resList = {_RSVD_NAME_waitEvent()}
    if resList[1] ~= uid then
        fatalPrintf('Send lua code to uid %s but get response from %d', uid, resList[1])
    end

    if resList[2] ~= SYS_EXECDONE then
        fatalPrintf('Wait event as SYS_EXECDONE but get %s', resList[2])
    end

    return table.unpack(resList, 3)
end

function uidExecute(uid, code, ...)
    return uidExecuteString(uid, code:format(...))
end

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

function uidPostXML(uid, xmlFormat, ...)
    if type(uid) ~= 'number' or type(xmlFormat) ~= 'string' then
        fatalPrintf("invalid argument type: uid: %s, xmlFormat: %s", type(uid), type(xmlFormat))
    end
    uidPostXMLString(uid, xmlFormat:format(...))
end

function setEventHandler(eventHandler)
    if _RSVD_NAME_defaultChatEventHandlers ~= nil then
        fatalPrintf('Call setEventHandler() twice')
    end

    assertType(eventHandler, 'table')
    if eventHandler[SYS_NPCINIT] == nil then
        fatalPrintf('Event handler does not support SYS_NPCINIT')
    end

    if type(eventHandler[SYS_NPCINIT]) ~= 'function' then
        fatalPrintf('Event handler for SYS_NPCINIT is not callable')
    end

    _RSVD_NAME_defaultChatEventHandlers = eventHandler
end

function hasEventHandler(event)
    if event == nil then
        return _RSVD_NAME_defaultChatEventHandlers ~= nil
    end

    assertType(event, 'string')
    assert(hasChar(event))

    if _RSVD_NAME_defaultChatEventHandlers == nil then
        return false
    end

    assertType(_RSVD_NAME_defaultChatEventHandlers, 'table')
    if _RSVD_NAME_defaultChatEventHandlers[event] == nil then
        return false
    end

    assertType(_RSVD_NAME_defaultChatEventHandlers[event], 'function')
    return true
end

-- entry coroutine for event handling
-- it's event driven, i.e. if the event sink has no event, this coroutine won't get scheduled

function _RSVD_NAME_coth_main(uid)
    -- setup current call stack uid
    -- all functions in current call stack can use this implicit argument as *this*
    getTLSTable().uid = uid
    getTLSTable().startTime = getNanoTstamp()

    -- poll the event sink
    -- current call stack only process 1 event and then clean itself
    local from, event, value = _RSVD_NAME_waitEvent()

    assertType(from, 'integer')
    assertType(event, 'string')

    if event ~= SYS_NPCDONE then
        if hasEventHandler(event) then
            _RSVD_NAME_defaultChatEventHandlers[event](from, value)
        else
            uidPostXML(uid,
            [[
                <layout>
                    <par>我听不懂你在说什么。。。</par>
                    <par></par>
                    <par><event id="%s">关闭</event></par>
                </layout>
            ]], SYS_NPCDONE)
        end
    end

    -- event process done
    -- clean the call stack itself, next event needs another call stack
    clearTLSTable()
end

--
-- )###"
