#include <sourcemod>
#include <convar_class>
#include <sdktools>
#include <shavit>
#include <shavit/core>
#include <shavit/replay-file>
#include <shavit/replay-stocks.sp>
#include <shavit/replay-recorder>
#include <shavit/rankings>

#undef REQUIRE_PLUGIN
#include <eventqueuefix>

#pragma newdecls required
#pragma semicolon 1

enum struct saveinfo_t
{
	bool bHasSave;
	float fTime;
	int iDate;
	int iStyle;
	char sMap[PLATFORM_MAX_PATH];
	int iStage;
}

enum struct mapsave_t
{
	char sMap[PLATFORM_MAX_PATH];
	int iSaveCount;
}

chatstrings_t gS_ChatStrings;
stylestrings_t gS_StyleStrings[STYLE_LIMIT];

float gF_Tickrate = 0.0;
int gI_StyleCount;
char gS_Map[PLATFORM_MAX_PATH];
char g_sBaseSaveFolder[PLATFORM_MAX_PATH];

int gI_SaveCount[MAXPLAYERS+1];

bool gB_HasCurrentMapSaves[MAXPLAYERS+1];
bool gB_Notified[MAXPLAYERS+1];

saveinfo_t gA_CurrentMapSaves[MAXPLAYERS+1][STYLE_LIMIT];
saveinfo_t gA_LastSelectedSave[MAXPLAYERS+1];

float gF_LastLoad[MAXPLAYERS+1][STYLE_LIMIT];

float empty_times[MAX_STAGES] = {-1.0, ...};
int empty_attempts[MAX_STAGES] = {0, ...};

ArrayList gA_ClientSaves[MAXPLAYERS+1];
StringMap gSM_ClientSavesIndex[MAXPLAYERS+1];

ConVar gCV_MaxPlayerSaves = null;
ConVar gCV_MinimumTimeAllowSave = null;
ConVar gCV_LoadSaveCoolDown = null;
ConVar gCV_StopTimerWarning = null;

bool gB_Late;
bool gB_Rankings = false;

public Plugin myinfo =
{
	name = "[shavit-surf] Savestate",
	author = "olivia, KikI",
	description = "Allow saving and loading savestates in shavit's surf timer",
	version = "1.0.0",
	url = "https://KawaiiClan.com https://github.com/bhopppp/Shavit-Surf-Timer"
}

public void OnPluginStart()
{
	gF_Tickrate = (1.0 / GetTickInterval());

	RegConsoleCmd("sm_savestate", Command_Savestate, "Save or load a timer state");
	RegConsoleCmd("sm_savestates", Command_Savestate, "Save or load a timer state");
	RegConsoleCmd("sm_savegame", Command_Savestate, "Save or load a timer state");
	RegConsoleCmd("sm_savetimer", Command_Savestate, "Save or load a timer state");
	RegConsoleCmd("sm_load", Command_Savestate, "Save or load a timer state");
	RegConsoleCmd("sm_loadgame", Command_Savestate, "Save or load a timer state");
	RegConsoleCmd("sm_loadtimer", Command_Savestate, "Save or load a timer state");

	LoadTranslations("shavit-savestate.phrases");
	
	gCV_MaxPlayerSaves = new Convar("shavit_savestate_maxplayersaves", "20", "Maximum saves can be saved for each client.\n0 - Disable feature", 0, true, 0.0, true, 100.0);
	gCV_MinimumTimeAllowSave = new Convar("shavit_savestate_mintimeallowsave", "30.0", "Minimum time (in seconds) allows player to save thier timer.", 0, true, 0.0, false, 60.0);
	gCV_LoadSaveCoolDown = new Convar("shavit_savestate_loadsavecooldown", "10.0", "Interval of time (in seconds) between player reading a save and the next save of the same slot", 0, true, 0.0, false, 0.0);
	Convar.AutoExecConfig();

	BuildPath(Path_SM, g_sBaseSaveFolder, sizeof(g_sBaseSaveFolder), "data/timersaves");

	if(!DirExists(g_sBaseSaveFolder) && !CreateDirectory(g_sBaseSaveFolder, 511))
	{
		SetFailState("Failed to create base savestate folder (%s). Check file permissions", g_sBaseSaveFolder);		
	}

	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientAuthorized(i, "");				
			}
		}

		Shavit_OnChatConfigLoaded();
		Shavit_OnStyleConfigLoaded(-1);
		GetLowercaseMapName(gS_Map);
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;
	return APLRes_Success;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}
}

public void OnConfigsExecuted()
{
	gCV_StopTimerWarning = FindConVar("shavit_misc_stoptimerwarning");
}


public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();		
	}

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i].sStyleName, sizeof(stylestrings_t::sStyleName));		
	}

	gI_StyleCount = styles;
}

public void OnMapStart()
{
	GetLowercaseMapName(gS_Map);
}

public void OnClientAuthorized(int client, const char[] auth)
{
	CacheSavedGame(client);
}

public void Shavit_OnStop(int client)
{
	if (Shavit_GetClientTrack(client) != Track_Main || Shavit_IsOnlyStageMode(client))
	{
		return;
	}

	if(Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), "segments"))
	{
		return;
	}

	gF_LastLoad[client][Shavit_GetBhopStyle(client)] = 0.0;		
}

public void Shavit_OnRestart(int client, int track)
{
	if (track != Track_Main || Shavit_IsOnlyStageMode(client))
	{
		return;
	}

	if(gB_HasCurrentMapSaves[client] && !gB_Notified[client])
	{
		Shavit_PrintToChat(client, "%T", "SaveReminder", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		gB_Notified[client] = true;
	}
	
	if(!Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), "segments"))
	{
		gF_LastLoad[client][Shavit_GetBhopStyle(client)] = 0.0;		
	}
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	if (track != Track_Main || Shavit_IsOnlyStageMode(client))
	{
		return;
	}

	// they have a checkpoint to load or just loaded a checkpoint, dont reset cooldown	
	if(Shavit_GetStyleSettingBool(oldstyle, "segments") || !manual)
	{
		return;
	}

	gF_LastLoad[client][oldstyle] = 0.0;
}


/**
 * * * * *
 * 
 * Cache
 * 
 * * * * *
 */

public void CacheSavedGame(int client)
{
	char sAuth[32];
	IntToString(GetSteamAccountID(client), sAuth, sizeof(sAuth));
	char sAuthFolder[PLATFORM_MAX_PATH];

	ResetSaveCache(client);

	gA_ClientSaves[client] = new ArrayList(sizeof(mapsave_t));
	gSM_ClientSavesIndex[client] = new StringMap();

	BuildPath(Path_SM, sAuthFolder, sizeof(sAuthFolder), "data/timersaves/%s", sAuth);

	if(!DirExists(sAuthFolder))
	{
		return;	// no save found
	}

	DirectoryListing mapsDir = OpenDirectory(sAuthFolder);
	if(mapsDir == null)
	{
		return;	// no save found
	}

	FileType type;
	char sMapFolder[PLATFORM_MAX_PATH];	// map name
	char sEntryPath[PLATFORM_MAX_PATH];

	while(ReadDirEntry(mapsDir, sMapFolder, sizeof(sMapFolder), type))
	{
		if(type != FileType_Directory)
		{
			continue;			
		}

		FormatEx(sEntryPath, sizeof(sEntryPath), "%s/%s", sAuthFolder, sMapFolder);
		DirectoryListing saveDir = OpenDirectory(sEntryPath);

		if(saveDir == null)
		{
			continue;	// no save inside this map
		}

		bool bCurrentMap = StrEqual(sMapFolder, gS_Map);

		int iMapSaveCount = 0;
		char sFile[PLATFORM_MAX_PATH];
		FileType type2;

		while(ReadDirEntry(saveDir, sFile, sizeof(sFile), type2))	// read into map directory
		{
			if(type2 != FileType_File)
			{
				continue;				
			}
			
			if(!HasSuffix(sFile, ".timer"))
			{
				continue;	// not a save file
			}

			char sStyleStr[16];
			strcopy(sStyleStr, sizeof(sStyleStr), sFile);

			ReplaceString(sStyleStr, sizeof(sStyleStr), ".timer", "");

			int iStyle = StringToInt(sStyleStr);
			if(iStyle < 0 || iStyle >= gI_StyleCount)
			{
				continue;	// invalid style
			}

			iMapSaveCount++;

			if (bCurrentMap)
			{
				char sPath[PLATFORM_MAX_PATH];
				FormatEx(sPath, sizeof(sPath), "%s/%s", sEntryPath, sFile);

				saveinfo_t info;
				LoadSaveInfo(sPath, info);

				gA_CurrentMapSaves[client][iStyle] = info;

				if(info.bHasSave)
				{
					gB_HasCurrentMapSaves[client] = true;					
				}
			}
		}

		if(iMapSaveCount > 0)
		{
			mapsave_t mapSave;
			mapSave.sMap = sMapFolder;
			mapSave.iSaveCount = iMapSaveCount;

			int index = gA_ClientSaves[client].PushArray(mapSave, sizeof(mapsave_t));
			gI_SaveCount[client] += iMapSaveCount;

			gSM_ClientSavesIndex[client].SetValue(sMapFolder, index);
		}

		CloseHandle(saveDir);
	}

	CloseHandle(mapsDir);
}

