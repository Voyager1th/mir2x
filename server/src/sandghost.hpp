/*
 * =====================================================================================
 *
 *       Filename: sandghost.hpp
 *        Created: 07/24/2021 03:48:41 AM
 *    Description:
 *
 *        Version: 1.0
 *       Revision: none
 *       Compiler: gcc
 *
 *         Author: ANHONG
 *          Email: anhonghe@gmail.com
 *   Organization: USTC
 *
 * =====================================================================================
 */

#pragma once
#include "dbcomid.hpp"
#include "monster.hpp"

class SandGhost final: public Monster
{
    private:
        bool m_standMode = false;

    public:
        SandGhost(ServerMap *mapPtr, int argX, int argY, int argDir)
            : Monster(DBCOM_MONSTERID(u8"沙鬼"), mapPtr, argX, argY, argDir, 0)
        {}

    protected:
        corof::long_jmper updateCoroFunc() override;

    protected:
        ActionNode makeActionStand() const override
        {
            return ActionStand
            {
                .x = X(),
                .y = Y(),
                .direction = Direction(),
                .extParam
                {
                    .sandGhost
                    {
                        .standMode = m_standMode,
                    },
                },
            };
        }

        void setStandMode(bool standMode)
        {
            if(standMode != m_standMode){
                m_standMode = standMode;
                dispatchAction(ActionTransf
                {
                    .x = X(),
                    .y = Y(),

                    .direction = Direction(),
                    .extParam
                    {
                        .sandGhost
                        {
                            .standModeReq = standMode,
                        }
                    },
                });
            }
        }

    protected:
        bool struckDamage(const DamageNode &damage)
        {
            if(!m_standMode){
                switch(damage.magicID){
                    case DBCOM_MAGICID(u8"火墙"):
                    case DBCOM_MAGICID(u8"地狱火"):
                    case DBCOM_MAGICID(u8"冰沙掌"):
                        {
                            setStandMode(true);
                            break;
                        }
                    default:
                        {
                            break;
                        }
                }
                return true;
            }

            if(damage){
                m_sdHealth.HP = std::max<int>(0, m_sdHealth.HP - damage.damage);
                dispatchHealth();

                if(m_sdHealth.HP <= 0){
                    goDie();
                }
                return true;
            }
            return false;
        }
};