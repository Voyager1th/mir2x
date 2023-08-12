#include "luaf.hpp"
#include "uidf.hpp"
#include "strf.hpp"
#include "quest.hpp"
#include "dbpod.hpp"
#include "filesys.hpp"
#include "monoserver.hpp"

extern DBPod *g_dbPod;
extern MonoServer *g_monoServer;

Quest::Quest(const SDInitQuest &initQuest)
    : ServerObject(uidf::getQuestUID(initQuest.questID))
    , m_scriptName(initQuest.fullScriptName)
{
    if(!g_dbPod->createQuery(u8R"###(select name from sqlite_master where type='table' and name='%s')###", getQuestDBName().c_str()).executeStep()){
        g_dbPod->exec(
            u8R"###( create table %s(                                          )###"
            u8R"###(     fld_dbid         int unsigned not null,               )###"
            u8R"###(     fld_timestamp    int unsigned not null,               )###"
            u8R"###(     fld_state        blob             null,               )###"
            u8R"###(     fld_flags        blob             null,               )###"
            u8R"###(     fld_team         blob             null,               )###"
            u8R"###(     fld_vars         blob             null,               )###"
            u8R"###(     fld_desp         blob             null,               )###"
            u8R"###(     fld_npcbehaviors blob             null,               )###"
            u8R"###(                                                           )###"
            u8R"###(     foreign key (fld_dbid) references tbl_char(fld_dbid), )###"
            u8R"###(     primary key (fld_dbid)                                )###"
            u8R"###( );                                                        )###", getQuestDBName().c_str());
    }
}