public void UpdateCacheOnDeleted(int client, int style, char[] sMap)
{
	gA_CurrentMapSaves[client][style].bHasSave = false;
	gA_CurrentMapSaves[client][style].fTime = 0.0;
	gA_CurrentMapSaves[client][style].iDate = 0;
	gI_SaveCount[client]--;

	int index;

	gSM_ClientSavesIndex[client].GetValue(sMap, index);
	mapsave_t mapSave;
	gA_ClientSaves[client].GetArray(index, mapSave, sizeof(mapsave_t));

	if(--mapSave.iSaveCount <= 0)
	{
		gSM_ClientSavesIndex[client].Remove(sMap);
	}

	gA_ClientSaves[client].SetArray(index, mapSave, sizeof(mapsave_t));
}

public void UpdateCacheOnSaved(int client, int style, float time, int stage, bool overwrite)
{
	if(!overwrite)
	{
		gI_SaveCount[client]++;

		int index;
		mapsave_t mapSave;
		
		if(!gSM_ClientSavesIndex[client].GetValue(gS_Map, index))
		{
			strcopy(mapSave.sMap, sizeof(mapsave_t::sMap), gS_Map);
			mapSave.iSaveCount = 1;

			index = gA_ClientSaves[client].PushArray(mapSave, sizeof(mapsave_t));
			gSM_ClientSavesIndex[client].SetValue(gS_Map, index);
		}
		else
		{
			gA_ClientSaves[client].GetArray(index, mapSave, sizeof(mapsave_t));
			mapSave.iSaveCount++;
		}

		gA_ClientSaves[client].SetArray(index, mapSave, sizeof(mapsave_t));
	}

	gA_CurrentMapSaves[client][style].bHasSave = true;
	gA_CurrentMapSaves[client][style].fTime = time;
	gA_CurrentMapSaves[client][style].iDate = GetTime();
	gA_CurrentMapSaves[client][style].iStyle = style;
	gA_CurrentMapSaves[client][style].iStage = stage;
	strcopy(gA_CurrentMapSaves[client][style].sMap, sizeof(saveinfo_t), gS_Map);
}

/**
 * * * * *
 * 
 * Commands
 * 
 * * * * *
 */


public Action Command_Savestate(int client, int args)
{
	if(IsValidClient(client))
	{
		char sCommand[16];
		GetCmdArg(0, sCommand, sizeof(sCommand));

		if(StrContains(sCommand, "load", false) != -1)
		{
			OpenLoadGameMenu(client);
		}
		else
		{
			OpenSavestateMenu(client);
		}
	}

	return Plugin_Handled;
}


/**
 * * * * *
 * 
 * Menus
 * 
 * * * * *
 */


