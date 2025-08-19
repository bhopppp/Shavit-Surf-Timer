#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <shavit/core>
#include <shavit/wr>
#include <shavit/replay-playback>
#include <shavit/replay-recorder>
#include <convar_class>

#define MAX_REPLAY 5
#undef REQUIRE_EXTENSIONS
#include <cstrike>

enum struct replayinfo_t
{
    bool bHasReplay;
    int iTrack;
    int iStage;
    int iStyle;
    int timestamp;
    frame_cache_t aCache;
}

enum struct persistent_replaydata_t
{
    int iSteamID;
    int iDisconnectTime;
    int iLastIndex;
    ArrayList aReplayInfo;
}

Handle gH_Cookie_Enabled;
Handle gH_Cookie_AutoOverWrite;
Handle gH_Cookie_PrintSavedMessage;

Convar gCV_PersistDataExpireTime = null;

replayinfo_t gA_ReplayInfo[MAXPLAYERS + 1][MAX_REPLAY];

ArrayList gA_PersisReplayInfo;

chatstrings_t gS_ChatStrings;
stylestrings_t gS_StyleStrings[STYLE_LIMIT];

char gS_Map[PLATFORM_MAX_PATH];
char gS_PreviousMap[PLATFORM_MAX_PATH];

int gI_LastSavedIndex[MAXPLAYERS + 1];
int gI_PlayerFinishFrame[MAXPLAYERS + 1];

bool gB_Enabled[MAXPLAYERS + 1];
bool gB_AutoOverWrite[MAXPLAYERS + 1];
bool gB_PrintSavedMessage[MAXPLAYERS + 1];


bool gB_Late;

public Plugin myinfo = 
{
    name = "[shavit-surf] Personal replay",
    author = "KikI",
    description = "Save client's most recent replay on cache.",
    version = "1.1",
    url = "https://github.com/bhopppp/Shavit-Surf-Timer"
};

public void OnPluginStart()
{
    LoadTranslations("shavit-common.phrases");
    LoadTranslations("shavit-personalreplay.phrases");

    gH_Cookie_Enabled = RegClientCookie("shavit_personalreplay_enabled", "feature enabled", CookieAccess_Public);
    gH_Cookie_AutoOverWrite = RegClientCookie("shavit_personalreplay_autooverwrite", "auto overwrite", CookieAccess_Public);
    gH_Cookie_PrintSavedMessage = RegClientCookie("shavit_personalreplay_printsavedmessage", "print savedmessage", CookieAccess_Public);

    gCV_PersistDataExpireTime = new Convar("shavit_personalreplay_persistdata_expiredtime", "600", "How long persist data expire for disconnected users in seconds?\n 0 - Disable persist data\n -1 - Until map changed", 0, true, -1.0);

    RegConsoleCmd("sm_personalreplay", Command_PersonalReplay, "Open personal replay menu.");
    RegConsoleCmd("sm_myreplay", Command_PersonalReplay, "Open personal replay menu.");
    RegConsoleCmd("sm_rewatch", Command_Rewatch, "Watch client's most recent replay.");

    gA_PersisReplayInfo = new ArrayList(sizeof(persistent_replaydata_t));

    Convar.AutoExecConfig();

    CreateTimer(1.0, Timer_PersistData, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

    if (gB_Late)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i))
            {
                continue;
            }

            if (!AreClientCookiesCached(i))
            {
                continue;
            }

            OnClientCookiesCached(i);
        }
    }
}

