#include <amxmodx>
#include <fakemeta>
#include <reapi>

#pragma semicolon 1

new Trie:g_tFloodCounts, Trie:g_tFloodTimes, Trie:g_tShadowBans;
new g_cvar_mode, g_cvar_limit, g_cvar_window, g_cvar_ban_time, g_cvar_fake_time;
new g_cvar_name_delay, g_cvar_cmd_limit;

new bool:g_bVerified[33];
new Float:g_fLastNameChange[33];
new g_iCmdCount[33];
new Float:g_fCmdTime[33];

public plugin_init() {
    register_plugin("Ultimate Anti-Flood Protection", "2.0", "KOHAH_Style");

    g_cvar_mode = register_cvar("amx_antiflood_mode", "1");
    g_cvar_limit = register_cvar("amx_antiflood_limit", "5");
    g_cvar_window = register_cvar("amx_antiflood_window", "3.0");
    g_cvar_ban_time = register_cvar("amx_antiflood_bantime", "60");
    g_cvar_fake_time = register_cvar("amx_antiflood_fake_time", "25.0");
    g_cvar_name_delay = register_cvar("amx_antiflood_name_delay", "3.0");
    g_cvar_cmd_limit = register_cvar("amx_antiflood_cmd_limit", "50");

    g_tFloodCounts = TrieCreate();
    g_tFloodTimes = TrieCreate();
    g_tShadowBans = TrieCreate();

    set_task(10.0, "Task_CleanMemory", .flags="b");
    
    register_forward(FM_ClientCommand, "fw_ClientCommand");

    AutoCreateConfig();
}

public plugin_cfg() {
    set_task(2.0, "ForceEngineCvars");
}

public ForceEngineCvars() {
    set_cvar_num("sv_max_queries_sec", 3);
    set_cvar_num("sv_max_queries_window", 10);
    set_cvar_num("sv_max_queries_sec_global", 150);
    set_cvar_num("sv_stats", 0);
    server_print("[Anti-Flood] ReHLDS Engine protection CVARs forced successfully.");
}

public plugin_end() {
    TrieDestroy(g_tFloodCounts); 
    TrieDestroy(g_tFloodTimes); 
    TrieDestroy(g_tShadowBans);
}