void OpenSavestateMenu(int client)
{
	Menu menu = new Menu(MenuHandler_OpenSavestate);
	menu.SetTitle("%T\n ", "MenuTitleSavestates", client);

	char sDisplay[128];
	FormatEx(sDisplay, sizeof(sDisplay), "%T", "SaveCurrentTimer", client, gI_SaveCount[client], gCV_MaxPlayerSaves.IntValue);
	menu.AddItem("save", sDisplay, (Shavit_GetTimerStatus(client) == Timer_Stopped || Shavit_IsOnlyStageMode(client)) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	
	FormatEx(sDisplay, sizeof(sDisplay), "%s", "SaveCurrentCP", client, gI_SaveCount[client], gCV_MaxPlayerSaves.IntValue);
	menu.AddItem("save", sDisplay, (Shavit_GetTimerStatus(client) == Timer_Stopped || Shavit_IsOnlyStageMode(client)) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

	FormatEx(sDisplay, sizeof(sDisplay), "%T\n ", "LoadTimerSave", client, gI_SaveCount[client]);
	menu.AddItem("load", sDisplay);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "ViewAllSaves", client, gI_SaveCount[client]);
	menu.AddItem("view", sDisplay);

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_OpenSavestate(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		if(StrEqual(sInfo, "save"))
		{
			int iStyle = Shavit_GetBhopStyle(param1);

			if(gA_CurrentMapSaves[param1][iStyle].bHasSave)
			{
				OpenOverwriteSaveMenu(param1, iStyle);					
			}
			else if(gI_SaveCount[param1] >= gCV_MaxPlayerSaves.IntValue)
			{
				Shavit_PrintToChat(param1, "%T", "MaxSavesReached", param1, 
				gS_ChatStrings.sVariable, gCV_MaxPlayerSaves.IntValue, gS_ChatStrings.sText);
				OpenSavestateMenu(param1);
			}
			else
			{
				if(!SaveGame(param1, iStyle, false))
				{
					OpenSavestateMenu(param1);
				}
			}
		}
		else if(StrEqual(sInfo, "load"))
		{
			OpenLoadGameMenu(param1);
		}
		else if(StrEqual(sInfo, "view"))
		{
			OpenViewSavesMenu(param1);
		}
	}

	return 0;
}

public void OpenMapSaveMenu(int client, char[] sMap)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildSaveFolderPath(client, sMap, sPath, sizeof(sPath));

	Menu menu = new Menu(MenuHandler_OpenMapSaveMenu);

	char sFile[PLATFORM_MAX_PATH];
	FileType type;

	StringMap tiersMap = gB_Rankings ? Shavit_GetMapInfo() : null;

	DirectoryListing dir = OpenDirectory(sPath);
	while(ReadDirEntry(dir, sFile, sizeof(sFile), type))	// read into map directory
	{
		if(type != FileType_File)
		{
			continue;				
		}
		
		if(!HasSuffix(sFile, ".timer"))
		{
			continue;	// not a save file
		}

		char sStyleStr[16];
		strcopy(sStyleStr, sizeof(sStyleStr), sFile);

		ReplaceString(sStyleStr, sizeof(sStyleStr), ".timer", "");

		int iStyle = StringToInt(sStyleStr);
		if(iStyle < 0 || iStyle >= gI_StyleCount)
		{
			continue;	// invalid style
		}

		char sSavePath[PLATFORM_MAX_PATH];
		FormatEx(sSavePath, sizeof(sSavePath), "%s/%s", sPath, sFile);

		saveinfo_t info;
		LoadSaveInfo(sSavePath, info);

		char sMenuItem[128];
		char sDate[32];
		char sTime[32];
		char sInfo[PLATFORM_MAX_PATH];

		FloatToString(info.fTime, sTime, sizeof(sTime));
		FormatTime(sDate, sizeof(sDate), "%Y/%m/%d %H:%M", info.iDate);

		if(tiersMap && info.iStage > 0)
		{
			mapinfo_t mapinfo;
			tiersMap.GetArray(sMap, mapinfo, sizeof(mapinfo_t));

			FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", "SaveDisplayStaged", client, sDate, gS_StyleStrings[iStyle].sStyleName, FormatToSeconds(sTime), info.iStage, mapinfo.iStages);
		}
		else
		{
			FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", "SaveDisplayLinear", client, sDate, gS_StyleStrings[iStyle].sStyleName, FormatToSeconds(sTime));
		}

		FormatEx(sInfo, sizeof(sInfo), "%s;%d", sMap, iStyle);
		menu.AddItem(sInfo, sMenuItem);
	}

	delete tiersMap;

	menu.SetTitle("%T\n ", menu.ItemCount > 1 ? "MenuTitleMapSaveMultiple":"MenuTitleMapSaveSingle", client, menu.ItemCount, sMap);
	menu.ExitBackButton = true;

	CloseHandle(dir);

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_OpenMapSaveMenu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[PLATFORM_MAX_PATH];
		char sExploded[2][PLATFORM_MAX_PATH];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		ExplodeString(sInfo, ";", sExploded, 2, PLATFORM_MAX_PATH);

		int iStyle = StringToInt(sExploded[1]);

		OpenSaveManagementMenu(param1, iStyle, sExploded[0]);
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenViewSavesMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action OpenSaveManagementMenu(int client, int style, char[] sMap)
{
	Menu menu = new Menu(MenuHandler_SaveManagement);

	char sDisplay[128];
	char sTime[32];

	char sPath[PLATFORM_MAX_PATH];
	BuildStylePaths(client, style, sMap, sPath, sizeof(sPath), "", 0);

	saveinfo_t info;
	LoadSaveInfo(sPath, info);
	FloatToString(info.fTime, sTime, sizeof(sTime));

	StringMap maptiers = gB_Rankings ? Shavit_GetMapInfo() : null;

	if(maptiers && info.iStage > 0)
	{
		mapinfo_t mapinfo;
		maptiers.GetArray(sMap, mapinfo, sizeof(mapinfo_t));

		FormatEx(sDisplay, sizeof(sDisplay), "%T", "MenuTitleSaveManagementStaged", client, sMap, gS_StyleStrings[style].sStyleName, FormatToSeconds(sTime), info.iStage, mapinfo.iStages);		
	}
	else
	{
		FormatEx(sDisplay, sizeof(sDisplay), "%T", "MenuTitleSaveManagementLinear", client, sMap, gS_StyleStrings[style].sStyleName, FormatToSeconds(sTime));
	}

	delete maptiers;
	
	menu.SetTitle(sDisplay);

	gA_LastSelectedSave[client] = info;

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "LoadSave", client); 
	menu.AddItem("load", sDisplay, StrEqual(sMap, gS_Map) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "DeleteSave", client); 
	menu.AddItem("del", sDisplay);

	menu.ExitBackButton = true;
	menu.ExitButton = true;

	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_SaveManagement(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[PLATFORM_MAX_PATH];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		if(StrEqual(sInfo, "load"))
		{
			int iStyle = gA_LastSelectedSave[param1].iStyle;

			if(iStyle > -1 && iStyle <= gI_StyleCount && Shavit_HasStyleAccess(param1, iStyle))
			{
				if(!ShouldDisplayLoadWarning(param1))
				{
					if(!LoadGame(param1, gA_LastSelectedSave[param1].iStyle))
					{
						OpenSaveManagementMenu(param1, iStyle, gA_LastSelectedSave[param1].sMap);
					}
				}
				else
				{
					OpenLoadWarningMenu(param1, iStyle);
				}
			}
			else
			{
				Shavit_PrintToChat(param1, "%T", "InvalidStyle", param1);
				OpenSaveManagementMenu(param1, gA_LastSelectedSave[param1].iStyle, gA_LastSelectedSave[param1].sMap);
			}
		}
		else if(StrEqual(sInfo, "del"))
		{
			DeleteGame(param1, gA_LastSelectedSave[param1].sMap, gA_LastSelectedSave[param1].iStyle);
			Shavit_PrintToChat(param1, "%T", "SaveDeleted", param1,
			gS_ChatStrings.sVariable2, gA_LastSelectedSave[param1].sMap, gS_ChatStrings.sText,
			gS_ChatStrings.sStyle, gS_StyleStrings[gA_LastSelectedSave[param1].iStyle].sStyleName, gS_ChatStrings.sText);

			OpenMapSaveMenu(param1, gA_LastSelectedSave[param1].sMap);
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenMapSaveMenu(param1, gS_Map);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action OpenLoadWarningMenu(int client, int style)
{
	Menu menu = new Menu(MenuHandler_LoadWarning);

	char sDisplay[128];
	char sInfo[8];
	IntToString(style, sInfo, sizeof(sInfo));

	menu.SetTitle("%T\n ", "LoadTimerWarning", client);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "MenuItemYes", client);
	menu.AddItem(sInfo, sDisplay);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "MenuItemNo", client);
	menu.AddItem("No", sDisplay);

	menu.ExitBackButton = false;
	menu.ExitButton = false;

	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_LoadWarning(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		if(StrEqual(sInfo, "No"))
		{
			if(gA_LastSelectedSave[param1].bHasSave)
			{
				OpenSaveManagementMenu(param1, gA_LastSelectedSave[param1].iStyle, gA_LastSelectedSave[param1].sMap);
			}
			else
			{
				OpenLoadGameMenu(param1);				
			}

			return 0;
		}
		else
		{
			int style = StringToInt(sInfo);

			if(style > -1 && style <= gI_StyleCount && Shavit_HasStyleAccess(param1, style))
			{
				if(!LoadGame(param1, style))
				{
					OpenLoadWarningMenu(param1, style);
				}	
			}
			else
			{
				Shavit_PrintToChat(param1, "%T", "InvalidStyle", param1);
				OpenLoadWarningMenu(param1, style);
			}
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action OpenOverwriteSaveMenu(int client, int style)
{
	Menu menu = new Menu(MenuHandler_OverwriteSave);

	char sDisplay[128];
	char sTime[32];
	FloatToString(gA_CurrentMapSaves[client][style].fTime, sTime, sizeof(sTime));

	StringMap tiersMap = gB_Rankings ? Shavit_GetMapInfo() : null;

	if(tiersMap && gA_CurrentMapSaves[client][style].iStage > 0)
	{
		mapinfo_t mapinfo;
		tiersMap.GetArray(gS_Map, mapinfo, sizeof(mapinfo_t));

		FormatEx(sDisplay, sizeof(sDisplay), "%T", "MenuTitleOverwriteStaged", client, gS_Map, gS_StyleStrings[style].sStyleName, FormatToSeconds(sTime), gA_CurrentMapSaves[client][style].iStage, mapinfo.iStages);
	}
	else
	{
		FormatEx(sDisplay, sizeof(sDisplay), "%T", "MenuTitleOverwriteLinear", client, gS_Map, gS_StyleStrings[style].sStyleName, FormatToSeconds(sTime));
	}

	delete tiersMap;
	
	menu.SetTitle(sDisplay);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "MenuItemYes", client);
	menu.AddItem("Yes", sDisplay);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "MenuItemNo", client);
	menu.AddItem("No", sDisplay);

	menu.ExitBackButton = false;
	menu.ExitButton = false;

	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_OverwriteSave(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		if(StrEqual(sInfo, "Yes"))
		{
			if(!SaveGame(param1, Shavit_GetBhopStyle(param1), true))
			{
				OpenOverwriteSaveMenu(param1, Shavit_GetBhopStyle(param1));
			}
		}
		else if(StrEqual(sInfo, "No"))
		{
			OpenSavestateMenu(param1);
			return 0;
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenLoadGameMenu(int client)
{
	Menu menu = new Menu(MenuHandler_LoadGame);
	int[] iOrderedStyles = new int[gI_StyleCount];
	Shavit_GetOrderedStyles(iOrderedStyles, gI_StyleCount);
	int iStyle;
	char sStyleID[4];
	char sTime[32];
	char sDate[32];
	char sDisplay[128];

	saveinfo_t save;
	gA_LastSelectedSave[client] = save;

	FormatEx(sDisplay, sizeof(sDisplay), "%T\n ", "MenuTitleLoadSaves", client);
	menu.SetTitle(sDisplay);

	StringMap tiersMap = gB_Rankings ? Shavit_GetMapInfo() : null;

	for(int i = 0; i < gI_StyleCount; i++)
	{
		iStyle = iOrderedStyles[i];
		if(gA_CurrentMapSaves[client][iStyle].bHasSave)
		{
			IntToString(iStyle, sStyleID, sizeof(sStyleID));
			FloatToString(gA_CurrentMapSaves[client][iStyle].fTime, sTime, sizeof(sTime));
			FormatTime(sDate, sizeof(sDate), "%Y/%m/%d %H:%M", gA_CurrentMapSaves[client][iStyle].iDate);

			if(tiersMap && gA_CurrentMapSaves[client][iStyle].iStage > 0)
			{
				mapinfo_t mapinfo;
				tiersMap.GetArray(gS_Map, mapinfo, sizeof(mapinfo_t));

				FormatEx(sDisplay, sizeof(sDisplay), "%T\n ", "SaveDisplayStaged", 
				client, sDate, gS_StyleStrings[iStyle].sStyleName, FormatToSeconds(sTime), gA_CurrentMapSaves[client][iStyle].iStage, mapinfo.iStages);
			}
			else
			{
				FormatEx(sDisplay, sizeof(sDisplay), "%T\n ", "SaveDisplayLinear", client, sDate, gS_StyleStrings[iStyle].sStyleName, FormatToSeconds(sTime));
			}
			
			menu.AddItem(sStyleID, sDisplay);
		}
	}

	delete tiersMap;

	if(menu.ItemCount == 0)
	{
		FormatEx(sDisplay, sizeof(sDisplay), "%T", "NoSavesFound", client);
		menu.AddItem("", sDisplay);
	}

	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_LoadGame(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[4];
		menu.GetItem(param2, sInfo, sizeof(sInfo));
		int iStyle = StringToInt(sInfo);

		if(iStyle > -1 && iStyle <= gI_StyleCount && Shavit_HasStyleAccess(param1, iStyle))
		{
			if(!ShouldDisplayLoadWarning(param1))
			{
				if(!LoadGame(param1, iStyle))
				{
					OpenLoadGameMenu(param1);
				}
			}
			else
			{
				OpenLoadWarningMenu(param1, iStyle);
			}
		}
		else
		{
			Shavit_PrintToChat(param1, "%T", "InvalidStyle", param1);
			OpenLoadGameMenu(param1);
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenSavestateMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenViewSavesMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ViewSaves);
	menu.SetTitle("%T\n ", "MenuTitleSavedGames", client, gI_SaveCount[client], gCV_MaxPlayerSaves.IntValue);
	char sDisplay[128];

	for (int i = 0; i < gA_ClientSaves[client].Length; i++)
	{
		mapsave_t mapSave;
		gA_ClientSaves[client].GetArray(i, mapSave, sizeof(mapsave_t));

		if(mapSave.iSaveCount <= 0)
		{
			continue;
		}

		FormatEx(sDisplay, sizeof(sDisplay), "%T", mapSave.iSaveCount == 1 ? "MapSaveDisplaySingle":"MapSaveDisplayMutiple", client, mapSave.sMap, mapSave.iSaveCount);
		menu.AddItem(mapSave.sMap, sDisplay);
	}

	if(menu.ItemCount == 0)
	{
		FormatEx(sDisplay, sizeof(sDisplay), "%T", "NoSavesFound", client);
		menu.AddItem("", sDisplay, ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ViewSaves(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sMap[PLATFORM_MAX_PATH];
		menu.GetItem(param2, sMap, sizeof(sMap));

		OpenMapSaveMenu(param1, sMap);
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenSavestateMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

/**
 * * * * *
 * 
 * Core functions - Save / Load / Delete
 * 
 * * * * *
 */


bool SaveGame(int client, int style, bool bOverwrite)
{
	if(Shavit_IsOnlyStageMode(client) || Shavit_GetClientTrack(client) != Track_Main)
	{
		Shavit_PrintToChat(client, "%T", "OnlyMainTrack", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		return false;
	}

	if(Shavit_IsPracticeMode(client))
	{
		Shavit_PrintToChat(client, "%T", "SaveTimerPractice", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return false;
	}

	int iFlags = Shavit_CanPause(client);

	if((iFlags > 0 && !Shavit_IsPaused(client)))
	{	
		if((iFlags & CPR_NoTimer) > 0 || (iFlags & CPR_InStartZone) > 0)
		{
			Shavit_PrintToChat(client, "%T", "SaveTimerNotRunning", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		}
		else
		{
			Shavit_PrintToChat(client, "%T", "SaveTimerMoving", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		}

		return false;
	}

	if(style != Shavit_GetBhopStyle(client))
	{
		return false;
	}

	if(Shavit_GetClientTime(client) < gCV_MinimumTimeAllowSave.FloatValue)
	{
		Shavit_PrintToChat(client, "%T", "SaveTimerShortDuration", client, gS_ChatStrings.sVariable, gCV_MinimumTimeAllowSave.FloatValue, gS_ChatStrings.sText);

		return false;
	}

	float cooldown = gF_LastLoad[client][style] + gCV_LoadSaveCoolDown.FloatValue - GetEngineTime();

	if(cooldown > 0.0)
	{
		Shavit_PrintToChat(client, "%T", "SaveTimerTooSoon", client, gS_ChatStrings.sVariable2, cooldown, gS_ChatStrings.sText);

		return false;
	}

	if(Shavit_GetTimerStatus(client) == Timer_Paused)
	{
		Shavit_ResumeTimer(client, true);		
	}

	cp_cache_t cpcache;

	Shavit_SaveCheckpointCache(client, client, cpcache, -1, sizeof(cp_cache_t));
	cpcache.iPreFrames = Shavit_GetPlayerPreFrames(client); //this is needed until https://github.com/shavitush/bhoptimer/pull/1244 is addressed, but might only be used if we save a replay, idk. i'll leave it here to be safe
	cpcache.iStageStartFrames = Shavit_GetStageStartFrames(client);
	cpcache.iStageReachFrames = Shavit_GetStageReachFrames(client);
	
	cpcache.aFrames = Shavit_GetReplayData(client);
	cpcache.aFrameOffsets = Shavit_GetPlayerFrameOffsets(client, false);
	cpcache.iPreFrames = Shavit_GetPlayerPreFrames(client);

	char sTimerPath[PLATFORM_MAX_PATH];
	char sReplayPath[PLATFORM_MAX_PATH];
	BuildStylePaths(client, cpcache.aSnapshot.bsStyle, gS_Map, sTimerPath, sizeof(sTimerPath), sReplayPath, sizeof(sReplayPath));

	if(!WriteReplayData(client, sReplayPath, cpcache, Shavit_GetClientFrameCount(client)))
	{
		DeleteCheckpointCache(cpcache);
		Shavit_PrintToChat(client, "%T", "SaveReplayError", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		
		return false;
	}
	
	if(!WriteTimerData(sTimerPath, cpcache))
	{
		DeleteCheckpointCache(cpcache);
		Shavit_PrintToChat(client, "%T", "SaveFileError", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return false;
	}

	Shavit_StopTimer(client, true);

	UpdateCacheOnSaved(client, style, cpcache.aSnapshot.fCurrentTime, cpcache.aSnapshot.iStageAttempts[cpcache.aSnapshot.iLastStage] > 0 ? cpcache.aSnapshot.iLastStage:-1, bOverwrite);

	DeleteCheckpointCache(cpcache);
	Shavit_PrintToChat(client, "%T", "TimerSaved", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

	return true;
}

bool LoadGame(int client, int style)
{
	if(!IsValidClient(client) || !gA_CurrentMapSaves[client][style].bHasSave)
	{
		return false;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "LoadTimerAlive", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		return false;
	}

	char sTimerPath[PLATFORM_MAX_PATH];
	char sReplayPath[PLATFORM_MAX_PATH];
	BuildStylePaths(client, style, gS_Map, sTimerPath, sizeof(sTimerPath), sReplayPath, sizeof(sReplayPath));

	cp_cache_t cpcache;

	cpcache.iSteamID = GetSteamAccountID(client);

	int real;
	if(!LoadTimerData(sTimerPath, cpcache, real))
	{
		DeleteCheckpointCache(cpcache);
		Shavit_PrintToChat(client, "%T", "LoadFileError", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return false;
	}
	
	if(!LoadReplayData(sReplayPath, real, cpcache))
	{
		DeleteCheckpointCache(cpcache);
		Shavit_PrintToChat(client, "%T", "LoadReplayError", gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		
		return false;
	}

	Shavit_ClearCheckpoints(client);
	Shavit_StopTimer(client, true);

	Shavit_SetTriggerDisable(client, false);
	Shavit_LoadCheckpointCache(client, cpcache, -1, sizeof(cp_cache_t), true);

	if(Shavit_GetTimerStatus(client) == Timer_Paused)
	{
		Shavit_ResumeTimer(client);		
	}

	if(Shavit_GetStyleSettingBool(style, "kzcheckpoints") || Shavit_GetStyleSettingBool(style, "segments"))
	{
		Shavit_SaveCheckpoint(client);		
	}

	Shavit_HijackAngles(client, cpcache.fAngles[0], cpcache.fAngles[1], -1, true);

	DeleteGame(client, gS_Map, style);
	DeleteCheckpointCache(cpcache);

	gF_LastLoad[client][style] = GetEngineTime();

	Shavit_PrintToChat(client, "%T", "TimerLoaded", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

	return true;
}

void DeleteGame(int client, char[] sMap, int iStyle)
{
	char sTimerPath[PLATFORM_MAX_PATH];
	char sReplayPath[PLATFORM_MAX_PATH];
	BuildStylePaths(client, iStyle, gS_Map, sTimerPath, sizeof(sTimerPath), sReplayPath, sizeof(sReplayPath));

	if(FileExists(sReplayPath))
	{	// delete replay file
		DeleteFile(sReplayPath);		
	}

	if(FileExists(sTimerPath))
	{	// delete timer file
		DeleteFile(sTimerPath);		
	}

	char sMapFolder[PLATFORM_MAX_PATH];
	BuildSaveFolderPath(client, sMap, sMapFolder, sizeof(sMapFolder));

	if(IsDirectoryEmpty(sMapFolder))	// if map folder becomes empty, remove it; if auth folder then also empty, remove it too
	{
		RemoveDir(sMapFolder);

		char sAuthFolder[PLATFORM_MAX_PATH];
		BuildAuthFolderPath(client, sAuthFolder, sizeof(sAuthFolder));

		if(IsDirectoryEmpty(sAuthFolder))
		{
			RemoveDir(sAuthFolder);
		}
	}

	UpdateCacheOnDeleted(client, iStyle, gS_Map);
}

/**
 * * * * * * *
 * 
 * stocks
 * 
 * * * * * * *
 */

stock char[] FormatToSeconds(char time[32])
{
	int iTemp = RoundToFloor(StringToFloat(time));
	int iHours = 0;

	if(iTemp > 3600)
	{
		iHours = iTemp / 3600;
		iTemp %= 3600;
	}

	int iMinutes = 0;

	if(iTemp >= 60)
	{
		iMinutes = iTemp / 60;
		iTemp %= 60;
	}

	float fSeconds = iTemp + StringToFloat(time) - RoundToFloor(StringToFloat(time));

	char result[32];

	if (iHours > 0)
	{
		Format(result, sizeof(result), "%ih %im %.1fs", iHours, iMinutes, fSeconds);
	}
	else if(iMinutes > 0)
	{
		Format(result, sizeof(result), "%im %.1fs", iMinutes, fSeconds);
	}
	else
	{
		Format(result, sizeof(result), "%.1fs", fSeconds);
	}

	return result;
}

stock bool WriteReplayData(int client, char[] sPath, cp_cache_t cache, int iSize)
{
	File fFile = OpenFile(sPath, "wb+");

	if(fFile == null)
	{
		LogError("Failed to open savegame replay file (%s).", sPath);

		return false;
	}

	WriteReplayHeader(fFile, cache.aSnapshot.bsStyle, cache.aSnapshot.iTimerTrack, 0, cache.aSnapshot.fCurrentTime, GetSteamAccountID(client), cache.iPreFrames, 0, cache.aSnapshot.fZoneOffset, iSize, gF_Tickrate, gS_Map, cache.aFrameOffsets);
	WriteReplayFrames(cache.aFrames, iSize, fFile, null);

	delete cache.aFrames;
	delete fFile;

	return true;
}

stock bool WriteTimerData(char[] sPath, cp_cache_t cache)
{
	// write KeyValues
	KeyValues kv = new KeyValues("savestate");
	kv.JumpToKey("meta", true);
	kv.SetNum("date", GetTime());
	kv.SetNum("auth", cache.iSteamID);
	kv.SetString("map", gS_Map);
	kv.SetNum("style", cache.aSnapshot.bsStyle);
	kv.SetNum("stage", cache.aSnapshot.iStageAttempts[cache.aSnapshot.iLastStage] >= 1 ? cache.aSnapshot.iLastStage:-1);
	kv.SetFloat("TfCurrentTime", cache.aSnapshot.fCurrentTime);
	kv.GoBack();

	kv.JumpToKey("snapshot", true);
	kv.SetNum("TbTimerEnabled", view_as<int>(cache.aSnapshot.bTimerEnabled));
	kv.SetNum("TbClientPaused", view_as<int>(cache.aSnapshot.bClientPaused));
	kv.SetNum("TiStyle", cache.aSnapshot.bsStyle);
	kv.SetNum("TiJumps", cache.aSnapshot.iJumps);
	kv.SetNum("TiStrafes", cache.aSnapshot.iStrafes);
	kv.SetNum("TiTotalMeasures", cache.aSnapshot.iTotalMeasures);
	kv.SetNum("TiGoodGains", cache.aSnapshot.iGoodGains);
	kv.SetFloat("TfServerTime", cache.aSnapshot.fServerTime);
	kv.SetNum("TiKeyCombo", cache.aSnapshot.iKeyCombo);
	kv.SetNum("TiTimerTrack", cache.aSnapshot.iTimerTrack);
	kv.SetNum("TiMeasuredJumps", cache.aSnapshot.iMeasuredJumps);
	kv.SetNum("TiPerfectJumps", cache.aSnapshot.iPerfectJumps);
	kv.SetNum("TiLastStage", cache.aSnapshot.iLastStage);
	kv.SetFloat("TfZoneOffset1", cache.aSnapshot.fZoneOffset[0]);
	kv.SetFloat("TfZoneOffset2", cache.aSnapshot.fZoneOffset[1]);
	kv.SetFloat("TfDistanceOffset1", cache.aSnapshot.fDistanceOffset[0]);
	kv.SetFloat("TfDistanceOffset2", cache.aSnapshot.fDistanceOffset[1]);
	kv.SetFloat("TfAvgVelocity", cache.aSnapshot.fAvgVelocity);
	kv.SetFloat("TfMaxVelocity", cache.aSnapshot.fMaxVelocity);
	kv.SetFloat("TfTimescale", cache.aSnapshot.fTimescale);
	kv.SetNum("TiZoneIncrement", cache.aSnapshot.iZoneIncrement);
	kv.SetNum("TiFullTicks", cache.aSnapshot.iFullTicks);
	kv.SetNum("TiFractionalTicks", cache.aSnapshot.iFractionalTicks);
	kv.SetNum("TbPracticeMode", view_as<int>(cache.aSnapshot.bPracticeMode));
	kv.SetNum("TbOnlyStageMode", view_as<int>(cache.aSnapshot.bOnlyStageMode));
	kv.SetNum("TbStageTimeValid", view_as<int>(cache.aSnapshot.bStageTimeValid));
	kv.SetNum("TbJumped", view_as<int>(cache.aSnapshot.bJumped));
	kv.SetNum("TbCanUseAllKeys", view_as<int>(cache.aSnapshot.bCanUseAllKeys));
	kv.SetNum("TbOnGround", view_as<int>(cache.aSnapshot.bOnGround));
	kv.SetNum("TiLastButtons", cache.aSnapshot.iLastButtons);
	kv.SetFloat("TfLastAngle", cache.aSnapshot.fLastAngle);
	kv.SetNum("TiLandingTick", cache.aSnapshot.iLandingTick);
	kv.SetNum("TiLastMoveType", view_as<int>(cache.aSnapshot.iLastMoveType));
	kv.SetFloat("TfStrafeWarning", cache.aSnapshot.fStrafeWarning);
	kv.SetFloat("TfLastInputVel1", cache.aSnapshot.fLastInputVel[0]);
	kv.SetFloat("TfLastInputVel2", cache.aSnapshot.fLastInputVel[1]);
	kv.SetFloat("Tfplayer_speedmod", cache.aSnapshot.fplayer_speedmod);
	kv.SetFloat("TfNextFrameTime", cache.aSnapshot.fNextFrameTime);
	kv.SetNum("TiLastMoveTypeTAS", view_as<int>(cache.aSnapshot.iLastMoveTypeTAS));

	// stage start info
	kv.JumpToKey("stagestart", true);
	kv.SetFloat("TfStageStartTime", cache.aSnapshot.aStageStartInfo.fStageStartTime);
	kv.SetNum("TiFullTicks", cache.aSnapshot.aStageStartInfo.iFullTicks);
	kv.SetNum("TiFractionalTicks", cache.aSnapshot.aStageStartInfo.iFractionalTicks);
	kv.SetNum("TiZoneIncrement", cache.aSnapshot.aStageStartInfo.iZoneIncrement);
	kv.SetNum("TiJumps", cache.aSnapshot.aStageStartInfo.iJumps);
	kv.SetNum("TiStrafes", cache.aSnapshot.aStageStartInfo.iStrafes);
	kv.SetNum("TiTotalMeasures", cache.aSnapshot.aStageStartInfo.iTotalMeasures);
	kv.SetNum("TiGoodGains", cache.aSnapshot.aStageStartInfo.iGoodGains);

	kv.SetFloat("TfZoneOffset1", cache.aSnapshot.aStageStartInfo.fZoneOffset[0]);
	kv.SetFloat("TfZoneOffset2", cache.aSnapshot.aStageStartInfo.fZoneOffset[1]);
	kv.SetFloat("TfDistanceOffset1", cache.aSnapshot.aStageStartInfo.fDistanceOffset[0]);
	kv.SetFloat("TfDistanceOffset2", cache.aSnapshot.aStageStartInfo.fDistanceOffset[1]);
	kv.SetFloat("TfStartVelocity", cache.aSnapshot.aStageStartInfo.fStartVelocity);
	kv.SetFloat("TfAvgVelocity", cache.aSnapshot.aStageStartInfo.fAvgVelocity);
	kv.SetFloat("TfMaxVelocity", cache.aSnapshot.aStageStartInfo.fMaxVelocity);
	kv.GoBack();

	// arrays
	kv.JumpToKey("CPTimes", true);
	for(int i = 0; i < cache.aSnapshot.iLastStage + 1; i++)
	{
		char idx[8]; 
		IntToString(i, idx, sizeof(idx));

		kv.SetFloat(idx, cache.aSnapshot.fCPTimes[i]);
	}
	kv.GoBack();
	kv.JumpToKey("StageFinishTimes", true);
	for(int i = 0; i < cache.aSnapshot.iLastStage + 1; i++)
	{
		char idx[8]; 
		IntToString(i, idx, sizeof(idx));

		kv.SetFloat(idx, cache.aSnapshot.fStageFinishTimes[i]);
	}
	kv.GoBack();
	kv.JumpToKey("StageAttempts", true);
	for(int i = 0; i <= cache.aSnapshot.iLastStage + 1; i++)
	{
		char idx[8]; 
		IntToString(i, idx, sizeof(idx));

		kv.SetNum(idx, cache.aSnapshot.iStageAttempts[i]);
	}
	kv.GoBack();
	kv.GoBack();

	kv.JumpToKey("replay", true);
	offset_info_t offset;
	cache.aFrameOffsets.GetArray(0, offset, sizeof(offset_info_t));
	kv.SetNum("RiRealFrameCount", offset.iFrameOffset);
	kv.SetNum("RiStageStartFrames", cache.iStageStartFrames);
	kv.SetNum("RiStageReachFrames", cache.iStageReachFrames);
	kv.GoBack();

	kv.JumpToKey("player", true);
	kv.SetFloat("CfPosition1", cache.fPosition[0]);
	kv.SetFloat("CfPosition2", cache.fPosition[1]);
	kv.SetFloat("CfPosition3", cache.fPosition[2]);
	kv.SetFloat("CfAngles1", cache.fAngles[0]);
	kv.SetFloat("CfAngles2", cache.fAngles[1]);
	kv.SetFloat("CfAngles3", cache.fAngles[2]);
	kv.SetFloat("CfVelocity1", cache.fVelocity[0]);
	kv.SetFloat("CfVelocity2", cache.fVelocity[1]);
	kv.SetFloat("CfVelocity3", cache.fVelocity[2]);
	kv.SetNum("CiMovetype", view_as<int>(cache.iMoveType));
	kv.SetFloat("CfGravity", cache.fGravity);
	kv.SetFloat("CfSpeed", cache.fSpeed);
	kv.SetFloat("CfStamina", cache.fStamina);
	kv.SetNum("CbDucked", view_as<int>(cache.bDucked));
	kv.SetNum("CbDucking", view_as<int>(cache.bDucking));
	kv.SetFloat("CfDuckTime", cache.fDucktime);
	kv.SetFloat("CfDuckSpeed", cache.fDuckSpeed);
	kv.SetNum("CiFlags", cache.iFlags);
	kv.SetString("CsTargetname", cache.sTargetname);
	kv.SetString("CsClassname", cache.sClassname);
	kv.SetNum("CiPreFrames", cache.iPreFrames);
	kv.SetNum("CiStageStartFrames", cache.iStageStartFrames);
	kv.SetNum("CbSegmented", view_as<int>(cache.bSegmented));
	kv.SetNum("CiGroundEntity", cache.iGroundEntity);
	kv.SetFloat("CvecLadderNormal1", cache.vecLadderNormal[0]);
	kv.SetFloat("CvecLadderNormal2", cache.vecLadderNormal[1]);
	kv.SetFloat("CvecLadderNormal3", cache.vecLadderNormal[2]);
	kv.SetNum("Cm_bHasWalkMovedSinceLastJump", view_as<int>(cache.m_bHasWalkMovedSinceLastJump));
	kv.SetFloat("Cm_ignoreLadderJumpTime", cache.m_ignoreLadderJumpTime);
	kv.SetFloat("Cm_lastStandingPos1", cache.m_lastStandingPos[0]);
	kv.SetFloat("Cm_lastStandingPos2", cache.m_lastStandingPos[1]);
	kv.SetFloat("Cm_lastStandingPos3", cache.m_lastStandingPos[2]);
	kv.SetFloat("Cm_ladderSuppressionTimer1", cache.m_ladderSurpressionTimer[0]);
	kv.SetFloat("Cm_ladderSuppressionTimer2", cache.m_ladderSurpressionTimer[1]);
	kv.SetFloat("Cm_lastLadderNormal1", cache.m_lastLadderNormal[0]);
	kv.SetFloat("Cm_lastLadderNormal2", cache.m_lastLadderNormal[1]);
	kv.SetFloat("Cm_lastLadderNormal3", cache.m_lastLadderNormal[2]);
	kv.SetFloat("Cm_lastLadderPos1", cache.m_lastLadderPos[0]);
	kv.SetFloat("Cm_lastLadderPos2", cache.m_lastLadderPos[1]);
	kv.SetFloat("Cm_lastLadderPos3", cache.m_lastLadderPos[2]);
	kv.SetNum("Cm_afButtonDisabled", cache.m_afButtonDisabled);
	kv.SetNum("Cm_afButtonForced", cache.m_afButtonForced);
	kv.GoBack();

	if(cache.aEvents != null)
	{
		kv.JumpToKey("events", true);
		for(int i = 0; i < cache.aEvents.Length; i++)
		{
			event_t e;
			cache.aEvents.GetArray(i, e);
			char sKey[16];
			FormatEx(sKey, sizeof(sKey), "e%i", i);
			kv.JumpToKey(sKey, true);
			kv.SetString("Etarget", e.target);
			kv.SetString("EtargetInput", e.targetInput);
			kv.SetString("EvariantValue", e.variantValue);
			kv.SetFloat("Edelay", e.delay);
			kv.SetNum("Eactivator", e.activator);
			kv.SetNum("Ecaller", e.caller);
			kv.SetNum("EoutputID", e.outputID);
			kv.GoBack();
		}
		kv.GoBack();
	}

	if(cache.aOutputWaits != null)
	{
		kv.JumpToKey("outputwaits", true);
		for(int i = 0; i < cache.aOutputWaits.Length; i++)
		{
			entity_t e;
			cache.aOutputWaits.GetArray(i, e);
			char sKey[16];
			FormatEx(sKey, sizeof(sKey), "o%i", i);
			kv.JumpToKey(sKey, true);
			kv.SetNum("Ecaller", e.caller);
			kv.SetFloat("EwaitTime", e.waitTime);
			kv.GoBack();
		}
		kv.GoBack();
	}

	if(cache.customdata != null)
	{
		kv.JumpToKey("customdata", true);
		float fPunishTime;
		int iLastBlock;
		if(cache.customdata.ContainsKey("mpbhops_punishtime"))
			cache.customdata.GetValue("mpbhops_punishtime", fPunishTime);
		if(cache.customdata.ContainsKey("mpbhops_lastblock"))
			cache.customdata.GetValue("mpbhops_lastblock", iLastBlock);
		kv.SetFloat("mpbhops_punishtime", fPunishTime);
		kv.SetNum("mpbhops_lastblock", iLastBlock);
		kv.GoBack();
	}

	if(!kv.ExportToFile(sPath))
	{
		LogError("Failed to write savestate KV file: %s", sPath);
		delete kv;

		return false;
	}

	delete kv;

	return true;
}

stock bool LoadTimerData(char[] sPath, cp_cache_t cache, int& iRealFrameCount)
{
	KeyValues kv = new KeyValues("savestate");
	if(!kv.ImportFromFile(sPath))
	{
		delete kv;
		return false;
	}

	if(kv.JumpToKey("snapshot", false))
	{
		cache.aSnapshot.bTimerEnabled = view_as<bool>(kv.GetNum("TbTimerEnabled", 0));
		cache.aSnapshot.bsStyle = kv.GetNum("TiStyle", 0);
		cache.aSnapshot.fCurrentTime = kv.GetFloat("TfCurrentTime", 0.0);
		cache.aSnapshot.bClientPaused = view_as<bool>(kv.GetNum("TbClientPaused", 0));
		cache.aSnapshot.iJumps = kv.GetNum("TiJumps", 0);
		cache.aSnapshot.iStrafes = kv.GetNum("TiStrafes", 0);
		cache.aSnapshot.iTotalMeasures = kv.GetNum("TiTotalMeasures", 0);
		cache.aSnapshot.iGoodGains = kv.GetNum("TiGoodGains", 0);
		cache.aSnapshot.fServerTime = kv.GetFloat("TfServerTime", 0.0);
		cache.aSnapshot.iKeyCombo = kv.GetNum("TiKeyCombo", 0);
		cache.aSnapshot.iTimerTrack = kv.GetNum("TiTimerTrack", 0);
		cache.aSnapshot.iLastStage = kv.GetNum("TiLastStage", 0);
		cache.aSnapshot.iMeasuredJumps = kv.GetNum("TiMeasuredJumps", 0);
		cache.aSnapshot.iPerfectJumps = kv.GetNum("TiPerfectJumps", 0);
		cache.aSnapshot.fZoneOffset[0] = kv.GetFloat("TfZoneOffset1", 0.0);
		cache.aSnapshot.fZoneOffset[1] = kv.GetFloat("TfZoneOffset2", 0.0);
		cache.aSnapshot.fDistanceOffset[0] = kv.GetFloat("TfDistanceOffset1", 0.0);
		cache.aSnapshot.fDistanceOffset[1] = kv.GetFloat("TfDistanceOffset2", 0.0);
		cache.aSnapshot.fAvgVelocity = kv.GetFloat("TfAvgVelocity", 0.0);
		cache.aSnapshot.fMaxVelocity = kv.GetFloat("TfMaxVelocity", 0.0);
		cache.aSnapshot.fTimescale = kv.GetFloat("TfTimescale", 1.0);
		cache.aSnapshot.iZoneIncrement = kv.GetNum("TiZoneIncrement", 0);
		cache.aSnapshot.iFullTicks = kv.GetNum("TiFullTicks", 0);
		cache.aSnapshot.iFractionalTicks = kv.GetNum("TiFractionalTicks", 0);
		cache.aSnapshot.bPracticeMode = view_as<bool>(kv.GetNum("TbPracticeMode", 0));
		cache.aSnapshot.bOnlyStageMode = view_as<bool>(kv.GetNum("TbOnlyStageMode", 0));
		cache.aSnapshot.bStageTimeValid = view_as<bool>(kv.GetNum("TbStageTimeValid", 1));
		cache.aSnapshot.bJumped = view_as<bool>(kv.GetNum("TbJumped", 0));
		cache.aSnapshot.bCanUseAllKeys = view_as<bool>(kv.GetNum("TbCanUseAllKeys", 1));
		cache.aSnapshot.bOnGround = view_as<bool>(kv.GetNum("TbOnGround", 1));
		cache.aSnapshot.iLastButtons = kv.GetNum("TiLastButtons", 0);
		cache.aSnapshot.fLastAngle = kv.GetFloat("TfLastAngle", 0.0);
		cache.aSnapshot.iLandingTick = kv.GetNum("TiLandingTick", 0);
		cache.aSnapshot.iLastMoveType = view_as<MoveType>(kv.GetNum("TiLastMoveType", 0));
		cache.aSnapshot.fStrafeWarning = kv.GetFloat("TfStrafeWarning", 0.0);
		cache.aSnapshot.fLastInputVel[0] = kv.GetFloat("TfLastInputVel1", 0.0);
		cache.aSnapshot.fLastInputVel[1] = kv.GetFloat("TfLastInputVel2", 0.0);
		cache.aSnapshot.fplayer_speedmod = kv.GetFloat("Tfplayer_speedmod", 0.0);
		cache.aSnapshot.fNextFrameTime = kv.GetFloat("TfNextFrameTime", 0.0);
		cache.aSnapshot.iLastMoveTypeTAS = view_as<MoveType>(kv.GetNum("TiLastMoveTypeTAS", 0));

		// stage start info
		if(kv.JumpToKey("stagestart", false))
		{
			cache.aSnapshot.aStageStartInfo.fStageStartTime = kv.GetFloat("TfStageStartTime", cache.aSnapshot.fCurrentTime);
			cache.aSnapshot.aStageStartInfo.iFullTicks = kv.GetNum("TiFullTicks", cache.aSnapshot.iFullTicks);
			cache.aSnapshot.aStageStartInfo.iFractionalTicks = kv.GetNum("TiFractionalTicks", cache.aSnapshot.iFractionalTicks);
			cache.aSnapshot.aStageStartInfo.iZoneIncrement = kv.GetNum("TiZoneIncrement", cache.aSnapshot.iZoneIncrement);
			cache.aSnapshot.aStageStartInfo.iJumps = kv.GetNum("TiJumps", cache.aSnapshot.iJumps);
			cache.aSnapshot.aStageStartInfo.iStrafes = kv.GetNum("TiStrafes", cache.aSnapshot.iStrafes);
			cache.aSnapshot.aStageStartInfo.iTotalMeasures = kv.GetNum("TiTotalMeasures", cache.aSnapshot.iTotalMeasures);
			cache.aSnapshot.aStageStartInfo.iGoodGains = kv.GetNum("TiGoodGains", cache.aSnapshot.iGoodGains);

			cache.aSnapshot.aStageStartInfo.fZoneOffset[0] = kv.GetFloat("TfZoneOffset1", cache.aSnapshot.fZoneOffset[0]);
			cache.aSnapshot.aStageStartInfo.fZoneOffset[1] = kv.GetFloat("TfZoneOffset2", cache.aSnapshot.fZoneOffset[1]);
			cache.aSnapshot.aStageStartInfo.fDistanceOffset[0] = kv.GetFloat("TfDistanceOffset1", cache.aSnapshot.fDistanceOffset[0]);
			cache.aSnapshot.aStageStartInfo.fDistanceOffset[1] = kv.GetFloat("TfDistanceOffset2", cache.aSnapshot.fDistanceOffset[1]);
			cache.aSnapshot.aStageStartInfo.fStartVelocity = kv.GetFloat("TfStartVelocity", 0.0);
			cache.aSnapshot.aStageStartInfo.fAvgVelocity = kv.GetFloat("TfAvgVelocity", cache.aSnapshot.fAvgVelocity);
			cache.aSnapshot.aStageStartInfo.fMaxVelocity = kv.GetFloat("TfMaxVelocity", cache.aSnapshot.fMaxVelocity);
			kv.GoBack();
		}

		// load arrays
		if(kv.JumpToKey("CPTimes", false))
		{
			cache.aSnapshot.fCPTimes = empty_times;

			for(int i = 0; i < cache.aSnapshot.iLastStage + 1; i++)	// +1 for checkpoint data of linear map
			{
				char idx[8]; 
				IntToString(i, idx, sizeof(idx));

				cache.aSnapshot.fCPTimes[i] = kv.GetFloat(idx, -1.0);
			}
			kv.GoBack();
		}
		if(kv.JumpToKey("StageFinishTimes", false))
		{
			cache.aSnapshot.fStageFinishTimes = empty_times;

			for(int i = 0; i < cache.aSnapshot.iLastStage + 1; i++)
			{
				char idx[8]; IntToString(i, idx, sizeof(idx));
				cache.aSnapshot.fStageFinishTimes[i] = kv.GetFloat(idx, -1.0);
			}
			kv.GoBack();
		}
		if(kv.JumpToKey("StageAttempts", false))
		{
			cache.aSnapshot.iStageAttempts = empty_attempts;

			for(int i = 0; i <= cache.aSnapshot.iLastStage + 1; i++)
			{
				char idx[8]; IntToString(i, idx, sizeof(idx));
				cache.aSnapshot.iStageAttempts[i] = kv.GetNum(idx, 0);
			}
			kv.GoBack();
		}
		kv.GoBack();
	}

	if(kv.JumpToKey("replay", false))
	{
		iRealFrameCount = kv.GetNum("RiRealFrameCount", 0);
		cache.iStageStartFrames = kv.GetNum("RiStageStartFrames", 0);
		cache.iStageReachFrames = kv.GetNum("RiStageReachFrames", 0);
		kv.GoBack();
	}

	if(kv.JumpToKey("player", false))
	{
		cache.fPosition[0] = kv.GetFloat("CfPosition1", 0.0);
		cache.fPosition[1] = kv.GetFloat("CfPosition2", 0.0);
		cache.fPosition[2] = kv.GetFloat("CfPosition3", 0.0);
		cache.fAngles[0] = kv.GetFloat("CfAngles1", 0.0);
		cache.fAngles[1] = kv.GetFloat("CfAngles2", 0.0);
		cache.fAngles[2] = kv.GetFloat("CfAngles3", 0.0);
		cache.fVelocity[0] = kv.GetFloat("CfVelocity1", 0.0);
		cache.fVelocity[1] = kv.GetFloat("CfVelocity2", 0.0);
		cache.fVelocity[2] = kv.GetFloat("CfVelocity3", 0.0);
		cache.iMoveType = MOVETYPE_WALK;
		cache.fGravity = kv.GetFloat("CfGravity", 0.0);
		cache.fSpeed = kv.GetFloat("CfSpeed", 0.0);
		cache.fStamina = kv.GetFloat("CfStamina", 0.0);
		cache.bDucked = view_as<bool>(kv.GetNum("CbDucked", 0));
		cache.bDucking = view_as<bool>(kv.GetNum("CbDucking", 0));
		cache.fDucktime = kv.GetFloat("CfDuckTime", 0.0);
		cache.fDuckSpeed = kv.GetFloat("CfDuckSpeed", 0.0);
		cache.iFlags = kv.GetNum("CiFlags", 0);
		kv.GetString("CsTargetname", cache.sTargetname, sizeof(cp_cache_t::sTargetname), "");
		kv.GetString("CsClassname", cache.sClassname, sizeof(cp_cache_t::sClassname), "player");
		cache.iPreFrames = kv.GetNum("CiPreFrames", 0);
		cache.iStageStartFrames = kv.GetNum("CiStageStartFrames", 0);
		cache.bSegmented = view_as<bool>(kv.GetNum("CbSegmented", 0));
		cache.iGroundEntity = kv.GetNum("CiGroundEntity", 0);
		cache.vecLadderNormal[0] = kv.GetFloat("CvecLadderNormal1", 0.0);
		cache.vecLadderNormal[1] = kv.GetFloat("CvecLadderNormal2", 0.0);
		cache.vecLadderNormal[2] = kv.GetFloat("CvecLadderNormal3", 0.0);
		cache.m_bHasWalkMovedSinceLastJump = view_as<bool>(kv.GetNum("Cm_bHasWalkMovedSinceLastJump", 0));
		cache.m_ignoreLadderJumpTime = kv.GetFloat("Cm_ignoreLadderJumpTime", 0.0);
		cache.m_lastStandingPos[0] = kv.GetFloat("Cm_lastStandingPos1", 0.0);
		cache.m_lastStandingPos[1] = kv.GetFloat("Cm_lastStandingPos2", 0.0);
		cache.m_lastStandingPos[2] = kv.GetFloat("Cm_lastStandingPos3", 0.0);
		cache.m_ladderSurpressionTimer[0] = kv.GetFloat("Cm_ladderSuppressionTimer1", 0.0);
		cache.m_ladderSurpressionTimer[1] = kv.GetFloat("Cm_ladderSuppressionTimer2", 0.0);
		cache.m_lastLadderNormal[0] = kv.GetFloat("Cm_lastLadderNormal1", 0.0);
		cache.m_lastLadderNormal[1] = kv.GetFloat("Cm_lastLadderNormal2", 0.0);
		cache.m_lastLadderNormal[2] = kv.GetFloat("Cm_lastLadderNormal3", 0.0);
		cache.m_lastLadderPos[0] = kv.GetFloat("Cm_lastLadderPos1", 0.0);
		cache.m_lastLadderPos[1] = kv.GetFloat("Cm_lastLadderPos2", 0.0);
		cache.m_lastLadderPos[2] = kv.GetFloat("Cm_lastLadderPos3", 0.0);
		cache.m_afButtonDisabled = kv.GetNum("Cm_afButtonDisabled", 0);
		cache.m_afButtonForced = kv.GetNum("Cm_afButtonForced", 0);
		kv.GoBack();
	}

	if(kv.JumpToKey("events", false))
	{
		cache.aEvents = new ArrayList(sizeof(event_t));
		kv.GotoFirstSubKey(false);
		do
		{
			event_t e;
			kv.GetString("Etarget", e.target, sizeof(event_t::target), "");
			kv.GetString("EtargetInput", e.targetInput, sizeof(event_t::targetInput), "");
			kv.GetString("EvariantValue", e.variantValue, sizeof(event_t::variantValue), "");
			e.delay = kv.GetFloat("Edelay", 0.0);
			e.activator = kv.GetNum("Eactivator", 0);
			e.caller = kv.GetNum("Ecaller", 0);
			e.outputID = kv.GetNum("EoutputID", 0);
			cache.aEvents.PushArray(e, sizeof(entity_t));
		}
		while(kv.GotoNextKey(false));
		kv.GoBack();
	}

	if(kv.JumpToKey("outputwaits", false))
	{
		cache.aOutputWaits = new ArrayList(sizeof(entity_t));
		kv.GotoFirstSubKey(false);
		do
		{
			entity_t e;
			e.caller = kv.GetNum("Ecaller", 0);
			e.waitTime = kv.GetFloat("EwaitTime", 0.0);
			cache.aOutputWaits.PushArray(e, sizeof(entity_t));
		}
		while(kv.GotoNextKey(false));
		kv.GoBack();
	}

	if(kv.JumpToKey("customdata", false))
	{
		StringMap cd = new StringMap();
		float fPunishTime = kv.GetFloat("mpbhops_punishtime", 0.0);
		int iLastBlock = kv.GetNum("mpbhops_lastblock", 0);
		cd.SetValue("mpbhops_punishtime", fPunishTime);
		cd.SetValue("mpbhops_lastblock", iLastBlock);
		cache.customdata = cd;
		kv.GoBack();
	}

	delete kv;

	return true;
}

stock bool LoadReplayData(char[] sPath, int iRealFrameCount, cp_cache_t cache)
{
	if(!FileExists(sPath))
	{
		return false;
	}

	frame_cache_t aFrameCache;

	if(!LoadReplayCache(aFrameCache, cache.aSnapshot.bsStyle, cache.aSnapshot.iTimerTrack, 0, sPath, gS_Map))
	{
		LogError("(Load replay data) Failed to load replay: %s", sPath);
		return false;
	}

	if(aFrameCache.aFrames == null || aFrameCache.aFrames.Length == 0)
	{
		delete aFrameCache.aFrames;
		delete aFrameCache.aFrameOffsets;

		LogError("(Load replay data) No frames found in replay file: %s", sPath);
		return false;
	}

	cache.aFrames = aFrameCache.aFrames;

	if(aFrameCache.aFrameOffsets)
	{
		aFrameCache.aFrameOffsets.Resize(cache.aSnapshot.iLastStage + 1);

		offset_info_t offset;
		if(aFrameCache.aFrameOffsets.Length < 2)
		{
			offset.iFrameOffset = iRealFrameCount;
			aFrameCache.aFrameOffsets.PushArray(offset, sizeof(offset_info_t));
		}
		else
		{
			offset.iFrameOffset = iRealFrameCount;
			aFrameCache.aFrameOffsets.SetArray(0, offset, sizeof(offset_info_t));				
		}

		cache.aFrameOffsets = aFrameCache.aFrameOffsets;
	}

	return true;
}

stock void BuildSaveFolderPath(int client, char[] sMap, char[] path, int maxlen)
{
	char sAuth[32];
	IntToString(GetSteamAccountID(client), sAuth, sizeof(sAuth));
	BuildPath(Path_SM, path, maxlen, "data/timersaves/%s/%s", sAuth, sMap);
}

stock void BuildStylePaths(int client, int style, char[] sMap, char[] timerPath, int timerMaxLen, char[] replayPath, int replayMaxLen)
{
	char sFolder[PLATFORM_MAX_PATH];
	BuildSaveFolderPath(client, sMap, sFolder, sizeof(sFolder));

	// ensure nested folders exist
	char sAuth[32];
	char sAuthFolder[PLATFORM_MAX_PATH];

	IntToString(GetSteamAccountID(client), sAuth, sizeof(sAuth));
	BuildPath(Path_SM, sAuthFolder, sizeof(sAuthFolder), "data/timersaves/%s", sAuth);

	if(!DirExists(sAuthFolder)) 
	{
		CreateDirectory(sAuthFolder, 511);		
	}

	if(!DirExists(sFolder)) 
	{
		CreateDirectory(sFolder, 511);
	}

	FormatEx(timerPath, timerMaxLen, "%s\\%i.timer", sFolder, style);
	FormatEx(replayPath, replayMaxLen, "%s\\%i.replay", sFolder, style);
}

stock void BuildAuthFolderPath(int client, char[] path, int maxlen)
{
	char sAuth[32];
	IntToString(GetSteamAccountID(client), sAuth, sizeof(sAuth));
	BuildPath(Path_SM, path, maxlen, "data/timersaves/%s", sAuth);
}

stock bool IsDirectoryEmpty(const char[] folder)
{
	if(!DirExists(folder))
		return true;

	DirectoryListing dir = OpenDirectory(folder);
	if(dir == null)
		return true;

	FileType type;
	char name[PLATFORM_MAX_PATH];
	bool empty = true;

	while(ReadDirEntry(dir, name, sizeof(name), type))
	{
		// skip if any entry starts with '.' just in case
		if(name[0] == '.')
			continue;
		empty = false;
		break;
	}

	CloseHandle(dir);
	return empty;
}

stock bool HasSuffix(const char[] name, const char[] suffix)
{
	if (suffix[0] == '\0') 
	{
		return false;
	}

	int nameLen = strlen(name);
	int suffixLen = strlen(suffix);

	if (suffixLen > nameLen)
	{
		return false;
	}

	for (int i = 0; i < suffixLen; ++i) 
	{
		if (name[nameLen - suffixLen + i] != suffix[i]) 
		{
			return false;
		}
	}

	return true;
}

stock void DeleteCheckpointCache(cp_cache_t cache)
{
	delete cache.aFrames;
	delete cache.aFrameOffsets;
	delete cache.aEvents;
	delete cache.aOutputWaits;
	delete cache.customdata;
}

stock void ResetSaveCache(int client)
{
	delete gA_ClientSaves[client];
	delete gSM_ClientSavesIndex[client];
	gI_SaveCount[client] = 0;

	for (int i = 0; i < gI_StyleCount; i++)
	{
		if(gA_CurrentMapSaves[client][i].bHasSave)
		{
			saveinfo_t info;
			gA_CurrentMapSaves[client][i] = info;			
		}
	}
}

stock void LoadSaveInfo(char[] sPath, saveinfo_t info)
{
	KeyValues kv = new KeyValues("savestate");

	if(!kv.ImportFromFile(sPath))
	{
		info.bHasSave = false;
		delete kv;

		return;
	}

	kv.Rewind();

	if(kv.JumpToKey("meta", false))
	{
		info.bHasSave = true;
		info.fTime = kv.GetFloat("TfCurrentTime", 0.0);
		info.iDate = kv.GetNum("date", 0);
		info.iStyle = kv.GetNum("style", 0);
		info.iStage = kv.GetNum("stage", 0);
		kv.GetString("map", info.sMap, sizeof(saveinfo_t::sMap), "UNKNOWN");
		kv.GoBack();
	}
	else
	{
		info.bHasSave = false;
	}

	delete kv;
}

stock bool ShouldDisplayLoadWarning(int client)
{
	return gCV_StopTimerWarning == null ? false : (!Shavit_IsPracticeMode(client) && Shavit_GetTimerStatus(client) != Timer_Stopped && Shavit_GetClientTime(client) > gCV_StopTimerWarning.FloatValue && !Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), "segments"));
}