public void OnClientCookiesCached(int client)
{
    if (!GetClientCookieBool(client, gH_Cookie_Enabled, gB_Enabled[client]))
    {
        gB_Enabled[client] = true;
        SetClientCookieBool(client, gH_Cookie_Enabled, true);
    }

    if (!GetClientCookieBool(client, gH_Cookie_AutoOverWrite, gB_AutoOverWrite[client]))
    {
        gB_AutoOverWrite[client] = true;
        SetClientCookieBool(client, gH_Cookie_AutoOverWrite, true);
    }

    if (!GetClientCookieBool(client, gH_Cookie_PrintSavedMessage, gB_PrintSavedMessage[client]))
    {
        gB_PrintSavedMessage[client] = true;
        SetClientCookieBool(client, gH_Cookie_PrintSavedMessage, true);
    }
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleStringsStruct(i, gS_StyleStrings[i]);
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void OnClientAuthorized(int client, const char[] auth)
{
    if(gCV_PersistDataExpireTime.IntValue != 0)
    {
        LoadPersistentData(client);
    }
}

public void OnClientDisconnect(int client)
{
    if(gCV_PersistDataExpireTime.IntValue != 0)
    {
        SavePersistentData(client);
    }
    
    for(int i = 0; i < MAX_REPLAY; i++)
    {
        ResetReplayData(gA_ReplayInfo[client][i], false);
    }

    gI_LastSavedIndex[client] = 0;
    gI_PlayerFinishFrame[client] = -1;
}

public void OnMapStart()
{
	GetLowercaseMapName(gS_Map);

	if (!StrEqual(gS_Map, gS_PreviousMap, false))
	{
		int iLength = gA_PersisReplayInfo.Length;

		for(int i = iLength - 1; i >= 0; i--)
		{
			persistent_replaydata_t aData;
			gA_PersisReplayInfo.GetArray(i, aData);
			DeletePersistentData(i, aData, true);
		}

		for (int i = 1; i <= MaxClients; i++)
		{
			for(int j = 0; j < MAX_REPLAY; j++)
			{
				ResetReplayData(gA_ReplayInfo[i][j], true);
			}			
		}
	}
}

public void OnMapEnd()
{
	gS_PreviousMap = gS_Map;
}

public Action Command_PersonalReplay(int client, int args)
{
    if(!IsValidClient2(client))
    {
        return Plugin_Continue;
    }
    
    ShowPersonaReplayMenu(client);

    return Plugin_Handled;
}

public Action Command_Rewatch(int client, int args)
{
	if(!IsValidClient2(client))
	{
		return Plugin_Continue;
	}

	if(gA_ReplayInfo[client][gI_LastSavedIndex[client]].aCache.aFrames == null)
	{
		Shavit_PrintToChat(client, "%T", "NoRecentReplay", client);
		return Plugin_Continue;
	}

	StartPersonalReplay(client, gI_LastSavedIndex[client]);

	return Plugin_Handled;
}

public void ShowPersonaReplayMenu(int client)
{
    Menu menu = new Menu(PersonaReplay_MenuHanlder);
    
    int timestamp = GetTime();
    char sMenu[64];
    char sInfo[8];
    char sTrack[32];
    char sTime[16];

    int count = 0;

    FormatEx(sMenu, sizeof(sMenu), "%T\n ", "RefreshMenu", client);
    menu.AddItem("refresh", sMenu);

    for (int i = 0; i < MAX_REPLAY; i++)
    {
        if(!gA_ReplayInfo[client][i].bHasReplay)
        {
            FormatEx(sMenu, sizeof(sMenu), "#%d |  %T\n ", i+1, "NoReplay", client);
            menu.AddItem("0", sMenu, ITEMDRAW_DISABLED);
            continue;
        }

        count++;
        int timediff = (timestamp - gA_ReplayInfo[client][i].timestamp) / 60;

        IntToString(i, sInfo, 8);

        FormatSeconds(gA_ReplayInfo[client][i].aCache.fTime, sTime, 16, true);

        if(gA_ReplayInfo[client][i].iStage == 0)
        {
            GetTrackName(client, gA_ReplayInfo[client][i].iTrack, sTrack, 32);
        }
        else
        {
            FormatEx(sTrack, 32, "%T %d", "StageText", client, gA_ReplayInfo[client][i].iStage);
        }

        FormatEx(sMenu, sizeof(sMenu), "#%d |  %T\n ", i+1, "ReplayInfo", client, sTrack, gS_StyleStrings[gA_ReplayInfo[client][i].iStyle].sStyleName, sTime, timediff);

        menu.AddItem(sInfo, sMenu);
    }

    FormatEx(sMenu, sizeof(sMenu), "%T", "Option", client);
    menu.AddItem("option", sMenu);

    SetMenuTitle(menu, "%T", "PersonalReplayMenuTitle", client, count, MAX_REPLAY);

    menu.Display(client, MENU_TIME_FOREVER);
}

public int PersonaReplay_MenuHanlder(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[8];
        menu.GetItem(param2, sInfo, 8);

        if(StrEqual(sInfo, "refresh"))
        {
            ShowPersonaReplayMenu(param1);
        }
        else if(StrEqual(sInfo, "option"))
        {
            ShowOptionMenu(param1);
        }
        else
        {
            int index = StringToInt(sInfo);

            Menu submenu = new Menu(StartReplay_MenuHanlder);
            submenu.ExitBackButton = true;
            SetMenuTitle(submenu, "%T\n ", "PersonalReplaySubMenuTitle", param1, index+1);
            char sMenu[32];

            FormatEx(sMenu, 32, "%T", "StartReplay", param1, ITEMDRAW_DEFAULT);
            submenu.AddItem(sInfo, sMenu);

            FormatEx(sMenu, 32, "%T", "DeleteReplay", param1);
            submenu.AddItem(sInfo, sMenu);

            submenu.Display(param1, MENU_TIME_FOREVER);            
        }
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

public int StartReplay_MenuHanlder(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[8];
        menu.GetItem(param2, sInfo, 8);

        int index = StringToInt(sInfo);

        switch (param2)
        {
            case 0:
            {
                StartPersonalReplay(param1, index);  
            }
            case 1:
            {
                ResetReplayData(gA_ReplayInfo[param1][index], true);
                Shavit_PrintToChat(param1, "%T", "PersonalReplayDeleted", param1);
                ShowPersonaReplayMenu(param1);                
            }
        }
    }
    else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowPersonaReplayMenu(param1);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

public void ShowOptionMenu(int client)
{
    Menu menu = new Menu(Option_MenuHanlder);
    SetMenuTitle(menu, "%T\n ", "OptionMenuTitle", client);
    menu.ExitBackButton = true;
    
    char sMenu[64];

    FormatEx(sMenu, sizeof(sMenu), "[%T] %T\n ", gB_Enabled[client] ? "ItemEnabled":"ItemDisabled", client, "EnableFeature", client);
    menu.AddItem("enable", sMenu);    

    FormatEx(sMenu, sizeof(sMenu), "[%T] %T", gB_AutoOverWrite[client] ? "ItemEnabled":"ItemDisabled", client, "AutoOverwrite", client);
    menu.AddItem("overwrite", sMenu);

    FormatEx(sMenu, sizeof(sMenu), "[%T] %T", gB_PrintSavedMessage[client] ? "ItemEnabled":"ItemDisabled", client, "PrintSavedMessage", client);
    menu.AddItem("print", sMenu);

    menu.Display(client, MENU_TIME_FOREVER);
}

public int Option_MenuHanlder(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[16];
        menu.GetItem(param2, sInfo, 16);

        if(StrEqual(sInfo, "enable"))
        {
            gB_Enabled[param1] = !gB_Enabled[param1];
            SetClientCookieBool(param1, gH_Cookie_Enabled, gB_Enabled[param1]);
        }
        else if(StrEqual(sInfo, "overwrite"))
        {
            gB_AutoOverWrite[param1] = !gB_AutoOverWrite[param1];
            SetClientCookieBool(param1, gH_Cookie_AutoOverWrite, gB_AutoOverWrite[param1]);
        }
        else if(StrEqual(sInfo, "print"))
        {
            gB_PrintSavedMessage[param1] = !gB_PrintSavedMessage[param1];
            SetClientCookieBool(param1, gH_Cookie_PrintSavedMessage, gB_PrintSavedMessage[param1]);
        }

        ShowOptionMenu(param1);
    }
    else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowPersonaReplayMenu(param1);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

public void Shavit_OnFinish(int client)
{
    gI_PlayerFinishFrame[client] = Shavit_GetClientFrameCount(client);
}

public void Shavit_OnFinishStage(int client, int track, int style, int stage)
{
    if((!Shavit_IsOnlyStageMode(client) && stage > 1))
    {
        return;
    }

    gI_PlayerFinishFrame[client] = Shavit_GetClientFrameCount(client);
}


public Action Shavit_ShouldSaveReplayCopy(int client, int style, float time, int jumps, int strafes, float sync, int track, int stage, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong)
{
    if(!gB_Enabled[client])
    {
        return Plugin_Continue;
    }

    if(isbestreplay || istoolong || (!Shavit_IsOnlyStageMode(client) && stage > 1))
    {
        return Plugin_Continue;
    }

    int index = FindNextIndex(client);

    if(index == -1)
    {
        return Plugin_Continue;
    }

    ResetReplayData(gA_ReplayInfo[client][index], true);

    if(!SaveReplayData(client, index, style, time, track, stage, timestamp))
    {
        return Plugin_Continue;
    }

    gI_LastSavedIndex[client] = index;

    if(gB_PrintSavedMessage[client])
        Shavit_PrintToChat(client, "%T", "PersonalReplayCached", client, gS_ChatStrings.sVariable2, index+1, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

    return Plugin_Continue;
}

stock int FindNextIndex(int client)
{
    for(int i = 0; i < MAX_REPLAY; i++)
    {
        if (!gA_ReplayInfo[client][i].bHasReplay)
        {
            return i;
		}
    }

    if(!gB_AutoOverWrite[client])
    {
        return -1;
    }

    return FindEarliestIndex(client);        
}

stock int FindEarliestIndex(int client)
{
    int timestamp = gA_ReplayInfo[client][0].timestamp;
    int index = 0;

    for(int i = 1; i < MAX_REPLAY; i++)
    {
        if(gA_ReplayInfo[client][i].timestamp < timestamp)
        {
            timestamp = gA_ReplayInfo[client][i].timestamp;
            index = i;            
        }
    }

    return index;
}

public void StartPersonalReplay(int client, int index)
{
    int bot = Shavit_StartReplayFromFrameCache(
        gA_ReplayInfo[client][index].iStyle,
        gA_ReplayInfo[client][index].iTrack, 
        gA_ReplayInfo[client][index].iStage, 
        -1.0, 
        client, 
        -1, 
        Replay_Dynamic, 
        true, 
        gA_ReplayInfo[client][index].aCache, 
        sizeof(frame_cache_t));

    if(bot == 0)
    {
        Shavit_PrintToChat(client, "%T", "BotUnavailable", client);
        return;
    }
}

stock bool SaveReplayData(int client, int index, int style, float time, int track, int stage, int timestamp)
{
	gA_ReplayInfo[client][index].aCache.aFrames = Shavit_GetReplayData(client, false);

	if(!gA_ReplayInfo[client][index].aCache.aFrames)
	{
		return false;
	}

	gA_ReplayInfo[client][index].aCache.aFrameOffsets = Shavit_GetPlayerFrameOffsets(client, false);

	if(!gA_ReplayInfo[client][index].aCache.aFrameOffsets)
	{
		gA_ReplayInfo[client][index].aCache.aFrameOffsets = new ArrayList(sizeof(offset_info_t));
		gA_ReplayInfo[client][index].aCache.aFrameOffsets.Clear();
	}

	gA_ReplayInfo[client][index].bHasReplay = true;
	gA_ReplayInfo[client][index].iTrack = track;
	gA_ReplayInfo[client][index].iStage = stage;   
	gA_ReplayInfo[client][index].iStyle = style;
	gA_ReplayInfo[client][index].timestamp = timestamp;

	gA_ReplayInfo[client][index].aCache.fTime = time;
	gA_ReplayInfo[client][index].aCache.bNewFormat = true;
	gA_ReplayInfo[client][index].aCache.iPreFrames = Shavit_GetPlayerPreFrames(client);
	gA_ReplayInfo[client][index].aCache.iPostFrames = gA_ReplayInfo[client][index].aCache.aFrames.Length - gI_PlayerFinishFrame[client];
	gA_ReplayInfo[client][index].aCache.iFrameCount = gA_ReplayInfo[client][index].aCache.aFrames.Length - gA_ReplayInfo[client][index].aCache.iPreFrames - gA_ReplayInfo[client][index].aCache.iPostFrames;
	gA_ReplayInfo[client][index].aCache.fTickrate = (1.0 / GetTickInterval());
	gA_ReplayInfo[client][index].aCache.iSteamID = GetSteamAccountID(client);
	gA_ReplayInfo[client][index].aCache.iReplayVersion = REPLAY_FORMAT_SUBVERSION;

	char sName[MAX_NAME_LENGTH];
	FormatEx(sName, sizeof(sName), "%T%N", "PersonalReplay", client, client);

	strcopy(gA_ReplayInfo[client][index].aCache.sReplayName, MAX_NAME_LENGTH, sName);

	return true;
}

stock void ResetReplayData(replayinfo_t info, bool bDelete)
{
	info.bHasReplay = false;
	info.iTrack = -1;
	info.iStage = -1;   
	info.iStyle = -1;

	info.aCache.fTime = -1.0;
	info.aCache.iPreFrames = 0;
	info.aCache.iFrameCount = 0;
	info.aCache.fTickrate = 0.0;
	info.aCache.iSteamID = 0;

	if(bDelete)
	{
		delete info.aCache.aFrames;
		delete info.aCache.aFrameOffsets;
	}
	else
	{
		info.aCache.aFrames = null;
		info.aCache.aFrameOffsets = null;
	}
}

stock void SavePersistentData(int client)
{
	int iSteamID = GetSteamAccountID(client);
    
	if(iSteamID == 0)
	{
		return;
	}

	persistent_replaydata_t aData;
	aData.iSteamID = iSteamID;
	aData.iDisconnectTime = GetTime();

	aData.aReplayInfo = new ArrayList(sizeof(replayinfo_t));

	bool bSaved = false;
    
	for(int i = 0; i < MAX_REPLAY; i++)
	{
		if(gA_ReplayInfo[client][i].bHasReplay)
		{
			aData.aReplayInfo.PushArray(gA_ReplayInfo[client][i]);
			bSaved = true;
		}
	}

	if(!bSaved)
	{
		delete aData.aReplayInfo;
		return;
	}

	gA_PersisReplayInfo.PushArray(aData);
}

void LoadPersistentData(int client)
{
	if(client == 0 || GetSteamAccountID(client) == 0)
	{
		return;
	}

	persistent_replaydata_t aData;
	int iIndex = -1;
	int iSteamID;

	if((iSteamID = GetSteamAccountID(client)) != 0)
	{
		iIndex = gA_PersisReplayInfo.FindValue(iSteamID, 0);

		if (iIndex != -1)
		{
			gA_PersisReplayInfo.GetArray(iIndex, aData);
		}
	}

	if(iIndex == -1)
	{
		return;
	}

	gI_LastSavedIndex[client] = aData.iLastIndex;

	for(int i = 0; i < aData.aReplayInfo.Length; i++)
	{
		aData.aReplayInfo.GetArray(i, gA_ReplayInfo[client][i]);
	}

	DeletePersistentData(iIndex, aData, false);
}

void DeletePersistentData(int index, persistent_replaydata_t data, bool bDelete)
{
	gA_PersisReplayInfo.Erase(index);
    
	for (int i = 0; i < data.aReplayInfo.Length; i++)
	{
		replayinfo_t ReplayInfo;
		data.aReplayInfo.GetArray(i, ReplayInfo);
		ResetReplayData(ReplayInfo, bDelete);
	}
}

public Action Timer_PersistData(Handle timer)
{
	int time = GetTime();
	int iExpiredTime = gCV_PersistDataExpireTime.IntValue;

	if(iExpiredTime == -1 || iExpiredTime == 0)
	{
		return Plugin_Continue;
	}

	for (int i = 0; i < gA_PersisReplayInfo.Length; i++)
	{
		persistent_replaydata_t aData;
		gA_PersisReplayInfo.GetArray(i, aData);

		if(time - aData.iDisconnectTime > iExpiredTime)
		{
			DeletePersistentData(i, aData, true);
		}
	}

	return Plugin_Continue;
}

stock bool IsValidClient2(int client)
{
	return (client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsClientSourceTV(client));
}

stock void SetClientCookieBool(int client, Handle cookie, bool value)
{
	SetClientCookie(client, cookie, value ? "1" : "0");
}

stock bool GetClientCookieBool(int client, Handle cookie, bool& value)
{
	char buffer[8];
	GetClientCookie(client, cookie, buffer, sizeof(buffer));

	if (buffer[0] == '\0')
	{
		return false;
	}

	value = StringToInt(buffer) != 0;
	return true;
}