void Quest::onActivate()
{
    ServerObject::onActivate();
    m_actorPod->forward(uidf::getServiceCoreUID(), {AM_REGISTERQUEST, cerealf::serialize(SDRegisterQuest
    {
        .name = getQuestName(),
    })});

    m_luaRunner = std::make_unique<ServerLuaCoroutineRunner>(m_actorPod);

    m_luaRunner->bindFunction("getQuestName", [this]() -> std::string
    {
        return getQuestName();
    });

    m_luaRunner->bindFunction("getMainScriptThreadKey", [this]() -> uint64_t
    {
        return m_mainScriptThreadKey;
    });

    m_luaRunner->bindFunction("dbGetUIDQuestDesp", [this](uint64_t uid, sol::this_state s) -> sol::object
    {
        sol::state_view sv(s);
        const auto dbName = getQuestDBName();
        const auto dbid = uidf::getPlayerDBID(uid);

        auto queryStatement = g_dbPod->createQuery(u8R"###(select fld_desp from %s where fld_dbid=%llu and fld_desp is not null)###", dbName.c_str(), to_llu(dbid));
        if(!queryStatement.executeStep()){
            return sol::make_object(sv, sol::nil);
        }
        return luaf::buildLuaObj(sol::state_view(s), std::move(cerealf::deserialize<luaf::luaVar>(queryStatement.getColumn(0))));
    });

    m_luaRunner->bindFunction("_RSVD_NAME_setUIDQuestDesp", [this](uint64_t uid, sol::object obj)
    {
        const auto dbName = getQuestDBName();
        const auto dbid = uidf::getPlayerDBID(uid);
        const auto timestamp = hres_tstamp().to_nsec();

        SDQuestDesp sdQD
        {
            .name = getQuestName(),
        };

        if(obj == sol::nil){
            g_dbPod->exec(
                u8R"###( insert into %s(fld_dbid, fld_timestamp, fld_desp) )###"
                u8R"###( values                                            )###"
                u8R"###(     (%llu, %llu, null)                            )###"
                u8R"###(                                                   )###"
                u8R"###( on conflict(fld_dbid) do                          )###"
                u8R"###( update set                                        )###"
                u8R"###(                                                   )###"
                u8R"###(     fld_timestamp=%llu,                           )###"
                u8R"###(     fld_desp=null                                 )###",

                dbName.c_str(),

                to_llu(dbid),
                to_llu(timestamp),
                to_llu(timestamp));

            sdQD.desp.reset();
        }
        else if(obj.is<std::string>()){
            auto query = g_dbPod->createQuery(
                u8R"###( insert into %s(fld_dbid, fld_timestamp, fld_desp) )###"
                u8R"###( values                                            )###"
                u8R"###(     (%llu, %llu, ?)                               )###"
                u8R"###(                                                   )###"
                u8R"###( on conflict(fld_dbid) do                          )###"
                u8R"###( update set                                        )###"
                u8R"###(                                                   )###"
                u8R"###(     fld_timestamp=%llu,                           )###"
                u8R"###(     fld_desp=excluded.fld_desp                    )###",

                dbName.c_str(),

                to_llu(dbid),
                to_llu(timestamp),
                to_llu(timestamp));

            query.bind(1, cerealf::serialize(luaf::buildLuaVar(obj)));
            query.exec();

            sdQD.desp = obj.as<std::string>();
        }
        else{
            throw fflerror("invalid type: %s", to_cstr(sol::type_name(obj.lua_state(), obj.get_type())));
        }

        forwardNetPackage(uid, SM_QUESTDESP, cerealf::serialize(sdQD));
    });

    m_luaRunner->bindFunction("dbGetUIDQuestField", [this](uint64_t uid, std::string fieldName, sol::this_state s) -> sol::object
    {
        sol::state_view sv(s);
        const auto dbName = getQuestDBName();
        const auto dbid = uidf::getPlayerDBID(uid);

        fflassert(str_haschar(fieldName));
        fflassert(fieldName.starts_with("fld_"));

        auto queryStatement = g_dbPod->createQuery(u8R"###(select %s from %s where fld_dbid=%llu and %s is not null)###", fieldName.c_str(), dbName.c_str(), to_llu(dbid), fieldName.c_str());
        if(!queryStatement.executeStep()){
            return sol::make_object(sv, sol::nil);
        }
        return luaf::buildLuaObj(sol::state_view(s), std::move(cerealf::deserialize<luaf::luaVar>(queryStatement.getColumn(0))));
    });

    m_luaRunner->bindFunction("dbSetUIDQuestField", [this](uint64_t uid, std::string fieldName, sol::object obj)
    {
        const auto dbName = getQuestDBName();
        const auto dbid = uidf::getPlayerDBID(uid);
        const auto timestamp = hres_tstamp().to_nsec();

        fflassert(str_haschar(fieldName));
        fflassert(fieldName.starts_with("fld_"));

        if(obj == sol::nil){
            g_dbPod->exec(
                u8R"###( insert into %s(fld_dbid, fld_timestamp, %s) )###"
                u8R"###( values                                      )###"
                u8R"###(     (%llu, %llu, null)                      )###"
                u8R"###(                                             )###"
                u8R"###( on conflict(fld_dbid) do                    )###"
                u8R"###( update set                                  )###"
                u8R"###(                                             )###"
                u8R"###(     fld_timestamp=%llu,                     )###"
                u8R"###(     %s=null                                 )###",

                dbName.c_str(),
                fieldName.c_str(),

                to_llu(dbid),
                to_llu(timestamp),

                to_llu(timestamp),
                fieldName.c_str());
        }
        else{
            auto query = g_dbPod->createQuery(
                u8R"###( insert into %s(fld_dbid, fld_timestamp, %s) )###"
                u8R"###( values                                      )###"
                u8R"###(     (%llu, %llu, ?)                         )###"
                u8R"###(                                             )###"
                u8R"###( on conflict(fld_dbid) do                    )###"
                u8R"###( update set                                  )###"
                u8R"###(                                             )###"
                u8R"###(     fld_timestamp=%llu,                     )###"
                u8R"###(     %s=excluded.%s                          )###",

                dbName.c_str(),
                fieldName.c_str(),

                to_llu(dbid),
                to_llu(timestamp),

                to_llu(timestamp),
                fieldName.c_str(),
                fieldName.c_str());

            query.bind(1, cerealf::serialize(luaf::buildLuaVar(obj)));
            query.exec();
        }
    });

    m_luaRunner->bindFunction("_RSVD_NAME_dbSetUIDQuestStateDone", [this](uint64_t uid)
    {
        // finialize quest
        // all quest vars get removed except fld_state

        const auto dbName = getQuestDBName();
        const auto dbid = uidf::getPlayerDBID(uid);
        const auto timestamp = hres_tstamp().to_nsec();

        auto query = g_dbPod->createQuery(
            u8R"###( replace into %s(fld_dbid, fld_timestamp, fld_state) )###"
            u8R"###( values                                              )###"
            u8R"###(     (%llu, %llu, ?)                                 )###",

            dbName.c_str(),

            to_llu(dbid),
            to_llu(timestamp));

        query.bind(1, cerealf::serialize(luaf::buildLuaVar(std::vector<std::string>{SYS_DONE})));
        query.exec();
    });

    m_luaRunner->bindFunctionCoop("_RSVD_NAME_modifyQuestTriggerType", [this](LuaCoopResumer onDone, int triggerType, bool enable)
    {
        fflassert(triggerType >= SYS_ON_BEGIN, triggerType);
        fflassert(triggerType <  SYS_ON_END  , triggerType);

        auto closed = std::make_shared<bool>(false);
        onDone.pushOnClose([closed]()
        {
            *closed = true;
        });

        AMModifyQuestTriggerType amMQTT;
        std::memset(&amMQTT, 0, sizeof(amMQTT));

        amMQTT.type = triggerType;
        amMQTT.enable = enable;

        m_actorPod->forward(uidf::getServiceCoreUID(), {AM_MODIFYQUESTTRIGGERTYPE, amMQTT}, [closed, onDone, this](const ActorMsgPack &rmpk)
        {
            if(*closed){
                return;
            }
            else{
                onDone.popOnClose();
            }

            // expected an reply
            // this makes sure when modifyQuestTriggerType() returns, the trigger has already been enabled/disabled

            switch(rmpk.type()){
                case AM_OK:
                    {
                        onDone(true);
                        break;
                    }
                default:
                    {
                        onDone();
                        break;
                    }
            }
        });
    });

    m_luaRunner->bindFunction("runQuestThread", [this](sol::function func)
    {
        m_luaRunner->spawn(m_threadKey++, func, [this](const sol::protected_function_result &pfr)
        {
            std::vector<std::string> error;
            if(m_luaRunner->pfrCheck(pfr, [&error](const std::string &s){ error.push_back(s); })){
                if(pfr.return_count() > 0){
                    // drop quest state function result
                }
            }
            else{
                if(error.empty()){
                    error.push_back(str_printf("unknown error for runThread"));
                }

                for(const auto &line: error){
                    g_monoServer->addLog(LOGTYPE_WARNING, "%s", to_cstr(line));
                }
            }
        });
    });

    m_luaRunner->bindFunction("_RSVD_NAME_switchUIDQuestState", [this](uint64_t uid, const char *fsm, sol::object state, sol::object args, bool restore, sol::function func, uint64_t threadKey, uint64_t threadSeqID)
    {
        auto &fsmStateRunner = m_uidStateRunner[fsm];
        if(const auto p = fsmStateRunner.find(uid); p != fsmStateRunner.end()){
            if(p->second != threadKey){
                // there is already a thread running quest state function for this uid
                // and it's not current thread, i.e.
                //
                //     quest_op_1 = function(uid)
                //         ...
                //         ...
                //
                //         uidExecute(uid,
                //         [[
                //             addTrigger(SYS_ON_KILL, function(monsterID)
                //                 if ... then
                //                     uidExecute(questUID, [=[ setUIDQuestState(uid, "quest_op_2") ]=])
                //                 end
                //             end)
                //         ]])
                //
                //         pause(9999999) -- or any function that can yield
                //     end
                //
                // previous state pauses in idle state, waiting timeout
                // now another thread terminates it and switch to new quest state quest_op_2

                // TODO should I erase before close ?
                //      close() shall only do clean work and shall not trigger setUIDQuestState() again
                //
                // no threadSeqID saved/provided
                // shall be good enough since quest luaRunner has unique threadKey
                m_luaRunner->close(p->second);
            }
            fsmStateRunner.erase(p);
        }
        else{
            // first time setup state
            // state may not be SYS_ENTER if called by restoring state
        }

        // always terminate current thread when calling _RSVD_NAME_switchUIDQuestState
        // it can be cases that state starts to switch itself to another state
        //
        //     quest_op_1 = function(uid)
        //         ...
        //         ...
        //         setUIDQuestState(uid, "quest_op_2")
        //     end
        //
        // or an simple uidExecute() remote call to switch state
        //
        //     addTrigger(SYS_ON_LEVELUP, function(uid)
        //         uidExecute(questUID, [=[ setUIDQuestState(uid, SYS_ENTER) ]=])
        //     end)
        //
        // can not close thread directly since current call still uses its stack
        addDelay(0, [threadKey, threadSeqID, this]()
        {
            m_luaRunner->close(threadKey, threadSeqID);
        });

        // immediately switch to new state
        // current state has been put into idle state:
        //
        //     while true do
        //         coroutine.yield()
        //     end
        //
        // and it will be closed by addDelay()
        // don't close immediately since current call still uses its stack

        if(state != sol::nil){
            fflassert(state.is<std::string>());
            const auto stateStr = state.as<std::string>();
            const auto fsmLuaStr   = luaf::quotedLuaString(fsm);
            const auto stateLuaStr = luaf::quotedLuaString(stateStr);
            const auto sdbArgsLuaStr = (args == sol::nil) ? std::string("nil") : luaf::quotedLuaString(cerealf::base64_serialize(luaf::buildLuaVar(args)).c_str());
            m_luaRunner->spawn(fsmStateRunner[uid] = m_threadKey++, str_printf(

            R"###( _RSVD_NAME_currFSMName = %s                         )###"
            R"###( _RSVD_NAME_enterUIDQuestState(%llu, %s, %s, %s, %s) )###",

            fsmLuaStr.c_str(),
            to_llu(uid), fsmLuaStr.c_str(), stateLuaStr.c_str(), sdbArgsLuaStr.c_str(), to_boolcstr(restore)),

            {},

            [&fsmStateRunner, uid, func, stateStr, this](const sol::protected_function_result &pfr)
            {
                fsmStateRunner.erase(uid);
                std::vector<std::string> error;

                if(m_luaRunner->pfrCheck(pfr, [&error](const std::string &s){ error.push_back(s); })){
                    if(pfr.return_count() > 0){
                        // drop quest state function result
                    }

                    if(func != sol::nil){
                        m_luaRunner->spawn(m_threadKey++, func, [stateStr, this](const sol::protected_function_result &pfr)
                        {
                            std::vector<std::string> error;
                            if(m_luaRunner->pfrCheck(pfr, [&error](const std::string &s){ error.push_back(s); })){
                                if(pfr.return_count() > 0){
                                    // drop quest state function result
                                }
                            }
                            else{
                                if(error.empty()){
                                    error.push_back(str_printf("unknown error in after func for quest state: %s", to_cstr(str_quoted(stateStr))));
                                }

                                for(const auto &line: error){
                                    g_monoServer->addLog(LOGTYPE_WARNING, "%s", to_cstr(line));
                                }
                            }
                        });
                    }
                }
                else{
                    if(error.empty()){
                        error.push_back(str_printf("unknown error for quest state: %s", to_cstr(str_quoted(stateStr))));
                    }

                    for(const auto &line: error){
                        g_monoServer->addLog(LOGTYPE_WARNING, "%s", to_cstr(line));
                    }
                }
            });
        }
    });

    m_luaRunner->bindFunctionCoop("_RSVD_NAME_loadMap", [this](LuaCoopResumer onDone, std::string mapName)
    {
        fflassert(str_haschar(mapName));

        auto closed = std::make_shared<bool>(false);
        onDone.pushOnClose([closed, this]()
        {
            *closed = true;
        });

        AMLoadMap amLM;
        std::memset(&amLM, 0, sizeof(AMLoadMap));

        amLM.mapID = DBCOM_MAPID(to_u8cstr(mapName));
        amLM.activateMap = true;

        m_actorPod->forward(uidf::getServiceCoreUID(), {AM_LOADMAP, amLM}, [closed, mapID = amLM.mapID, onDone, this](const ActorMsgPack &mpk)
        {
            if(*closed){
                return;
            }
            else{
                onDone.popOnClose();
            }

            switch(mpk.type()){
                case AM_LOADMAPOK:
                    {
                        const auto amLMOK = mpk.conv<AMLoadMapOK>();
                        onDone(amLMOK.uid);
                        break;
                    }
                default:
                    {
                        onDone();
                        break;
                    }
            }
        });
    });

    m_luaRunner->pfrCheck(m_luaRunner->execRawString(BEGIN_LUAINC(char)
#include "quest.lua"
    END_LUAINC()));

    // define all functions needed for the quest
    // but don't execute them here since they may require coroutine environment
    m_luaRunner->pfrCheck(m_luaRunner->execFile(m_scriptName.c_str()));

    m_luaRunner->spawn(m_mainScriptThreadKey, str_printf(
        R"#( do                           )#""\n"
        R"#(     getTLSTable().uid = %llu )#""\n"
        R"#(     return main()            )#""\n"
        R"#( end                          )#""\n", to_llu(UID())));
}