public client_connect(id) {
    if(is_user_bot(id) || is_user_hltv(id)) return PLUGIN_CONTINUE;

    new szIP[16]; get_user_ip(id, szIP, charsmax(szIP), 1);
    new iSysTime = get_systime();
    new iMode = get_pcvar_num(g_cvar_mode);

    if(iMode == 1) {
        new iBanExpireTime;
        if(TrieGetCell(g_tShadowBans, szIP, iBanExpireTime)) {
            if(iSysTime < iBanExpireTime) {
                TrieSetCell(g_tShadowBans, szIP, iSysTime + get_pcvar_num(g_cvar_ban_time));
                rh_drop_client(id, "Anti-Flood: Blocked (Shadow Ban). Stop flood.");
                return PLUGIN_HANDLED;
            } else {
                TrieDeleteKey(g_tShadowBans, szIP);
            }
        }
    }

    new iCount = 0, iFirstTime = 0;
    TrieGetCell(g_tFloodCounts, szIP, iCount);
    TrieGetCell(g_tFloodTimes, szIP, iFirstTime);

    new Float:fWindow = get_pcvar_float(g_cvar_window);

    if(iFirstTime == 0 || (float(iSysTime) - float(iFirstTime)) > fWindow) {
        iCount = 1;
        TrieSetCell(g_tFloodTimes, szIP, iSysTime);
    } else {
        iCount++;
    }
    TrieSetCell(g_tFloodCounts, szIP, iCount);

    if(iCount > get_pcvar_num(g_cvar_limit)) {
        log_to_file("antiflood.log", "[FLOOD] %s | Mode: %d | Count: %d", szIP, iMode, iCount);
        
        if(iMode == 1) {
            TrieSetCell(g_tShadowBans, szIP, iSysTime + get_pcvar_num(g_cvar_ban_time));
            TrieDeleteKey(g_tFloodCounts, szIP);
            TrieDeleteKey(g_tFloodTimes, szIP);
        }

        rh_drop_client(id, "Anti-Flood: Limit exceeded. Wait a bit.");
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public client_putinserver(id) {
    if(is_user_bot(id) || is_user_hltv(id)) return;

    g_bVerified[id] = false;
    g_fLastNameChange[id] = get_gametime();
    g_iCmdCount[id] = 0;
    g_fCmdTime[id] = get_gametime();
    
    query_client_cvar(id, "fps_max", "ClientCvar_Result");
    
    set_task(get_pcvar_float(g_cvar_fake_time), "Task_CheckFake", id);
}

public client_infochanged(id) {
    if (!is_user_connected(id)) return PLUGIN_CONTINUE;

    new szNewName[32], szOldName[32];
    get_user_info(id, "name", szNewName, charsmax(szNewName));
    get_user_name(id, szOldName, charsmax(szOldName));

    if (!equal(szNewName, szOldName)) {
        new Float:fTime = get_gametime();
        if (fTime - g_fLastNameChange[id] < get_pcvar_float(g_cvar_name_delay)) {
            set_user_info(id, "name", szOldName);
            client_print_color(id, print_team_default, "^4[Anti-Flood]^1 Stop changing name so fast!");
            return PLUGIN_HANDLED;
        }
        g_fLastNameChange[id] = fTime;
    }
    return PLUGIN_CONTINUE;
}

public fw_ClientCommand(id) {
    if (!is_user_connected(id)) return FMRES_IGNORED;

    new Float:fTime = get_gametime();
    
    if (fTime - g_fCmdTime[id] > 1.0) {
        g_iCmdCount[id] = 1;
        g_fCmdTime[id] = fTime;
    } else {
        g_iCmdCount[id]++;
    }

    if (g_iCmdCount[id] > get_pcvar_num(g_cvar_cmd_limit)) {
        new szIP[16]; get_user_ip(id, szIP, charsmax(szIP), 1);
        
        if (get_pcvar_num(g_cvar_mode) == 1) {
            TrieSetCell(g_tShadowBans, szIP, get_systime() + get_pcvar_num(g_cvar_ban_time));
            log_to_file("antiflood.log", "[CMD FLOOD] %s | Shadow Banned for command spam.", szIP);
        } else {
            log_to_file("antiflood.log", "[CMD FLOOD] %s | Dropped for command spam (Drop Mode).", szIP);
        }
        
        rh_drop_client(id, "Anti-Flood: Command spam detected.");
        return FMRES_SUPERCEDE;
    }
    
    return FMRES_IGNORED;
}

public ClientCvar_Result(id, const cvar[], const value[]) {
    if(is_user_connected(id)) {
        g_bVerified[id] = true;
    }
}

public Task_CheckFake(id) {
    if(!is_user_connected(id)) return;
    
    if(!g_bVerified[id]) {
        new szIP[16]; get_user_ip(id, szIP, charsmax(szIP), 1);
        log_to_file("antiflood.log", "[FAKE PLAYER] Dropped fake client %s (No response in %d sec)", szIP, get_pcvar_num(g_cvar_fake_time));
        rh_drop_client(id, "Anti-Fake: Client validation failed.");
    }
}

public client_disconnected(id) {
    remove_task(id);
    g_bVerified[id] = false;
    g_iCmdCount[id] = 0;
}

public Task_CleanMemory() {
    TrieClear(g_tFloodCounts);
    TrieClear(g_tFloodTimes);

    new Snapshot:hSnapshot = TrieSnapshotCreate(g_tShadowBans);
    new szKey[16], iExpireTime, iSysTime = get_systime();
    new iLen = TrieSnapshotLength(hSnapshot);

    for(new i = 0; i < iLen; i++) {
        TrieSnapshotGetKey(hSnapshot, i, szKey, charsmax(szKey));
        if(TrieGetCell(g_tShadowBans, szKey, iExpireTime)) {
            if(iSysTime >= iExpireTime) {
                TrieDeleteKey(g_tShadowBans, szKey);
            }
        }
    }
    TrieSnapshotDestroy(hSnapshot);
}

AutoCreateConfig() {
    new szPath[256]; 
    get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
    
    add(szPath, charsmax(szPath), "/plugins");
    
    if (!dir_exists(szPath)) {
        mkdir(szPath);
    }

    add(szPath, charsmax(szPath), "/ultimate_antiflood.cfg");

    if (!file_exists(szPath)) {
        new iFile = fopen(szPath, "wt");
        if (iFile) {
            fputs(iFile, "// Ultimate Anti-Flood Hybrid Config^n^n");
            fputs(iFile, "// Режим: 0 - Только отбой (Drop), 1 - Теневой бан (Shadow Ban)^n");
            fputs(iFile, "amx_antiflood_mode ^"1^"^n^n");
            fputs(iFile, "// Лимит коннектов с одного IP^n");
            fputs(iFile, "amx_antiflood_limit ^"5^"^n^n");
            fputs(iFile, "// Окно времени (сек) для проверки лимита^n");
            fputs(iFile, "amx_antiflood_window ^"3.0^"^n^n");
            fputs(iFile, "// Время бана (сек). В режиме 1 продлевается при атаке.^n");
            fputs(iFile, "amx_antiflood_bantime ^"60^"^n^n");
            fputs(iFile, "// Время (сек) ожидания ответа от клиента на проверку фейка (xFakePlayers).^n");
            fputs(iFile, "// Рекомендуется 25.0, чтобы не кикало живых игроков с плохим интернетом.^n");
            fputs(iFile, "amx_antiflood_fake_time ^"25.0^"^n^n");
            fputs(iFile, "// Задержка между сменой ника (сек)^n");
            fputs(iFile, "amx_antiflood_name_delay ^"3.0^"^n^n");
            fputs(iFile, "// Лимит команд от клиента в секунду (защита от Command Flood)^n");
            fputs(iFile, "amx_antiflood_cmd_limit ^"50^"^n");
            fclose(iFile);
        }
    }
    server_cmd("exec %s", szPath);
}