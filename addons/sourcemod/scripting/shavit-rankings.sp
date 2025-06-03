/*
 * shavit's Timer - Rankings
 * by: shavit, rtldg
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

// Design idea:
// Rank 1 per map/style/track gets ((points per tier * tier) * 1.5) + (rank 1 time in seconds / 15.0) points.
// Records below rank 1 get points% relative to their time in comparison to rank 1.
//
// Bonus track gets a 0.25* final multiplier for points and is treated as tier 1.
//
// Points for all styles are combined to promote competitive and fair gameplay.
// A player that gets good times at all styles should be ranked high.
//
// Total player points are weighted in the following way: (descending sort of points)
// points[0] * 0.975^0 + points[1] * 0.975^1 + points[2] * 0.975^2 + ... + points[n] * 0.975^n
//
// The ranking leaderboard will be calculated upon: map start.
// Points are calculated per-player upon: connection/map.
// Points are calculated per-map upon: map start, map end, tier changes.
// Rankings leaderboard is re-calculated once per map change.
// A command will be supplied to recalculate all of the above.
//
// Heavily inspired by pp (performance points) from osu!, written by Tom94. https://github.com/ppy/osu-performance

#include <sourcemod>
#include <convar_class>
#include <dhooks>

#include <shavit/core>
#include <shavit/rankings>
#include <shavit/wr>
#include <shavit/zones>

#undef REQUIRE_PLUGIN

#undef REQUIRE_EXTENSIONS
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

// #define DEBUG

enum struct ranking_t
{
	int iRank;
	float fPoints;
	int iWRAmountAll;
	int iWRAmountCvar;
	int iWRHolderRankAll;
	int iWRHolderRankCvar;
	int iWRAmount[STYLE_LIMIT*2];
	int iWRHolderRank[STYLE_LIMIT*2];
}

char gS_MySQLPrefix[32];
Database gH_SQL = null;
bool gB_SQLWindowFunctions = false;
bool gB_SqliteHatesPOW = false;
int gI_Driver = Driver_unknown;

bool gB_Stats = false;
bool gB_Late = false;
bool gB_TierQueried = false;

int gI_Tier = 1; // No floating numbers for tiers, sorry.

char gS_Map[PLATFORM_MAX_PATH];
EngineVersion gEV_Type = Engine_Unknown;

ArrayList gA_ValidMaps = null;
StringMap gA_MapInfo = null;

Convar gCV_BasicFinishPoints_Main = null;
Convar gCV_BasicFinishPoints_Bonus = null;
Convar gCV_BasicFinishPoints_Stage = null;

Convar gCV_BasicRankPoints_Main = null;
Convar gCV_BasicRankPoints_Bonus = null;
Convar gCV_BasicRankPoints_Stage = null;
Convar gCV_MaxRankPoints_Main = null;
Convar gCV_MaxRankPoints_Bonus = null;
Convar gCV_MaxRankPoints_Stage = null;
Convar gCV_ExtraFinishPointsMulitiplier = null;

Convar gCV_LastLoginRecalculate = null;
Convar gCV_MVPRankOnes_Slow = null;
Convar gCV_MVPRankOnes = null;
Convar gCV_MVPRankOnes_Main = null;
Convar gCV_DefaultTier = null;
Convar gCV_DefaultMaxVelocity = null;
Convar gCV_MinMaxVelocity = null;


ConVar sv_maxvelocity = null;

ranking_t gA_Rankings[MAXPLAYERS+1];

int gI_RankedPlayers = 0;
Menu gH_Top100Menu = null;

Handle gH_Forwards_OnTierAssigned = null;
Handle gH_Forwards_OnRankAssigned = null;

// Timer settings.
chatstrings_t gS_ChatStrings;
int gI_Styles = 0;
float gF_MaxVelocity;

bool gB_WorldRecordsCached = false;
bool gB_WRHolderTablesMade = false;
bool gB_WRHoldersRefreshed = false;
bool gB_WRHoldersRefreshedTimer = false;
int gI_WRHolders[2][STYLE_LIMIT];
int gI_WRHoldersAll;
int gI_WRHoldersCvar;

public Plugin myinfo =
{
	name = "[shavit-surf] Rankings",
	author = "shavit, rtldg, *Surf integration version modified by KikI",
	description = "A fair and competitive ranking system shavit surf timer. (This plugin is base on shavit's bhop timer)",
	version = SHAVIT_SURF_VERSION,
	url = "https://github.com/shavitush/bhoptimer  https://github.com/bhopppp/Shavit-Surf-Timer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetMapTier", Native_GetMapTier);
	CreateNative("Shavit_GetMapInfo", Native_GetMapInfo);
	CreateNative("Shavit_GetPoints", Native_GetPoints);
	CreateNative("Shavit_GetRank", Native_GetRank);
	CreateNative("Shavit_GetRankedPlayers", Native_GetRankedPlayers);
	CreateNative("Shavit_Rankings_DeleteMap", Native_Rankings_DeleteMap);
	CreateNative("Shavit_GetWRCount", Native_GetWRCount);
	CreateNative("Shavit_GetWRHolders", Native_GetWRHolders);
	CreateNative("Shavit_GetWRHolderRank", Native_GetWRHolderRank);
	CreateNative("Shavit_GuessPointsForTime", Native_GuessPointsForTime);

	RegPluginLibrary("shavit-rankings");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	gEV_Type = GetEngineVersion();

	gH_Forwards_OnTierAssigned = CreateGlobalForward("Shavit_OnTierAssigned", ET_Event, Param_String, Param_Cell);
	gH_Forwards_OnRankAssigned = CreateGlobalForward("Shavit_OnRankAssigned", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	RegConsoleCmd("sm_tier", Command_Tier, "Prints the map's tier to chat.");
	RegConsoleCmd("sm_maptier", Command_Tier, "Prints the map's tier to chat. (sm_tier alias)");

	RegConsoleCmd("sm_mapinfo", Command_MapInfo, "Shows map info to client.");

	RegConsoleCmd("sm_rank", Command_Rank, "Show your or someone else's rank. Usage: sm_rank [name]");
	RegConsoleCmd("sm_top", Command_Top, "Show the top 100 players.");

	RegAdminCmd("sm_settier", Command_SetTier, ADMFLAG_RCON, "Change the map's tier. Usage: sm_settier <tier> [map]");
	RegAdminCmd("sm_setmaptier", Command_SetTier, ADMFLAG_RCON, "Change the map's tier. Usage: sm_setmaptier <tier> [map] (sm_settier alias)");

	RegAdminCmd("sm_setmaxvelocity", Command_SetMaxVelocity, ADMFLAG_RCON, "Change the map's sv_maxvelocity. Usage: sm_setmaxvelocity <value> [map]");
	RegAdminCmd("sm_setmaxvel", Command_SetMaxVelocity, ADMFLAG_RCON, "Change the map's sv_maxvelocity. Usage: sm_setmaxvel <value> [map] (sm_setmaxvelocity alias)");
	RegAdminCmd("sm_setmapmaxvelocity", Command_SetMaxVelocity, ADMFLAG_RCON, "Change the map's sv_maxvelocity. Usage: sm_setmapmaxvelocity <value> [map] (sm_setmaxvelocity alias)");
	RegAdminCmd("sm_setmapmaxvel", Command_SetMaxVelocity, ADMFLAG_RCON, "Change the map's sv_maxvelocity. Usage: sm_setmapmaxvelocity <value> [map] (sm_setmaxvelocity alias)");

	RegAdminCmd("sm_recalcmap", Command_RecalcMap, ADMFLAG_RCON, "Recalculate the current map's records' points.");
	RegAdminCmd("sm_recalcall", Command_RecalcAll, ADMFLAG_ROOT, "Recalculate the points for every map on the server. Run this after you change the ranking multiplier for a style or after you install the plugin.");
	
	//its really a great design but someone may thought there are not enough point for beat a records, so i decide to rework it :( 
	//gCV_PointsPerTier = new Convar("shavit_rankings_pointspertier", "50.0", "Base points to use for per-tier scaling.\nRead the design idea to see how it works: https://github.com/shavitush/bhoptimer/issues/465", 0, true, 1.0);
	gCV_BasicFinishPoints_Main = new Convar("shavit_rankings_basicfinishpoint_main", "22.0", "Basic point for player when finished main.", 0, true, 0.0, false, 0.0);
	gCV_BasicFinishPoints_Bonus = new Convar("shavit_rankings_basicfinishpoint_bonus", "35.0", "Basic point for player when finished bonus.", 0, true, 0.0, false, 0.0);
	gCV_BasicFinishPoints_Stage = new Convar("shavit_rankings_basicfinishpoint_stage", "1.0", "Basic point for player when finished stage. (0.0 for using tier for basic point)", 0, true, 0.0, false, 0.0);
	
	gCV_BasicRankPoints_Main = new Convar("shavit_rankings_basicrankpoint_main", "350.0", "Max point for player's rank of main.", 0, true, 0.0, false, 0.0);
	gCV_BasicRankPoints_Bonus = new Convar("shavit_rankings_basicrankpoint_bonus", "150.0", "Max point for player's rank of bonus.", 0, true, 0.0, false, 0.0);
	gCV_BasicRankPoints_Stage = new Convar("shavit_rankings_basicrankpoint_stage", "50.0", "Max point for player's rank of stage.", 0, true, 0.0, false, 0.0);

	gCV_MaxRankPoints_Main = new Convar("shavit_rankings_maxrankpoint_main", "850.0", "Max point for player's rank of main.", 0, true, 0.0, false, 0.0);
	gCV_MaxRankPoints_Bonus = new Convar("shavit_rankings_maxrankpoint_bonus", "400.0", "Max point for player's rank of bonus.", 0, true, 0.0, false, 0.0);
	gCV_MaxRankPoints_Stage = new Convar("shavit_rankings_maxrankpoint_stage", "300.0", "Max point for player's rank of stage.", 0, true, 0.0, false, 0.0);

	gCV_ExtraFinishPointsMulitiplier = new Convar("shavit_rankings_extrafinishpoint_multiplier", "5.5", "YOU DONT NEED TO TOUCH THIS USUALLY\nThe mulitiplier to caculate extra finish points.\nFormula: tier * (max(0, tier-{X})**2) * basic_finsh_point", 0, true, 0.0, true, 10.0);

	gCV_LastLoginRecalculate = new Convar("shavit_rankings_llrecalc", "0", "Maximum amount of time (in minutes) since last login to recalculate points for a player.\nsm_recalcall does not respect this setting.\n0 - disabled, don't filter anyone", 0, true, 0.0);
	gCV_MVPRankOnes_Slow = new Convar("shavit_rankings_mvprankones_slow", "1", "Uses a slower but more featureful MVP counting system.\nEnables the WR Holder ranks & counts for every style & track.\nYou probably won't need to change this unless you have hundreds of thousands of player times in your database.", 0, true, 0.0, true, 1.0);
	gCV_MVPRankOnes = new Convar("shavit_rankings_mvprankones", "2", "Set the players' amount of MVPs to the amount of #1 times they have.\n0 - Disabled\n1 - Enabled, for all styles.\n2 - Enabled, for default style only.\n(CS:S/CS:GO only)", 0, true, 0.0, true, 2.0);
	gCV_MVPRankOnes_Main = new Convar("shavit_rankings_mvprankones_maintrack", "1", "If set to 0, all tracks will be counted for the MVP stars.\nOtherwise, only the main track will be checked.\n\nRequires \"shavit_stats_mvprankones\" set to 1 or above.\n(CS:S/CS:GO only)", 0, true, 0.0, true, 1.0);
	gCV_DefaultTier = new Convar("shavit_rankings_default_tier", "1", "Sets the default tier for new maps added.", 0, true, 0.0, true, 10.0);
	gCV_DefaultMaxVelocity = new Convar("shavit_rankings_default_maxvelocity", "3500.0", "Sets the default sv_maxvelocity for new maps added.", 0, true, 0.0, false, 0.0);
	gCV_MinMaxVelocity = new Convar("shavit_rankings_min_maxvelocity", "3499.9", "Sets the minimum sv_maxvelocity value.", 0, true, 0.0, false, 0.0);
	

	sv_maxvelocity = FindConVar("sv_maxvelocity");

	Convar.AutoExecConfig();

	LoadTranslations("plugin.basecommands");
	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-rankings.phrases");

	// tier cache
	gA_ValidMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	gA_MapInfo = new StringMap();

	if(gB_Late)
	{
		Shavit_OnChatConfigLoaded();
		Shavit_OnDatabaseLoaded();
	}

	if (gEV_Type != Engine_TF2)
	{
		CreateTimer(1.0, Timer_MVPs, 0, TIMER_REPEAT);
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	gI_Styles = styles;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = false;
	}
}

public void Shavit_OnDatabaseLoaded()
{
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = Shavit_GetDatabase(gI_Driver);

	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientAuthorized(i))
		{
			OnClientAuthorized(i, "");
		}
	}

	QueryLog(gH_SQL, SQL_Version_Callback,
		gI_Driver == Driver_sqlite
		? "WITH p AS (SELECT COUNT(*) FROM pragma_function_list WHERE name = 'pow') SELECT sqlite_version(), * FROM p;"
		: "SELECT VERSION();");

	if(!gB_TierQueried)
	{
		OnMapStart();
	}
}

public void Trans_RankingsSetupError(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Your Mysql/Mariadb didn't let us create the GetWeightedPoints function. Either update your DB version so it doesn't need GetWeightedPoints (to 8.0 or 10.2), fix your DB permissions, OR set `shavit_rankings_weighting` to `1.0`.");
	LogError("Timer (rankings) error %d/%d. Reason: %s", failIndex, numQueries, error);
	SetFailState("Read the error log");
}

public void Trans_RankingsSetupSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	OnMapStart();
}

public void OnClientConnected(int client)
{
	ranking_t empty_ranking;
	gA_Rankings[client] = empty_ranking;
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (gH_SQL && !IsFakeClient(client))
	{
		if (gB_WRHolderTablesMade)
		{
			UpdateWRs(client);
		}

		UpdatePlayerRank(client, true);
	}
}

public void OnMapStart()
{
	GetLowercaseMapName(gS_Map);
	Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount()); // just in case :)

	if (gH_SQL == null)
	{
		return;
	}

	if (gB_WRHolderTablesMade && !gB_WRHoldersRefreshed)
	{
		RefreshWRHolders();
	}

	// do NOT keep running this more than once per map, as UpdateAllPoints() is called after this eventually and locks up the database while it is running
	if (gB_TierQueried)
	{
		return;
	}

	RefreshMapSettings("");

	if (gB_SqliteHatesPOW)
	{
		LogError("Rankings Weighting multiplier set but sqlite extension isn't supported. Try using db.sqlite.ext from Sourcemod 1.12 or higher.");
	}

	if (gH_Top100Menu == null)
	{
		UpdateTop100();
	}
}

public void RefreshMapSettings(const char[] map)
{
	// Default tier.
	// I won't repeat the same mistake blacky has done with tier 3 being default..
	gI_Tier = gCV_DefaultTier.IntValue;
	gF_MaxVelocity = gCV_DefaultMaxVelocity.FloatValue;
	sv_maxvelocity.FloatValue = gF_MaxVelocity;

	char sQuery[512];
	char sWhere[256];
	if(map[0])
	{
		FormatEx(sWhere, sizeof(sWhere), " WHERE map = '%s'", map);
	}

	FormatEx(sQuery, sizeof(sQuery), "SELECT map, tier, maxvelocity, maptype, bonuses, stages FROM %smapinfo%s;", gS_MySQLPrefix, sWhere);
	QueryLog(gH_SQL, SQL_FillMapSettingCache_Callback, sQuery, 0, DBPrio_High);

	gB_TierQueried = true;
}

public void SQL_FillMapSettingCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, fill tier cache) error! Reason: %s", error);

		return;
	}

	gA_ValidMaps.Clear();
	gA_MapInfo.Clear();

	while(results.FetchRow())
	{
		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(0, sMap, sizeof(sMap));
		LowercaseString(sMap);

		mapinfo_t info;

		info.iTier = results.FetchInt(1);
		info.iType = results.FetchInt(3);
		info.iBonuses = results.FetchInt(4);
		
		if(info.iType == 0)
		{
			info.iStages = 0;
			info.iCheckpoints = results.FetchInt(5);
		}
		else if(info.iType == 1)
		{
			info.iStages = results.FetchInt(5);
			info.iCheckpoints = 0;
		}

		gA_MapInfo.SetArray(sMap, info, sizeof(mapinfo_t));
		gA_ValidMaps.PushString(sMap);

		if(StrEqual(sMap, gS_Map))
		{
			gF_MaxVelocity = results.FetchFloat(2);
			sv_maxvelocity.FloatValue = gF_MaxVelocity;
		}

		Call_StartForward(gH_Forwards_OnTierAssigned);
		Call_PushString(sMap);
		Call_PushCell(info.iTier);
		Call_Finish();
	}

	mapinfo_t mapinfo;

	if (!gA_MapInfo.GetArray(gS_Map, mapinfo, sizeof(mapinfo_t)))
	{
		Call_StartForward(gH_Forwards_OnTierAssigned);
		Call_PushString(gS_Map);
		Call_PushCell(gI_Tier);
		Call_Finish();

		char sQuery[512];
		
		// in case some gA_MapInfo is not cached because of database connection issues
		if(gI_Driver == Driver_sqlite)
		{
			FormatEx(sQuery, sizeof(sQuery), "INSERT OR IGNORE INTO %smaptiers (map, tier, maxvelocity) VALUES ('%s', %d, %f);", gS_MySQLPrefix, gS_Map, gI_Tier, gF_MaxVelocity);
		}
		else
		{
			FormatEx(sQuery, sizeof(sQuery), "INSERT IGNORE INTO %smaptiers (map, tier, maxvelocity) VALUES ('%s', %d, %f);", gS_MySQLPrefix, gS_Map, gI_Tier, gF_MaxVelocity);
		}
		
		QueryLog(gH_SQL, SQL_SetMapTier_Callback, sQuery, 0, DBPrio_High);
	}
}

public void Shavit_OnZoneCreated(int entity, int type, int track, int data)
{
	if (type == Zone_Stage || type == Zone_Checkpoint || (type == Zone_Start && track >= Track_Bonus))
	{
		RefreshMapSettings(gS_Map);
	}
}

public void Shavit_OnZoneDeleted(int type, int track, int data)
{
	if (type == Zone_Stage || type == Zone_Checkpoint || (type == Zone_Start && track >= Track_Bonus))
	{
		RefreshMapSettings(gS_Map);
	}
}

public void Shavit_OnAllZoneDeleted()
{
	RefreshMapSettings(gS_Map);
}

public void OnMapEnd()
{
	gB_TierQueried = false;
	gB_WRHoldersRefreshed = false;
	gB_WRHoldersRefreshedTimer = false;
	gB_WorldRecordsCached = false;
}


public void Shavit_OnWRDeleted(int style, int id, int track, int stage, int accountid, const char[] mapname)
{
	if (!StrEqual(gS_Map, mapname))
	{
		return;
	}

	char sQuery[1024];
	// bUseCurrentMap=true because shavit-wr should maybe have updated the wr even through the updatewrcache query hasn't run yet
	FormatRecalculate(true, track, stage, style, sQuery, sizeof(sQuery));
	QueryLog(gH_SQL, SQL_Recalculate_Callback, sQuery, (style << 8) | track, DBPrio_High);

	char map[PLATFORM_MAX_PATH];// Why use const char[] instead char[] ?
	FormatEx(map, sizeof(map), "%s", mapname);

	UpdateAllPoints(true, map, track, stage);
}

public void Shavit_OnWorldRecordsCached()
{
	gB_WorldRecordsCached = true;
}

public Action Timer_MVPs(Handle timer)
{
	if (gCV_MVPRankOnes.IntValue == 0)
	{
		return Plugin_Continue;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			CS_SetMVPCount(i, Shavit_GetWRCount(i, -1, -1, true));
		}
	}

	return Plugin_Continue;
}

void UpdateWRs(int client)
{
	int iSteamID = GetSteamAccountID(client);

	if(iSteamID == 0)
	{
		return;
	}

	char sQuery[512];

	if (gCV_MVPRankOnes_Slow.BoolValue)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"     SELECT *, 0 as track, 0 as type FROM %swrhrankmain  WHERE auth = %d \
			UNION SELECT *, 1 as track, 0 as type FROM %swrhrankbonus WHERE auth = %d \
			UNION SELECT *, -1,         1 as type FROM %swrhrankall   WHERE auth = %d \
			UNION SELECT *, -1,         2 as type FROM %swrhrankcvar  WHERE auth = %d;",
			gS_MySQLPrefix, iSteamID, gS_MySQLPrefix, iSteamID, gS_MySQLPrefix, iSteamID, gS_MySQLPrefix, iSteamID);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"SELECT 0 as wrrank, -1 as style, auth, COUNT(*), -1 as track, 2 as type FROM %swrs WHERE auth = %d %s %s;",
			gS_MySQLPrefix,
			iSteamID,
			(gCV_MVPRankOnes.IntValue == 2)  ? "AND style = 0" : "",
			(gCV_MVPRankOnes_Main.BoolValue) ? "AND track = 0" : ""
		);
	}

	QueryLog(gH_SQL, SQL_GetWRs_Callback, sQuery, GetClientSerial(client));
}

public void SQL_GetWRs_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("SQL_GetWRs_Callback failed. Reason: %s", error);
		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	while (results.FetchRow())
	{
		int wrrank  = results.FetchInt(0);
		int style   = results.FetchInt(1);
		//int auth    = results.FetchInt(2);
		int wrcount = results.FetchInt(3);
		int track   = results.FetchInt(4);
		int type    = results.FetchInt(5);

		if (type == 0)
		{
			int index = STYLE_LIMIT*track + style;
			gA_Rankings[client].iWRAmount[index] = wrcount;
			gA_Rankings[client].iWRHolderRank[index] = wrrank;
		}
		else if (type == 1)
		{
			gA_Rankings[client].iWRAmountAll = wrcount;
			gA_Rankings[client].iWRHolderRankAll = wrcount;
		}
		else if (type == 2)
		{
			gA_Rankings[client].iWRAmountCvar = wrcount;
			gA_Rankings[client].iWRHolderRankCvar = wrrank;
		}
	}
}

public Action Command_Tier(int client, int args)
{
	int tier = gI_Tier;

	char sMap[PLATFORM_MAX_PATH];

	if(args == 0)
	{
		sMap = gS_Map;
	}
	else
	{
		GetCmdArgString(sMap, sizeof(sMap));
		LowercaseString(sMap);
	}
	
	mapinfo_t mapinfo;
	if(!GuessBestMapName(gA_ValidMaps, sMap, sMap) || !gA_MapInfo.GetArray(sMap, mapinfo, sizeof(mapinfo_t)))
	{
		Shavit_PrintToChat(client, "%t", "Map was not found", sMap);
		return Plugin_Handled;
	}

	tier = mapinfo.iTier;

	Shavit_PrintToChat(client, "%T", "CurrentTier", client, gS_ChatStrings.sVariable, sMap, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, tier, gS_ChatStrings.sText);

	return Plugin_Handled;
}

public Action Command_MapInfo(int client, int args)
{
	char sMap[PLATFORM_MAX_PATH];

	if(args == 0)
	{
		sMap = gS_Map;
	}
	else
	{
		GetCmdArg(1, sMap, sizeof(sMap));
		LowercaseString(sMap);

		Menu mapmatches = new Menu(MenuHandler_MapInfoMatches);
		mapmatches.SetTitle("%T", "Choose Map", client);

		int length = gA_ValidMaps.Length;
		for (int i = 0; i < length; i++)
		{
			char entry[PLATFORM_MAX_PATH];
			gA_ValidMaps.GetString(i, entry, PLATFORM_MAX_PATH);

			if (StrContains(entry, sMap) != -1)
			{
				mapmatches.AddItem(entry, entry);
			}
		}

		switch (mapmatches.ItemCount)
		{
			case 0:
			{
				delete mapmatches;
				Shavit_PrintToChat(client, "%t", "Map was not found", sMap);
				return Plugin_Handled;
			}
			case 1:
			{
				mapmatches.GetItem(0, sMap, sizeof(sMap));
				delete mapmatches;
			}
			default:
			{
				mapmatches.Display(client, MENU_TIME_FOREVER);
				return Plugin_Handled;
			}
		}
	}

	PrintMapInfo(client, sMap);	

	return Plugin_Handled;
}

public void PrintMapInfo(int client, const char[] map)
{
	mapinfo_t mapinfo;

	if(!gA_MapInfo.GetArray(map, mapinfo, sizeof(mapinfo_t)))
	{
		Shavit_PrintToChat(client, "%t", "Map was not found", map);
		return;
	}

	char sType[32];
	char sStageInfo[32];

	if(mapinfo.iType == 1)
	{
		FormatEx(sType, 16, "Staged");
		FormatEx(sStageInfo, 16, "%d Stages", mapinfo.iStages);
	}
	else
	{
		FormatEx(sType, 16, "Linear");
		FormatEx(sStageInfo, 16, "%d Checkpoint%s", mapinfo.iCheckpoints, mapinfo.iCheckpoints > 2 ? "s":"");
	}

	char sTrackInfo[32];
	FormatEx(sTrackInfo, 32, "%d Bonus%s", mapinfo.iBonuses, mapinfo.iBonuses > 1 ? "es":"");

	char sTier[8];
	FormatEx(sTier, 8, "Tier %d", mapinfo.iTier);

	Shavit_PrintToChat(client, "Map: %s%s%s - %s | %s%s%s | %s%s%s | %s%s%s |",
		gS_ChatStrings.sVariable2, map, gS_ChatStrings.sText, sType,
		gS_ChatStrings.sVariable, sTier, gS_ChatStrings.sText,
		gS_ChatStrings.sVariable, sStageInfo, gS_ChatStrings.sText,
		gS_ChatStrings.sVariable, sTrackInfo, gS_ChatStrings.sText);		
}

public int MenuHandler_MapInfoMatches(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char map[PLATFORM_MAX_PATH];
		menu.GetItem(param2, map, sizeof(map));

		PrintMapInfo(param1, map);	
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Rank(int client, int args)
{
	int target = client;

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		target = FindTarget(client, sArgs, true, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}

	if(gA_Rankings[target].fPoints == 0.0)
	{
		Shavit_PrintToChat(client, "%T", "Unranked", client, gS_ChatStrings.sVariable2, target, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	Shavit_PrintToChat(client, "%T", "Rank", client, gS_ChatStrings.sVariable2, target, gS_ChatStrings.sText,
		gS_ChatStrings.sVariable, (gA_Rankings[target].iRank > gI_RankedPlayers)? gI_RankedPlayers:gA_Rankings[target].iRank, gS_ChatStrings.sText,
		gI_RankedPlayers,
		gS_ChatStrings.sVariable, gA_Rankings[target].fPoints, gS_ChatStrings.sText);

	return Plugin_Handled;
}

public Action Command_Top(int client, int args)
{
	if(gH_Top100Menu != null)
	{
		gH_Top100Menu.SetTitle("%T (%d)\n ", "Top100", client, gI_RankedPlayers);
		gH_Top100Menu.Display(client, MENU_TIME_FOREVER);
	}

	return Plugin_Handled;
}

public int MenuHandler_Top(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, 32);

		if(gB_Stats && !StrEqual(sInfo, "-1"))
		{
			FakeClientCommand(param1, "sm_profile [U:1:%s]", sInfo);
		}
	}

	return 0;
}

public Action Command_SetMaxVelocity(int client, int args)
{
	char sArg[8];
	GetCmdArg(1, sArg, 8);

	float fMaxVelocity = StringToFloat(sArg);
	float fOldMaxVelocity = sv_maxvelocity.FloatValue;

	if(args == 0 || fMaxVelocity < gCV_MinMaxVelocity.FloatValue)
	{
		char sMessage[64];
		Format(sMessage, 64, "sm_setmaxvelocity <value> (%.0f or greater) [map]", gCV_MinMaxVelocity.FloatValue);
		ReplyToCommand(client, "%T", "ArgumentsMissing", client, sMessage);

		return Plugin_Handled;
	}

	char map[PLATFORM_MAX_PATH];

	if (args < 2)
	{
		gF_MaxVelocity = fMaxVelocity;
		map = gS_Map;
		sv_maxvelocity.FloatValue = gF_MaxVelocity;
	}
	else
	{
		GetCmdArg(2, map, sizeof(map));
		TrimString(map);
		LowercaseString(map);

		if (!map[0])
		{
			Shavit_PrintToChat(client, "Invalid map name");
			return Plugin_Handled;
		}
	}

	for(int i = 0; i < MaxClients; i++)
	{
		Shavit_PrintToChat(i, "%T", "SetMaxVelocity", i, gS_ChatStrings.sVariable2, fOldMaxVelocity, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, fMaxVelocity, gS_ChatStrings.sText);
	}
	
	Shavit_LogMessage("%L - set sv_maxvelocity of `%s` to %f", client, gS_Map, fMaxVelocity);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %smaptiers SET maxvelocity = %f WHERE map = '%s';", gS_MySQLPrefix, fMaxVelocity, map);

	QueryLog(gH_SQL, SQL_SetMapMaxVelocity_Callback, sQuery, fMaxVelocity);

	return Plugin_Handled;
}

public void SQL_SetMapMaxVelocity_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, set map maxvelocity) error! Reason: %s", error);

		return;
	}
}

public Action Command_SetTier(int client, int args)
{
	char sArg[8];
	GetCmdArg(1, sArg, 8);

	int tier = StringToInt(sArg);

	if(args == 0 || tier < 1 || tier > 10)
	{
		ReplyToCommand(client, "%T", "ArgumentsMissing", client, "sm_settier <tier> (1-10) [map]");

		return Plugin_Handled;
	}

	char map[PLATFORM_MAX_PATH];

	if (args < 2)
	{
		gI_Tier = tier;
		map = gS_Map;
	}
	else
	{
		GetCmdArg(2, map, sizeof(map));
		TrimString(map);

		if (!map[0])
		{
			Shavit_PrintToChat(client, "Invalid map name");
			return Plugin_Handled;
		}

		LowercaseString(map);

		Menu mapmatches = new Menu(SetMapTier_MatchesMenuHandler);
		mapmatches.SetTitle("%T", "Choose Map", client);

		int length = gA_ValidMaps.Length;
		int iLastIndex = -1;
		for (int i = 0; i < length; i++)
		{
			char entry[PLATFORM_MAX_PATH];
			gA_ValidMaps.GetString(i, entry, PLATFORM_MAX_PATH);

			if (StrContains(entry, map) != -1)
			{
				char sInfo[PLATFORM_MAX_PATH];
				FormatEx(sInfo, sizeof(sInfo), "%s;%d", entry, tier);
				mapmatches.AddItem(sInfo, entry);
				iLastIndex = i;
			}
		}

		switch (mapmatches.ItemCount)
		{
			case 0:
			{
				delete mapmatches;
				Shavit_PrintToChat(client, "%t", "Map was not found", map);
				return Plugin_Handled;
			}
			case 1:
			{
				gA_ValidMaps.GetString(iLastIndex, map, sizeof(map));
				delete mapmatches;
			}
			default:
			{
				mapmatches.Display(client, MENU_TIME_FOREVER);
				return Plugin_Handled;
			}
		}
	}

	mapinfo_t mapinfo;
	gA_MapInfo.GetArray(map, mapinfo, sizeof(mapinfo_t));

	mapinfo.iTier = tier;
	gA_MapInfo.SetArray(map, mapinfo, sizeof(mapinfo_t));

	Call_StartForward(gH_Forwards_OnTierAssigned);
	Call_PushString(map);
	Call_PushCell(tier);
	Call_Finish();

	Shavit_PrintToChat(client, "%T", "SetTier", client, gS_ChatStrings.sVariable, map, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, tier, gS_ChatStrings.sText);
	Shavit_LogMessage("%L - set tier of `%s` to %d", client, map, tier);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %smaptiers SET tier = %d WHERE map = '%s';", gS_MySQLPrefix, tier, map);

	DataPack data = new DataPack();
	data.WriteCell(client ? GetClientSerial(client) : 0);
	data.WriteString(map);

	QueryLog(gH_SQL, SQL_SetMapTier_Callback, sQuery, data);

	return Plugin_Handled;
}

public int SetMapTier_MatchesMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[PLATFORM_MAX_PATH];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		char sExploded[2][PLATFORM_MAX_PATH];
		ExplodeString(sInfo, ";", sExploded, 2, PLATFORM_MAX_PATH);

		int tier = StringToInt(sExploded[1]);

		mapinfo_t mapinfo;
		gA_MapInfo.GetArray(sExploded[0], mapinfo, sizeof(mapinfo_t));

		mapinfo.iTier = tier;
		gA_MapInfo.SetArray(sExploded[0], mapinfo, sizeof(mapinfo_t));

		Call_StartForward(gH_Forwards_OnTierAssigned);
		Call_PushString(sExploded[0]);
		Call_PushCell(tier);
		Call_Finish();

		Shavit_PrintToChat(param1, "%T", "SetTier", param1, gS_ChatStrings.sVariable, sExploded[0], gS_ChatStrings.sText, gS_ChatStrings.sVariable2, tier, gS_ChatStrings.sText);
		Shavit_LogMessage("%L - set tier of `%s` to %d", param1, sExploded[0], tier);

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "UPDATE %smaptiers SET tier = %d WHERE map = '%s';", gS_MySQLPrefix, tier, sExploded[0]);

		DataPack data = new DataPack();
		data.WriteCell(GetClientSerial(param1));
		data.WriteString(sExploded[0]);

		QueryLog(gH_SQL, SQL_SetMapTier_Callback, sQuery, data);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void SQL_SetMapTier_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if(results == null)
	{
		LogError("Timer (rankings, set map tier) error! Reason: %s", error);

		return;
	}

	if (data == null)
	{
		return;
	}

	int serial;
	char map[PLATFORM_MAX_PATH];

	data.Reset();
	serial = data.ReadCell();
	data.ReadString(map, sizeof(map));

	if (StrEqual(map, gS_Map))
	{
		ReallyRecalculateCurrentMap();
	}
	else
	{
		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "SELECT map, MAX(data) AS stage FROM mapzones WHERE (type = 2 OR type = 0) AND map='%s';", map);
		QueryLog(gH_SQL, SQL_RecalculateSpecificMap_Callback, sQuery, serial);
	}

	delete data;
}

public Action Command_RecalcMap(int client, int args)
{
	ReallyRecalculateCurrentMap();

	ReplyToCommand(client, "Recalc started.");

	return Plugin_Handled;
}

// You can use Sourcepawn_GetRecordPoints() as a reference for how the queries calculate points.
void FormatRecalculate(bool bUseCurrentMap, int track, int stage, int style, char[] sQuery, int sQueryLen, const char[] map = "")
{
	float fMultiplier = Shavit_GetStyleSettingFloat(style, "rankingmultiplier");

	char sTable[32];
	FormatEx(sTable, sizeof(sTable), "%s", stage == 0 ? "playertimes":"stagetimes");

	if (Shavit_GetStyleSettingBool(style, "unranked") || fMultiplier == 0.0)
	{
		FormatEx(sQuery, sQueryLen,
			"UPDATE %s%s SET points = 0 WHERE style = %d AND track %c 0 %s%s%s;",
			gS_MySQLPrefix, sTable,
			style,
			(track > 0) ? '>' : '=',
			(bUseCurrentMap) ? "AND map = '" : "",
			(bUseCurrentMap) ? gS_Map : "",
			(bUseCurrentMap) ? "'" : ""
		);

		return;
	}

	float fMaxRankPoint;
	float fBaiscFinishPoint;
	float fExtraFinishPoint = 0.0;
	float fTier = float(gI_Tier);
	float fCount;

	if(track >= Track_Bonus)
	{
		fCount = float(Shavit_GetRecordAmount(style, track));
		fCount = (fCount == 0.0) ? 1.0:fCount;
		fTier = 1.0;
		fMaxRankPoint = min(gCV_MaxRankPoints_Bonus.FloatValue, gCV_BasicRankPoints_Bonus.FloatValue + fCount / 2.0);
		fBaiscFinishPoint = gCV_BasicFinishPoints_Bonus.FloatValue;
	}
	else if(stage == 0)
	{
		fCount = float(Shavit_GetRecordAmount(style, track));
		fCount = (fCount == 0.0) ? 1.0:fCount;
		fMaxRankPoint = min(gCV_MaxRankPoints_Main.FloatValue, gCV_BasicRankPoints_Main.FloatValue + fCount * (Pow(fTier, 2.0) / max(9.0-fTier, 1.0)));
		fBaiscFinishPoint = gCV_BasicFinishPoints_Main.FloatValue;
		fExtraFinishPoint = fTier * Pow(max(0.0, fTier-gCV_ExtraFinishPointsMulitiplier.FloatValue), 2.0) * fBaiscFinishPoint;
	}
	else 
	{
		fCount = float(Shavit_GetStageRecordAmount(style, stage));
		fCount = (fCount == 0.0) ? 1.0:fCount;
		fMaxRankPoint = min(gCV_MaxRankPoints_Stage.FloatValue, gCV_BasicRankPoints_Stage.FloatValue + fCount * (Pow(fTier, 2.0) / max(16.0-fTier, 1.0)));
		fBaiscFinishPoint = gCV_BasicFinishPoints_Stage.FloatValue == 0.0 ? fTier : gCV_BasicFinishPoints_Stage.FloatValue;
	}

	float fFinishPoint = fBaiscFinishPoint * fTier;

	char sStageFilter[32];
	if(stage > 0) FormatEx(sStageFilter, sizeof(sStageFilter), "AND stage = %d", stage);

	if (bUseCurrentMap)
	{
		if(gI_Driver == Driver_mysql)
		{
			FormatEx(sQuery, sQueryLen,
				"UPDATE %s%s PT " ...
				"JOIN ( " ...
				"	SELECT id, time, RANK() OVER (ORDER BY time ASC) AS r FROM %s%s WHERE map = '%s' AND style = %d AND track = %d %s "...
				") AS Ranked ON PT.id = Ranked.id "...
				"SET PT.points = (%f / Ranked.r) + %f WHERE PT.id = Ranked.id;",
				gS_MySQLPrefix, sTable,  gS_MySQLPrefix, sTable, gS_Map, style, track, sStageFilter, fMaxRankPoint, (fFinishPoint + fExtraFinishPoint) * fMultiplier);	
		}
		else if(gI_Driver == Driver_sqlite)
		{
			FormatEx(sQuery, sQueryLen,
				"WITH RankedPT AS "...
				"(SELECT id, %f / RANK() OVER (ORDER BY time ASC) AS points FROM %s%s WHERE map = '%s' AND style = %d AND track = %d %s) "...
				"UPDATE %s%s SET points = RankedPT.points + %f FROM RankedPT WHERE %s.id = RankedPT.id;",
				fMaxRankPoint, gS_MySQLPrefix, sTable, gS_Map, style, track, sStageFilter, gS_MySQLPrefix, sTable, (fFinishPoint + fExtraFinishPoint) * fMultiplier, sTable);			
		}
	}
	else
	{
		char mapfilter[50+PLATFORM_MAX_PATH];
		if (map[0]) FormatEx(mapfilter, sizeof(mapfilter), "AND %s.map = '%s'", sTable, map);
		
		char sPointCalculate[256];

		if(stage > 0)
		{
			char sStagePoint[256];
			if(gCV_BasicFinishPoints_Stage.FloatValue == 0.0)
			{
				FormatEx(sStagePoint, sizeof(sStagePoint), "Ranked.tier");				
			}
			else
			{
				FormatEx(sStagePoint, sizeof(sStagePoint), "%f", gCV_BasicFinishPoints_Stage.FloatValue);
			}

			FormatEx(sPointCalculate, sizeof(sPointCalculate), "%s(%f, %f + Ranked.c * (POW(Ranked.tier, 2.0) / %s((16.0 - Ranked.tier), 1.0))) / Ranked.r + (Ranked.tier * %s * %f)", 
			gI_Driver == Driver_sqlite ? "MIN":"LEAST", gCV_MaxRankPoints_Stage.FloatValue, gCV_BasicRankPoints_Stage.FloatValue, gI_Driver == Driver_sqlite ? "MAX":"GREATEST", 
			sStagePoint, fMultiplier);
		}
		else if(track == Track_Main)
		{
			FormatEx(sPointCalculate, sizeof(sPointCalculate), "%s(%f, %f + Ranked.c * (POW(Ranked.tier, 2.0) / %s((9.0 - Ranked.tier), 1.0))) / Ranked.r + ((Ranked.tier + (Ranked.tier * POW(%s(0.0, Ranked.tier - %f), 2.0))) * %f * %f)", 
			gI_Driver == Driver_sqlite ? "MIN":"LEAST", gCV_MaxRankPoints_Main.FloatValue, gCV_BasicRankPoints_Main.FloatValue, gI_Driver == Driver_sqlite ? "MAX":"GREATEST", 
			gI_Driver == Driver_sqlite ? "MAX":"GREATEST", gCV_ExtraFinishPointsMulitiplier.FloatValue, fBaiscFinishPoint, fMultiplier);
		}
		else
		{
			FormatEx(sPointCalculate, sizeof(sPointCalculate), "%s(%f, %f + Ranked.c / 2.0) / Ranked.r + %f * %f", 
			gI_Driver == Driver_sqlite ? "MIN":"LEAST", gCV_MaxRankPoints_Bonus.FloatValue, gCV_BasicRankPoints_Bonus.FloatValue, 
			gCV_BasicFinishPoints_Bonus.FloatValue, fMultiplier);
		}

		if(gI_Driver == Driver_mysql)
		{
			FormatEx(sQuery, sQueryLen,
				"UPDATE %s%s PT " ...
				"JOIN ( " ...
				"	SELECT id, time, RANK() OVER (ORDER BY time ASC) AS r, COUNT(%s.map) OVER() as c, tier FROM %s%s "...
				" JOIN %smaptiers AS MT ON MT.map = %s.map WHERE style = %d AND track = %d %s %s "...
				") AS Ranked ON PT.id = Ranked.id "...
				"SET PT.points = %s WHERE PT.id = Ranked.id;",
				gS_MySQLPrefix, sTable, sTable, gS_MySQLPrefix, sTable, gS_MySQLPrefix, sTable, style, track, mapfilter, sStageFilter, sPointCalculate);
		}
		else if(gI_Driver == Driver_sqlite)
		{
			FormatEx(sQuery, sQueryLen,
				"WITH Ranked AS "...
				"(SELECT id, CAST(tier AS FLOAT) as tier, RANK() OVER (ORDER BY time ASC) AS r, COUNT(%s.map) OVER() AS c "...
				"FROM %s%s JOIN %smaptiers AS MT ON %s.map = MT.map WHERE track = %d AND style = %d %s %s ) "...
				"UPDATE %s%s SET points = %s "...
				"FROM Ranked WHERE %s.id = Ranked.id;",
				sTable, gS_MySQLPrefix, sTable, gS_MySQLPrefix, sTable, 
				track, style, mapfilter, sStageFilter, gS_MySQLPrefix, sTable, sPointCalculate, sTable);		
		}
	}
}

public Action Command_RecalcAll(int client, int args)
{
	ReplyToCommand(client, "- Started recalculating points for all maps. Check console for output.");

	Transaction trans = new Transaction();
	char sQuery[1024];

	FormatEx(sQuery, sizeof(sQuery), "UPDATE %splayertimes SET points = 0;", gS_MySQLPrefix);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %sstagetimes SET points = 0;", gS_MySQLPrefix);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %susers SET points = 0;", gS_MySQLPrefix);
	AddQueryLog(trans, sQuery);

	// Recalculate 
	if (gI_Driver == Driver_mysql)
	{
		for(int i = 0; i < gI_Styles; i++)
		{
			if (!Shavit_GetStyleSettingBool(i, "unranked") && Shavit_GetStyleSettingFloat(i, "rankingmultiplier") != 0.0)
			{
				float fMultiplier = Shavit_GetStyleSettingFloat(i, "rankingmultiplier");

				FormatEx(sQuery, sizeof(sQuery), 
					"UPDATE %splayertimes PT "...
					"JOIN ( "...
					"	SELECT id, time, TS.map, track, RANK() OVER (PARTITION BY map, track, style ORDER BY time ASC) r, "...
					"	COUNT(TS.map) OVER(PARTITION BY map, track, style) c, tier "...
					"	FROM %splayertimes TS "...
					"	JOIN %smaptiers AS MT ON TS.map = MT.map) AS Ranked ON PT.id = Ranked.id "...
					"	SET PT.points = ( LEAST(%f, %f + Ranked.c * (POW(Ranked.tier, 2.0) / GREATEST((9.0 - Ranked.tier), 1.0))) / Ranked.r ) + (Ranked.tier * POW(GREATEST(0.0, Ranked.tier - %f), 2.0) + Ranked.tier) * %f * %f "...
					"	WHERE PT.style = %d AND PT.track = 0;",
					gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, 
					gCV_MaxRankPoints_Main.FloatValue, gCV_BasicRankPoints_Main.FloatValue, gCV_ExtraFinishPointsMulitiplier.FloatValue, gCV_BasicFinishPoints_Main.FloatValue, fMultiplier, i);

				AddQueryLog(trans, sQuery);

				FormatEx(sQuery, sizeof(sQuery), 
					"UPDATE %splayertimes PT "...
					"JOIN ( "...
					"	SELECT id, time, TS.map, track, RANK() OVER (PARTITION BY map, track, style ORDER BY time ASC) r, "...
					"	COUNT(TS.map) OVER(PARTITION BY map, track, style) c, tier "...
					"	FROM %splayertimes TS"...
					"	JOIN %smaptiers AS MT ON TS.map = MT.map) AS Ranked ON PT.id = Ranked.id"...
					"	SET PT.points = ( LEAST(%f, %f + Ranked.c / 2.0) / Ranked.r ) + (%f * %f) "... 
					"	WHERE PT.style = %d AND PT.track > 0;",
					gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, 
					gCV_MaxRankPoints_Bonus.FloatValue, gCV_BasicRankPoints_Bonus.FloatValue, gCV_BasicFinishPoints_Bonus.FloatValue, fMultiplier, i);

				AddQueryLog(trans, sQuery);

				// Recalculate stages	
				char sBasicStagePoint[32];
				if(gCV_BasicFinishPoints_Stage.FloatValue == 0.0)
				{
					FormatEx(sBasicStagePoint, sizeof(sBasicStagePoint), "Ranked.tier");
				}
				else
				{
					gCV_BasicFinishPoints_Stage.GetString(sBasicStagePoint, sizeof(sBasicStagePoint));
				}

				FormatEx(sQuery, sizeof(sQuery), 
					"UPDATE %sstagetimes PT "...
					"JOIN ( "...
					"	SELECT id, time, TS.map, stage, RANK() OVER (PARTITION BY map, stage, style ORDER BY time ASC) r, "...
					"	COUNT(TS.map) OVER(PARTITION BY map, stage, style) c, tier "...
					"	FROM %sstagetimes TS"...
					"	JOIN %smaptiers AS MT ON TS.map = MT.map) AS Ranked ON PT.id = Ranked.id"...
					"	SET PT.points = ( LEAST(%f, %f + Ranked.c * (POW(Ranked.tier, 2.0) / GREATEST((16.0 - Ranked.tier), 1.0))) / Ranked.r ) + (Ranked.tier * %s * %f) WHERE style = %d;",
					gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, gCV_MaxRankPoints_Stage.FloatValue, gCV_BasicRankPoints_Stage.FloatValue, sBasicStagePoint, fMultiplier, i);

				AddQueryLog(trans, sQuery);
			}
		}		
	}
	else if(gI_Driver == Driver_sqlite)
	{
		for(int i = 0; i < gI_Styles; i++)
		{
			if (!Shavit_GetStyleSettingBool(i, "unranked") && Shavit_GetStyleSettingFloat(i, "rankingmultiplier") != 0.0)
			{
				float fMultiplier = Shavit_GetStyleSettingFloat(i, "rankingmultiplier");
			
				// Recalculate main
				FormatEx(sQuery, sizeof(sQuery),
					"WITH Ranked AS "...
					"(SELECT id, CAST(tier AS FLOAT) as tier, "...
					"RANK() OVER (PARTITION BY PT.map, track, style ORDER BY time ASC) AS r, COUNT(PT.map) OVER(PARTITION BY PT.map, track, style) AS c "...
					"FROM %splayertimes PT JOIN %smaptiers AS MT ON PT.map = MT.map WHERE track = 0 AND style = %d) "...
					"UPDATE %splayertimes SET points = ( MIN(%f, %f + Ranked.c * (POW(Ranked.tier, 2.0) / MAX((9.0 - Ranked.tier), 1.0))) / Ranked.r ) + (Ranked.tier * POW(MAX(0.0, Ranked.tier - 4.0), 2.0) + Ranked.tier) * %f * %f "...
					"FROM Ranked WHERE playertimes.id = Ranked.id;",
					gS_MySQLPrefix, gS_MySQLPrefix, i, gS_MySQLPrefix,
					gCV_MaxRankPoints_Main.FloatValue, gCV_BasicRankPoints_Main.FloatValue, gCV_BasicFinishPoints_Main.FloatValue, fMultiplier);		

				AddQueryLog(trans, sQuery);

				// Recalculate bonuses
				FormatEx(sQuery, sizeof(sQuery),
					"WITH Ranked AS "...
					"(SELECT id, CAST(tier AS FLOAT) as tier, "...
					"RANK() OVER (PARTITION BY PT.map, track, style ORDER BY time ASC) AS r, COUNT(PT.map) OVER(PARTITION BY PT.map, track, style) AS c "...
					"FROM %splayertimes PT JOIN %smaptiers AS MT ON PT.map = MT.map WHERE track > 0 AND style = %d) "...
					"UPDATE %splayertimes SET points = ( MIN(%f, %f + Ranked.c / 2.0) / Ranked.r ) + (%f * %f) "...
					"FROM Ranked WHERE playertimes.id = Ranked.id;",
					gS_MySQLPrefix, gS_MySQLPrefix, i, gS_MySQLPrefix,
					gCV_MaxRankPoints_Bonus.FloatValue, gCV_BasicRankPoints_Bonus.FloatValue, gCV_BasicFinishPoints_Bonus.FloatValue, fMultiplier);	

				AddQueryLog(trans, sQuery);

				// Recalculate stages	
				char sBasicStagePoint[32];
				if(gCV_BasicFinishPoints_Stage.FloatValue == 0.0)
				{
					FormatEx(sBasicStagePoint, sizeof(sBasicStagePoint), "Ranked.tier");
				}
				else
				{
					gCV_BasicFinishPoints_Stage.GetString(sBasicStagePoint, sizeof(sBasicStagePoint));
				}

				FormatEx(sQuery, sizeof(sQuery),
					"WITH Ranked AS "...
					"(SELECT id, CAST(tier AS FLOAT) as tier, "...
					"RANK() OVER (PARTITION BY PT.map, stage, style ORDER BY time ASC) AS r, COUNT(PT.map) OVER(PARTITION BY PT.map, stage, style) AS c "...
					"FROM %sstagetimes PT JOIN %smaptiers AS MT ON PT.map = MT.map WHERE style = %d) "...
					"UPDATE %sstagetimes SET points = ( MIN(%f, %f + Ranked.c * (POW(Ranked.tier, 2.0) / MAX((16.0 - Ranked.tier), 1.0))) / Ranked.r ) + (Ranked.tier * %s * %f) "...
					"FROM Ranked WHERE stagetimes.id = Ranked.id;",
					gS_MySQLPrefix, gS_MySQLPrefix, i, gS_MySQLPrefix,
					gCV_MaxRankPoints_Stage.FloatValue, gCV_BasicRankPoints_Stage.FloatValue, sBasicStagePoint, fMultiplier);	

				AddQueryLog(trans, sQuery);
			}
		}
	}
	
	DataPack pack = new DataPack();
	pack.WriteCell((client == 0)? 0:GetClientSerial(client));
	pack.WriteCell(true);

	gH_SQL.Execute(trans, Trans_OnRecalcSuccess, Trans_OnRecalcFail, pack);
	return Plugin_Handled;
}

public void Trans_OnRecalcSuccess(Database db, DataPack data, int numQueries, DBResultSet[] results, any[] queryData)
{
	data.Reset();

	int serial = data.ReadCell();
	int client = (serial == 0) ? 0:GetClientFromSerial(serial);
	bool recalcall = data.ReadCell();
	char sMap[PLATFORM_MAX_PATH];
	if(!recalcall)
	{
		data.ReadString(sMap, sizeof(sMap));
	}

	delete data;

	if(client != 0)
	{
		SetCmdReplySource(SM_REPLY_TO_CONSOLE);
	}

	ReplyToCommand(client, "- Finished recalculating %s points. Recalculating user points, top 100 and user cache.", recalcall ? "all":sMap);

	UpdateAllPoints(true, sMap);
}

public void Trans_OnRecalcFail(Database db, DataPack data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	delete data;
	LogError("Timer (rankings) error! Recalculation failed. Reason: %s (%d / %d)", error, failIndex, numQueries);
}

public void SQL_RecalculateSpecificMap_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null || !results.FetchRow()) 
	{
		LogError("Timer (rankings, recalculate specific map) error! Reason: %s", error);

		return;
	}

	char map[PLATFORM_MAX_PATH];
	results.FetchString(0, map, sizeof(map));
	int iStageCount = results.FetchInt(1);

	Transaction trans = new Transaction();
	char sQuery[1024];

	// Only maintrack times because bonus times aren't tiered.
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %splayertimes SET points = 0 WHERE map = '%s' AND track = 0;", gS_MySQLPrefix, map);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %sstagetimes SET points = 0 WHERE map = '%s';", gS_MySQLPrefix, map);
	AddQueryLog(trans, sQuery);

	for(int i = 0; i < gI_Styles; i++)
	{
		if (!Shavit_GetStyleSettingBool(i, "unranked") && Shavit_GetStyleSettingFloat(i, "rankingmultiplier") != 0.0)
		{
			for (int j = 0; j < TRACKS_SIZE; j++)
			{
				FormatRecalculate(false, j, 0, i, sQuery, sizeof(sQuery), map);
				AddQueryLog(trans, sQuery);
			}

			for (int k = 0; k <= iStageCount; k++)
			{
				FormatRecalculate(false, Track_Main, k, i, sQuery, sizeof(sQuery), map);
				AddQueryLog(trans, sQuery);
			}
		}
	}

	DataPack pack = new DataPack();
	pack.WriteCell(data);
	pack.WriteCell(false);
	pack.WriteString(map);

	gH_SQL.Execute(trans, Trans_OnRecalcSuccess, Trans_OnRecalcFail, pack);
}

void ReallyRecalculateCurrentMap()
{
	#if defined DEBUG
	LogError("DEBUG: 5xxx (ReallyRecalculateCurrentMap)");
	#endif

	Transaction trans1 = new Transaction();
	char sQuery[1024];

	FormatEx(sQuery, sizeof(sQuery), "UPDATE %splayertimes SET points = 0 WHERE map = '%s';", gS_MySQLPrefix, gS_Map);
	AddQueryLog(trans1, sQuery);

	for(int i = 0; i < gI_Styles; i++)
	{
		if (!Shavit_GetStyleSettingBool(i, "unranked") && Shavit_GetStyleSettingFloat(i, "rankingmultiplier") != 0.0)
		{
			for (int j = 0; j < TRACKS_SIZE; j++)
			{
				FormatRecalculate(true, j, 0, i, sQuery, sizeof(sQuery));
				AddQueryLog(trans1, sQuery);
			}
		}
	}

	gH_SQL.Execute(trans1, Trans_OnReallyRecalcSuccess, Trans_OnReallyRecalcFail, 0);

	int iStageCount = Shavit_GetStageCount(Track_Main);

	if(iStageCount > 1)
	{
		Transaction trans2 = new Transaction();
		FormatEx(sQuery, sizeof(sQuery), "UPDATE %sstagetimes SET points = 0 WHERE map = '%s';", gS_MySQLPrefix, gS_Map);
		AddQueryLog(trans2, sQuery);

		for(int i = 0; i < gI_Styles; i++)
		{
			if (!Shavit_GetStyleSettingBool(i, "unranked") && Shavit_GetStyleSettingFloat(i, "rankingmultiplier") != 0.0)
			{
				for (int j = 1; j <= iStageCount; j++)
				{
					FormatRecalculate(true, Track_Main, j, i, sQuery, sizeof(sQuery));
					AddQueryLog(trans2, sQuery);
				}
			}
		}

		gH_SQL.Execute(trans2, Trans_OnReallyRecalcSuccess, Trans_OnReallyRecalcFail, 0);
	}
}

public void Trans_OnReallyRecalcSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	UpdateAllPoints(true, gS_Map);
}

public void Trans_OnReallyRecalcFail(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (rankings) error! ReallyRecalculateCurrentMap failed. Reason: %s", error);
}

public void Shavit_OnFinishStage_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int stage, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
	if (Shavit_GetStyleSettingBool(style, "unranked") || Shavit_GetStyleSettingFloat(style, "rankingmultiplier") == 0.0)
	{
		return;
	}

	if (rank >= 20)
	{
		UpdatePointsForSinglePlayer(client);
		return;
	}

	#if defined DEBUG
	PrintToServer("Recalculating points. (%s, %d, %d)", map, track, style);
	#endif

	char sQuery[1024];
	FormatRecalculate(true, Track_Main, stage, style, sQuery, sizeof(sQuery));

	QueryLog(gH_SQL, SQL_Recalculate_Callback, sQuery, (style << 8) | Track_Main, DBPrio_High);
	UpdateAllPoints(true, gS_Map, Track_Main, stage);
}

public void Shavit_OnFinish_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int track)
{
	if (Shavit_GetStyleSettingBool(style, "unranked") || Shavit_GetStyleSettingFloat(style, "rankingmultiplier") == 0.0)
	{
		return;
	}

	if (rank >= 20)
	{
		UpdatePointsForSinglePlayer(client);
		return;
	}

	#if defined DEBUG
	PrintToServer("Recalculating points. (%s, %d, %d)", map, track, style);
	#endif

	char sQuery[1024];
	FormatRecalculate(true, track, 0, style, sQuery, sizeof(sQuery));	// recal points here

	QueryLog(gH_SQL, SQL_Recalculate_Callback, sQuery, (style << 8) | track, DBPrio_High);
	UpdateAllPoints(true, gS_Map, track);
}

public void SQL_Recalculate_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	int track = data & 0xFF;
	int style = data >> 8;

	if(results == null)
	{
		LogError("Timer (rankings, recalculate map points, %s, style=%d) error! Reason: %s", (track == Track_Main) ? "main" : "bonus", style, error);

		return;
	}

	#if defined DEBUG
	PrintToServer("Recalculated (%s, style=%d).", (track == Track_Main) ? "main_" : "bonus", style);
	#endif
}

void UpdatePointsForSinglePlayer(int client)
{
	int auth = GetSteamAccountID(client);

	char sQuery[1024];

	FormatEx(sQuery, sizeof(sQuery),
		"UPDATE %susers SET points = (SELECT SUM(points) FROM "...
		"(SELECT points, auth FROM %splayertimes UNION ALL SELECT points, auth FROM %sstagetimes) PT WHERE PT.auth = %d) WHERE auth = %d;",
		gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, auth, auth);

	QueryLog(gH_SQL, SQL_UpdateAllPoints_Callback, sQuery, GetClientSerial(client));
}

void UpdateAllPoints(bool recalcall=false, char[] map="", int track=-1, int stage=-1)
{
	#if defined DEBUG
	LogError("DEBUG: 6 (UpdateAllPoints)");
	#endif
	char sQuery[1024];
	char sLastLogin[69];

	if (!recalcall && gCV_LastLoginRecalculate.IntValue > 0)
	{
		FormatEx(sLastLogin, sizeof(sLastLogin), "lastlogin > %d", (GetTime() - gCV_LastLoginRecalculate.IntValue * 60));
	}

	if(!map[0] && track == -1 && stage == -1)
	{
		if (gI_Driver == Driver_sqlite)
		{
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %susers AS U SET points = P.total FROM (SELECT auth, SUM(points) AS total "...
				"FROM (SELECT points, auth FROM %splayertimes UNION ALL SELECT points, auth FROM %sstagetimes) GROUP BY auth) P WHERE U.auth = P.auth %s %s;",
				gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, (sLastLogin[0] != 0) ? "AND " : "", sLastLogin);
		}
		else
		{
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %susers U "...
				"JOIN ( "... 
				"	SELECT auth, SUM(points) AS total "...  
				"	FROM ( "... 
				"		SELECT auth, points FROM %splayertimes "...  
				"		UNION ALL "...
				"		SELECT auth, points FROM %sstagetimes "...
				"	) AS T "...
				"	GROUP BY auth "...
				") AS P ON U.auth = P.auth "... 
				"SET U.points = P.total %s %s;",
			gS_MySQLPrefix, gS_MySQLPrefix, 
			gS_MySQLPrefix, (sLastLogin[0] != 0) ? "WHERE" : "", sLastLogin);
		}		
	}
	else
	{
		char sMapWhere[256], sTrackWhere[64], sTable[512];

		if(stage > 0)
		{
			FormatEx(sTable, sizeof(sTable), "%sstagetimes ts", gS_MySQLPrefix);
			FormatEx(sTrackWhere, sizeof(sTrackWhere), "ts.stage = %d", stage);
		}
		else if (track != -1)
		{
			FormatEx(sTable, sizeof(sTable), "%splayertimes ts", gS_MySQLPrefix);
			FormatEx(sTrackWhere, sizeof(sTrackWhere), "ts.track = %d", track);		
		}
		else
		{
			FormatEx(sTable, sizeof(sTable), "(SELECT map, auth FROM %splayertimes UNION ALL SELECT map, auth FROM %sstagetimes) ts", gS_MySQLPrefix, gS_MySQLPrefix);
		}

		if (map[0])
			FormatEx(sMapWhere, sizeof(sMapWhere), "ts.map = '%s'", map);

		if(gI_Driver == Driver_sqlite)
		{
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %susers AS U SET points = P.total FROM (SELECT auth, SUM(points) AS total "...
				"FROM ( "...
				"SELECT points, auth FROM %splayertimes PT WHERE PT.auth IN (SELECT auth FROM %s WHERE %s %s %s ) "... 
				"UNION ALL "... 
				"SELECT points, auth FROM %sstagetimes ST WHERE ST.auth IN (SELECT auth FROM %s WHERE %s %s %s ) "...
				") GROUP BY auth) P "...
				"WHERE U.auth = P.auth %s %s;",
				gS_MySQLPrefix, 
				gS_MySQLPrefix, sTable, sMapWhere, (sMapWhere[0] && sTrackWhere[0]) ? "AND":"", sTrackWhere,
				gS_MySQLPrefix, sTable, sMapWhere, (sMapWhere[0] && sTrackWhere[0]) ? "AND":"", sTrackWhere,
				(sLastLogin[0] != 0) ? "AND " : "", sLastLogin);
		}
		else
		{
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %susers U "...
				"JOIN ( "... 
				"	SELECT auth, SUM(points) AS total "...  
				"	FROM ( "... 
				"		SELECT auth, points FROM %splayertimes PT WHERE PT.auth IN (SELECT auth FROM %s WHERE %s %s %s ) "...  
				"		UNION ALL "...
				"		SELECT auth, points FROM %sstagetimes ST WHERE ST.auth IN (SELECT auth FROM %s WHERE %s %s %s ) "...
				"	) AS T "...
				"	GROUP BY auth "...
				") AS P ON U.auth = P.auth "... 
				"SET U.points = P.total %s %s;",
			gS_MySQLPrefix, 
			gS_MySQLPrefix, sTable, sMapWhere, (sMapWhere[0] && sTrackWhere[0]) ? "AND":"", sTrackWhere,
			gS_MySQLPrefix, sTable, sMapWhere, (sMapWhere[0] && sTrackWhere[0]) ? "AND":"", sTrackWhere,
			(sLastLogin[0] != 0) ? "WHERE" : "", sLastLogin);			
		}
	}

	QueryLog(gH_SQL, SQL_UpdateAllPoints_Callback, sQuery);
}

public void SQL_UpdateAllPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update all points) error! Reason: %s", error);

		return;
	}

	UpdateTop100();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsClientAuthorized(i))
		{
			UpdatePlayerRank(i, false);
		}
	}
}

void UpdatePlayerRank(int client, bool first)
{
	int iSteamID = 0;

	if((iSteamID = GetSteamAccountID(client)) != 0)
	{
		// if there's any issue with this query,
		// add "ORDER BY points DESC " before "LIMIT 1"
		char sQuery[512];
		FormatEx(sQuery, 512, "SELECT u2.points, COUNT(*) FROM %susers u1 JOIN (SELECT points FROM %susers WHERE auth = %d) u2 WHERE u1.points >= u2.points;",
			gS_MySQLPrefix, gS_MySQLPrefix, iSteamID);

		DataPack hPack = new DataPack();
		hPack.WriteCell(GetClientSerial(client));
		hPack.WriteCell(first);

		QueryLog(gH_SQL, SQL_UpdatePlayerRank_Callback, sQuery, hPack, DBPrio_Low);
	}
}

public void SQL_UpdatePlayerRank_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack hPack = view_as<DataPack>(data);
	hPack.Reset();

	int iSerial = hPack.ReadCell();
	bool bFirst = view_as<bool>(hPack.ReadCell());
	delete hPack;

	if(results == null)
	{
		LogError("Timer (rankings, update player rank) error! Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(iSerial);

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		gA_Rankings[client].fPoints = results.FetchFloat(0);
		gA_Rankings[client].iRank = (gA_Rankings[client].fPoints > 0.0)? results.FetchInt(1):0;

		Call_StartForward(gH_Forwards_OnRankAssigned);
		Call_PushCell(client);
		Call_PushCell(gA_Rankings[client].iRank);
		Call_PushCell(gA_Rankings[client].fPoints);
		Call_PushCell(bFirst);
		Call_Finish();
	}
}

void UpdateTop100()
{
	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery),
		"SELECT * FROM (SELECT COUNT(*) as c, 0 as auth, '' as name, 0 as p FROM %susers WHERE points > 0) a \
		UNION ALL \
		SELECT * FROM (SELECT -1 as c, auth, name, points FROM %susers WHERE points > 0 ORDER BY points DESC LIMIT 100) b;",
		gS_MySQLPrefix, gS_MySQLPrefix);

	QueryLog(gH_SQL, SQL_UpdateTop100_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_UpdateTop100_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update top 100) error! Reason: %s", error);

		return;
	}

	if (!results.FetchRow())
	{
		LogError("Timer (rankings, update top 100 b) error! Reason: failed to fetch first row");
		return;
	}

	gI_RankedPlayers = results.FetchInt(0);

	delete gH_Top100Menu;
	gH_Top100Menu = new Menu(MenuHandler_Top);

	int row = 0;

	while(results.FetchRow())
	{
		char sSteamID[32];
		results.FetchString(1, sSteamID, 32);

		char sName[32+1];
		results.FetchString(2, sName, sizeof(sName));

		float fPoints;
		fPoints = results.FetchFloat(3);

		char sDisplay[96];
		FormatEx(sDisplay, 96, "#%d - %s (%.3f)", (++row), sName, fPoints);
		gH_Top100Menu.AddItem(sSteamID, sDisplay);
	}

	if(gH_Top100Menu.ItemCount == 0)
	{
		char sDisplay[64];
		FormatEx(sDisplay, 64, "%t", "NoRankedPlayers");
		gH_Top100Menu.AddItem("-1", sDisplay);
	}

	gH_Top100Menu.ExitButton = true;
}

bool DoWeHaveWindowFunctions(const char[] sVersion)
{
	char buf[100][2];
	ExplodeString(sVersion, ".", buf, 2, 100);
	int iMajor = StringToInt(buf[0]);
	int iMinor = StringToInt(buf[1]);

	if (gI_Driver == Driver_sqlite)
	{
		// 2018~
		return iMajor > 3 || (iMajor == 3 && iMinor >= 25); 
	}
	else if (gI_Driver == Driver_pgsql)
	{
		// 2009~
		return iMajor > 8 || (iMajor == 8 && iMinor >= 4);
	}
	else if (gI_Driver == Driver_mysql)
	{
		if (StrContains(sVersion, "MariaDB") != -1)
		{
			// 2016~
			return iMajor > 10 || (iMajor == 10 && iMinor >= 2);
		}
		else // mysql then...
		{
			// 2018~
			return iMajor > 8 || (iMajor == 8 && iMinor >= 0);
		}
	}

	return false;
}

public void SQL_Version_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null || !results.FetchRow())
	{
		LogError("Timer (rankings) error! Failed to retrieve VERSION(). Reason: %s", error);
	}
	else
	{
		char sVersion[100];
		results.FetchString(0, sVersion, sizeof(sVersion));
		gB_SQLWindowFunctions = DoWeHaveWindowFunctions(sVersion);

		if (gI_Driver == Driver_sqlite)
		{
			gB_SqliteHatesPOW = results.FetchInt(1) == 0;
		}
	}

	if (!gB_SQLWindowFunctions)
	{
		if (gI_Driver == Driver_sqlite)
		{
			SetFailState("sqlite version not supported. Try using db.sqlite.ext from Sourcemod 1.12 or higher.");
		}
		else if (gI_Driver == Driver_pgsql)
		{
			LogError("Okay, really? Your postgres version is from 2014 or earlier... come on, brother...");
			SetFailState("Update postgresql: window function required.");
		}
		else // mysql
		{
			SetFailState("Update mysql: window function required.");
			// Mysql 5.7 is a cancer upon society. EOS is Oct 2023!! Unbelievable.
			// Please update your servers already, nfoservers.
			// CreateGetWeightedPointsFunction();
		}
	}
	else if (gI_Driver == Driver_mysql)
	{
		QueryLog(gH_SQL, SQL_DisableFullGroupBy_Callback, "SET @@sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';", 0, DBPrio_High);
	}

	char sWRHolderRankTrackQueryYuck[] =
		"%s %s%s AS \
			SELECT \
			0 as wrrank, \
			style, auth, COUNT(auth) as wrcount \
			FROM %swrs WHERE track %c 0 GROUP BY style, auth;";

	char sWRHolderRankTrackQueryRANK[] =
		"%s %s%s AS \
			SELECT \
				RANK() OVER(PARTITION BY style ORDER BY COUNT(auth) DESC, auth ASC) \
			as wrrank, \
			style, auth, COUNT(auth) as wrcount \
			FROM %swrs WHERE track %c 0 GROUP BY style, auth;";

	char sStageWRHolderRankTrackQueryYuck[] =
			"%s %s%s AS \
			SELECT \
			0 as wrrank, \
			style, auth, COUNT(auth) as wrcount \
			FROM %sstagewrs WHERE GROUP BY style, auth;";

	char sStageWRHolderRankTrackQueryRANK[] =
		"%s %s%s AS \
			SELECT \
				RANK() OVER(PARTITION BY style ORDER BY COUNT(auth) DESC, auth ASC) \
			as wrrank, \
			style, auth, COUNT(auth) as wrcount \
			FROM %sstagewrs GROUP BY style, auth;";

	char sWRHolderRankOtherQueryYuck[] =
		"%s %s%s AS \
			SELECT \
			0 as wrrank, \
			-1 as style, auth, COUNT(*) \
			FROM %swrs %s %s %s %s GROUP BY auth;";

	char sWRHolderRankOtherQueryRANK[] =
		"%s %s%s AS \
			SELECT \
				RANK() OVER(ORDER BY COUNT(auth) DESC, auth ASC) \
			as wrrank, \
			-1 as style, auth, COUNT(*) as wrcount \
			FROM %swrs %s %s %s %s GROUP BY auth;";

	char sCreateMapInfoView[] = 
		"%s %smapinfo AS \
			SELECT \
				MT.map, \
				MT.tier, \
				MT.maxvelocity, \
				COUNT(DISTINCT CASE WHEN MZ.type = 0 AND MZ.track > 0 THEN MZ.track END) AS bonuses, \
				COALESCE(MAX(CASE WHEN MZ.type = 3 THEN MZ.data END), \
						CASE WHEN MAX(CASE WHEN MZ.type = 2 THEN 1 END) = 1 THEN MAX(MZ.data) \
						ELSE 0 END) AS stages, \
				MAX(CASE WHEN MZ.type = 2 THEN 1 ELSE 0 END) AS maptype \
			FROM %smaptiers MT \
			LEFT JOIN %smapzones MZ ON MT.map = MZ.map \
			GROUP BY MT.map, MT.tier, MT.maxvelocity \
			ORDER BY MT.map ASC;";

	char sQuery[800];
	Transaction trans = new Transaction();

	if (gI_Driver == Driver_sqlite)
	{
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankmain;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankbonus;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankstages;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankall;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankcvar;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %smapinfo;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
	}

	FormatEx(sQuery, sizeof(sQuery), sCreateMapInfoView,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix);
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankTrackQueryYuck : sWRHolderRankTrackQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankmain", gS_MySQLPrefix, '=');
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sStageWRHolderRankTrackQueryYuck : sStageWRHolderRankTrackQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankstages", gS_MySQLPrefix);
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankTrackQueryYuck : sWRHolderRankTrackQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankbonus", gS_MySQLPrefix, '>');
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankOtherQueryYuck : sWRHolderRankOtherQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankall", gS_MySQLPrefix, "", "", "", "");
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankOtherQueryYuck : sWRHolderRankOtherQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankcvar", gS_MySQLPrefix,
		(gCV_MVPRankOnes.IntValue == 2 || gCV_MVPRankOnes_Main.BoolValue) ? "WHERE" : "",
		(gCV_MVPRankOnes.IntValue == 2)  ? "style = 0" : "",
		(gCV_MVPRankOnes.IntValue == 2 && gCV_MVPRankOnes_Main.BoolValue) ? "AND" : "",
		(gCV_MVPRankOnes_Main.BoolValue) ? "track = 0" : "");
	AddQueryLog(trans, sQuery);

	gH_SQL.Execute(trans, Trans_WRHolderRankTablesSuccess, Trans_WRHolderRankTablesError, 0, DBPrio_High);
}

public void Trans_WRHolderRankTablesSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	gB_WRHolderTablesMade = true;

	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientAuthorized(i))
		{
			UpdateWRs(i);
		}
	}

	RefreshWRHolders();
}

public void SQL_DisableFullGroupBy_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, disable full_group_by) error! Reason: %s", error);

		return;
	}
}

void RefreshWRHolders()
{
	if (gB_WRHoldersRefreshedTimer)
	{
		return;
	}

	gB_WRHoldersRefreshedTimer = true;
	CreateTimer(10.0, Timer_RefreshWRHolders, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RefreshWRHolders(Handle timer, any data)
{
	RefreshWRHoldersActually();
	return Plugin_Stop;
}

void RefreshWRHoldersActually()
{
	char sQuery[1024];

	if (gCV_MVPRankOnes_Slow.BoolValue)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"     SELECT 0 as type, 0 as track, style, COUNT(DISTINCT auth) FROM %swrhrankmain GROUP BY style \
			UNION SELECT 0 as type, 1 as track, style, COUNT(DISTINCT auth) FROM %swrhrankbonus GROUP BY style \
			UNION SELECT 1 as type, -1 as track, -1 as style, COUNT(DISTINCT auth) FROM %swrhrankall \
			UNION SELECT 2 as type, -1 as track, -1 as style, COUNT(DISTINCT auth) FROM %swrhrankcvar;",
			gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"SELECT 2 as type, -1 as track, -1 as style, COUNT(DISTINCT auth) FROM %swrs %s %s %s %s;",
			gS_MySQLPrefix,
			(gCV_MVPRankOnes.IntValue == 2 || gCV_MVPRankOnes_Main.BoolValue) ? "WHERE" : "",
			(gCV_MVPRankOnes.IntValue == 2)  ? "style = 0" : "",
			(gCV_MVPRankOnes.IntValue == 2 && gCV_MVPRankOnes_Main.BoolValue) ? "AND" : "",
			(gCV_MVPRankOnes_Main.BoolValue) ? "track = 0" : ""
		);
	}

	QueryLog(gH_SQL, SQL_GetWRHolders_Callback, sQuery);

	gB_WRHoldersRefreshed = true;
}

public void Trans_WRHolderRankTablesError(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (WR Holder Rank table creation %d/%d) SQL query failed. Reason: %s", failIndex, numQueries, error);
}

public void SQL_GetWRHolders_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (get WR Holder amount) SQL query failed. Reason: %s", error);

		return;
	}

	while (results.FetchRow())
	{
		int type  = results.FetchInt(0);
		int track = results.FetchInt(1);
		int style = results.FetchInt(2);
		int total = results.FetchInt(3);

		if (type == 0)
		{
			gI_WRHolders[track][style] = total;
		}
		else if (type == 1)
		{
			gI_WRHoldersAll = total;
		}
		else if (type == 2)
		{
			gI_WRHoldersCvar = total;
		}
	}
}

public int Native_GetWRCount(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);
	int style = GetNativeCell(3);
	bool usecvars = view_as<bool>(GetNativeCell(4));

	if (usecvars)
	{
		return gA_Rankings[client].iWRAmountCvar;
	}
	else if (track == -1 && style == -1)
	{
		return gA_Rankings[client].iWRAmountAll;
	}

	if (track > Track_Bonus)
	{
		track = Track_Bonus;
	}

	return gA_Rankings[client].iWRAmount[STYLE_LIMIT*track + style];
}

public int Native_GetWRHolders(Handle handler, int numParams)
{
	int track = GetNativeCell(1);
	int style = GetNativeCell(2);
	bool usecvars = view_as<bool>(GetNativeCell(3));

	if (usecvars)
	{
		return gI_WRHoldersCvar;
	}
	else if (track == -1 && style == -1)
	{
		return gI_WRHoldersAll;
	}

	if (track > Track_Bonus)
	{
		track = Track_Bonus;
	}

	return gI_WRHolders[track][style];
}

public int Native_GetWRHolderRank(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);
	int style = GetNativeCell(3);
	bool usecvars = view_as<bool>(GetNativeCell(4));

	if (usecvars)
	{
		return gA_Rankings[client].iWRHolderRankCvar;
	}
	else if (track == -1 && style == -1)
	{
		return gA_Rankings[client].iWRHolderRankAll;
	}

	if (track > Track_Bonus)
	{
		track = Track_Bonus;
	}

	return gA_Rankings[client].iWRHolderRank[STYLE_LIMIT*track + style];
}

public int Native_GetMapTier(Handle handler, int numParams)
{
	char sMap[PLATFORM_MAX_PATH];
	GetNativeString(1, sMap, sizeof(sMap));

	if (!sMap[0])
	{
		return gI_Tier;
	}

	mapinfo_t mapinfo;

	if(!gA_MapInfo.GetArray(sMap, mapinfo, sizeof(mapinfo_t)))
	{
		return 0;
	}

	return mapinfo.iTier;
}

public int Native_GetMapInfo(Handle handler, int numParams)
{
	return view_as<int>(CloneHandle(gA_MapInfo, handler));
}

public int Native_GetPoints(Handle handler, int numParams)
{
	return view_as<int>(gA_Rankings[GetNativeCell(1)].fPoints);
}

public int Native_GetRank(Handle handler, int numParams)
{
	return gA_Rankings[GetNativeCell(1)].iRank;
}

public int Native_GetRankedPlayers(Handle handler, int numParams)
{
	return gI_RankedPlayers;
}

public int Native_Rankings_DeleteMap(Handle handler, int numParams)
{
	char sMap[PLATFORM_MAX_PATH];
	GetNativeString(1, sMap, sizeof(sMap));
	LowercaseString(sMap);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM %smaptiers WHERE map = '%s';", gS_MySQLPrefix, sMap);
	QueryLog(gH_SQL, SQL_DeleteMap_Callback, sQuery, StrEqual(gS_Map, sMap, false), DBPrio_High);
	return 1;
}

public int Native_GuessPointsForTime(Handle plugin, int numParams)
{
	int track = GetNativeCell(1);
	int stage = GetNativeCell(2);
	int style = GetNativeCell(3);
	int rank = GetNativeCell(4);
	int tier = GetNativeCell(5);
	int count = GetNativeCell(6);

	float ppoints = Sourcepawn_GetRecordPoints(
		track,
		stage,
		rank,
		Shavit_GetStyleSettingFloat(style, "rankingmultiplier"),
		float(tier == -1 ? gI_Tier : tier),
		count
	);

	return view_as<int>(ppoints);
}

float Sourcepawn_GetRecordPoints(int track, int stage, int rank, float stylemultiplier, float tier, int count)
{
	if(stylemultiplier == 0.0)
	{
		return 0.0;
	}

	float fMaxRankPoint;
	float fBaiscFinishPoint;
	float fExtraFinishPoint = 0.0;
	float fCount = float(count);

	if(track >= Track_Bonus) // bonus
	{
		tier = 1.0;
		fMaxRankPoint = min(gCV_MaxRankPoints_Bonus.FloatValue, gCV_BasicRankPoints_Bonus.FloatValue + fCount / 2.0);
		fBaiscFinishPoint = gCV_BasicFinishPoints_Bonus.FloatValue;
	}
	else if(stage == 0) // main
	{
		fMaxRankPoint = min(gCV_MaxRankPoints_Main.FloatValue, gCV_BasicRankPoints_Main.FloatValue + fCount * (Pow(tier, 2.0) / max(9.0-tier, 1.0)));
		fBaiscFinishPoint = gCV_BasicFinishPoints_Main.FloatValue;
		fExtraFinishPoint = tier * Pow(max(0.0, tier-gCV_ExtraFinishPointsMulitiplier.FloatValue), 2.0) * fBaiscFinishPoint;
	}
	else // stage
	{
		fMaxRankPoint = min(gCV_MaxRankPoints_Stage.FloatValue, gCV_BasicRankPoints_Stage.FloatValue + fCount * (Pow(tier, 2.0) / max(16.0-tier, 1.0)));
		fBaiscFinishPoint = gCV_BasicFinishPoints_Stage.FloatValue == 0.0 ? tier : gCV_BasicFinishPoints_Stage.FloatValue;
	}

	float fRankPoint = fMaxRankPoint / float(rank);
	float fFinishPoint = fBaiscFinishPoint * tier;

	float fTotalPoint = fRankPoint + (fFinishPoint + fExtraFinishPoint) * stylemultiplier;

	return fTotalPoint;
}

public void SQL_DeleteMap_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings deletemap) SQL query failed. Reason: %s", error);

		return;
	}

	if(view_as<bool>(data))
	{
		gI_Tier = gCV_DefaultTier.IntValue;

		UpdateAllPoints(true);
	}
}

stock float max(float a, float b)
{
	return a > b ? a:b;
}

stock float min(float a, float b)
{
	return a < b ? a:b;
}