void Quest::operateAM(const ActorMsgPack &mpk)
{
    switch(mpk.type()){
        case AM_METRONOME:
            {
                on_AM_METRONOME(mpk);
                break;
            }
        case AM_REMOTECALL:
            {
                on_AM_REMOTECALL(mpk);
                break;
            }
        case AM_RUNQUESTTRIGGER:
            {
                on_AM_RUNQUESTTRIGGER(mpk);
                break;
            }
        default:
            {
                throw fflerror("unsupported message: %s", mpkName(mpk.type()));
            }
    }
}

void Quest::dumpUIDQuestField(uint64_t uid, const std::string &fieldName) const
{
    const auto dbName = getQuestDBName();
    const auto dbid = uidf::getPlayerDBID(uid);

    fflassert(str_haschar(fieldName));
    fflassert(fieldName.starts_with("fld_"));

    auto queryStatement = g_dbPod->createQuery(u8R"###(select %s from %s where fld_dbid=%llu and %s is not null)###", fieldName.c_str(), dbName.c_str(), to_llu(dbid), fieldName.c_str());
    if(queryStatement.executeStep()){
        std::cout << str_printf("table %s, uid %llu, dbid %llu, field %s: %s", dbName.c_str(), to_llu(uid), to_llu(dbid), fieldName.c_str(), str_any(cerealf::deserialize<luaf::luaVar>(queryStatement.getColumn(0))).c_str()) << std::endl;
    }
    else{
        std::cout << str_printf("table %s, uid %llu, dbid %llu, field %s: no result", dbName.c_str(), to_llu(uid), to_llu(dbid), fieldName.c_str()) << std::endl;
    }
}
