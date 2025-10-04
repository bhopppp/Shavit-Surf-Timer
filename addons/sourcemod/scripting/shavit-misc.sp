/*
 * shavit's Timer - Miscellaneous
 * by: shavit, Technoblazed, strafe, EvanIMK, Nickelony, rtldg, ofirgall
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
 *
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

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <convar_class>
#include <dhooks>

#undef REQUIRE_EXTENSIONS
#include <SteamWorks>
#include <cstrike>
#include <tf2>
#include <tf2_stocks>

#include <shavit/core>
#include <shavit/misc>

#undef REQUIRE_PLUGIN
#include <shavit/chat>
#include <shavit/checkpoints>
#include <shavit/rankings>
#include <shavit/replay-playback>
#include <shavit/wr>
#include <shavit/zones>
#include <eventqueuefix>

#include <shavit/weapon-stocks>

#pragma newdecls required
#pragma semicolon 1

#define DEBUG 0

typedef StopTimerCallback = function void (int data);

// game specific
EngineVersion gEV_Type = Engine_Unknown;

char gS_RadioCommands[][] = { "coverme", "takepoint", "holdpos", "regroup", "followme", "takingfire", "go", "fallback", "sticktog",
	"getinpos", "stormfront", "report", "roger", "enemyspot", "needbackup", "sectorclear", "inposition", "reportingin",
	"getout", "negative", "enemydown", "compliment", "thanks", "cheer", "go_a", "go_b", "sorry", "needrop", "playerradio", "playerchatwheel", "player_ping", "chatwheel_ping" };

bool gB_Hide[MAXPLAYERS+1];
bool gB_AutoRestart[MAXPLAYERS+1];
bool gB_Late = false;
bool gB_DisableTriggers[MAXPLAYERS+1];
int gI_LastShot[MAXPLAYERS+1];
ArrayList gA_Advertisements = null;
int gI_AdvertisementsCycle = 0;
char gS_Map[PLATFORM_MAX_PATH];
int gI_Style[MAXPLAYERS+1];
Function gH_AfterWarningMenu[MAXPLAYERS+1];
int gI_LastWeaponTick[MAXPLAYERS+1];
int gI_LastNoclipTick[MAXPLAYERS+1];
int gI_LastStopInfo[MAXPLAYERS+1];

// cookies
Handle gH_HideCookie = null;
Handle gH_AutoRestartCookie = null;

// floats
float gF_PauseOrigin[MAXPLAYERS+1][3];
float gF_PauseAngles[MAXPLAYERS+1][3];
float gF_PauseVelocity[MAXPLAYERS+1][3];

// cvars
Convar gCV_GodMode = null;
Convar gCV_HideTeamChanges = null;
Convar gCV_RespawnOnTeam = null;
Convar gCV_RespawnOnRestart = null;
Convar gCV_StartOnSpawn = null;
Convar gCV_HideRadar = null;
Convar gCV_TeleportCommands = null;
Convar gCV_NoWeaponDrops = null;
Convar gCV_NoBlock = null;
Convar gCV_NoBlood = null;
Convar gCV_AutoRespawn = null;
Convar gCV_CreateSpawnPoints = null;
Convar gCV_DisableRadio = null;
Convar gCV_Scoreboard = null;
Convar gCV_WeaponCommands = null;
Convar gCV_PlayerOpacity = null;
Convar gCV_StaticPrestrafe = null;
Convar gCV_NoclipMe = null;
Convar gCV_AdvertisementInterval = null;
Convar gCV_RemoveRagdolls = null;
Convar gCV_ClanTag = null;
Convar gCV_DropAll = null;
Convar gCV_JointeamHook = null;
Convar gCV_SpectatorList = null;
Convar gCV_HideChatCommands = null;
Convar gCV_StopTimerWarning = null;
Convar gCV_WRMessages = null;
Convar gCV_BhopSounds = null;
Convar gCV_RestrictNoclip = null;
Convar gCV_SpecScoreboardOrder = null;
Convar gCV_BadSetLocalAnglesFix = null;

// external cvars
ConVar sv_cheats = null;
ConVar sv_disable_immunity_alpha = null;
ConVar mp_humanteam = null;
ConVar hostname = null;
ConVar hostport = null;
ConVar sv_disable_radar = null;
ConVar tf_dropped_weapon_lifetime = null;

// forwards
Handle gH_Forwards_OnClanTagChangePre = null;
Handle gH_Forwards_OnClanTagChangePost = null;

// dhooks
DynamicHook gH_GetPlayerMaxSpeed = null;
DynamicHook gH_IsSpawnPointValid = null;
DynamicDetour gH_CalcPlayerScore = null;

// modules
bool gB_Checkpoints = false;
bool gB_Eventqueuefix = false;
bool gB_Rankings = false;
bool gB_ReplayPlayback = false;
bool gB_Chat = false;
bool gB_Zones = false;

// timer settings
stylestrings_t gS_StyleStrings[STYLE_LIMIT];

// chat settings
chatstrings_t gS_ChatStrings;

public Plugin myinfo =
{
	name = "[shavit-surf] Miscellaneous",
	author = "shavit, Technoblazed, strafe, EvanIMK, Nickelony, rtldg, ofirgall, *Surf integration version modified by KikI",
	description = "Miscellaneous features for shavit surf timer. (This plugin is base on shavit's bhop timer)",
	version = SHAVIT_SURF_VERSION,
	url = "https://github.com/shavitush/bhoptimer  https://github.com/bhopppp/Shavit-Surf-Timer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_IsClientUsingHide", Native_IsClientUsingHide);

	RegPluginLibrary("shavit-misc");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// forwards
	gH_Forwards_OnClanTagChangePre = CreateGlobalForward("Shavit_OnClanTagChangePre", ET_Event, Param_Cell, Param_String, Param_Cell);
	gH_Forwards_OnClanTagChangePost = CreateGlobalForward("Shavit_OnClanTagChangePost", ET_Event, Param_Cell, Param_String, Param_Cell);

	// cache
	gEV_Type = GetEngineVersion();

	sv_cheats = FindConVar("sv_cheats");
	sv_disable_immunity_alpha = FindConVar("sv_disable_immunity_alpha");

	RegAdminCmd("sm_maptimer_checkpoints", Command_MaptimerCheckpoints, ADMFLAG_RCON, "kz_bhop_yonkoma");

	RegAdminCmd("sm_toggletriggers", Command_ToggleTriggers, ADMFLAG_RCON, "Disable triggers for a client");
	RegAdminCmd("sm_triggers", Command_ToggleTriggers, ADMFLAG_RCON, "Disable triggers for a client");
	RegAdminCmd("sm_disabletriggers", Command_ToggleTriggers, ADMFLAG_RCON, "Disable triggers for a client");

	// spectator list
	RegConsoleCmd("sm_specs", Command_Specs, "Show a list of spectators.");
	RegConsoleCmd("sm_spectators", Command_Specs, "Show a list of spectators.");

	// spec
	RegConsoleCmd("sm_spec", Command_Spec, "Moves you to the spectators' team. Usage: sm_spec [target]");
	RegConsoleCmd("sm_spectate", Command_Spec, "Moves you to the spectators' team. Usage: sm_spectate [target]");

	// hide
	RegConsoleCmd("sm_hide", Command_Hide, "Toggle players' hiding.");
	RegConsoleCmd("sm_unhide", Command_Hide, "Toggle players' hiding.");
	gH_HideCookie = RegClientCookie("shavit_hide", "Hide settings", CookieAccess_Protected);

	// tpto
	RegConsoleCmd("sm_tpto", Command_Teleport, "Teleport to another player. Usage: sm_tpto [target]");
	RegConsoleCmd("sm_goto", Command_Teleport, "Teleport to another player. Usage: sm_goto [target]");

	// weapons
	RegConsoleCmd("sm_usp", Command_Weapon, "Spawn a USP.");
	RegConsoleCmd("sm_glock", Command_Weapon, "Spawn a Glock.");
	RegConsoleCmd("sm_knife", Command_Weapon, "Spawn a knife.");

	// noclip
	RegConsoleCmd("sm_prac", Command_Noclip, "Toggles noclip. (sm_nc alias)");
	RegConsoleCmd("sm_practice", Command_Noclip, "Toggles noclip. (sm_nc alias)");
	RegConsoleCmd("sm_nc", Command_Noclip, "Toggles noclip.");
	RegConsoleCmd("sm_noclipme", Command_Noclip, "Toggles noclip. (sm_nc alias)");

	RegConsoleCmd("sm_help", Command_Help, "Shows command menu to client.");

	// qol
	RegConsoleCmd("sm_autorestart", Command_AutoRestart, "Toggles auto-restart.");
	RegConsoleCmd("sm_autoreset", Command_AutoRestart, "Toggles auto-restart.");
	gH_AutoRestartCookie = RegClientCookie("shavit_autorestart", "Auto-restart settings", CookieAccess_Protected);

	AddCommandListener(CommandListener_Noclip, "+noclip");
	AddCommandListener(CommandListener_Noclip, "-noclip");
	// Hijack sourcemod's sm_noclip from funcommands to work when no args are specified.
	AddCommandListener(CommandListener_funcommands_Noclip, "sm_noclip");
	AddCommandListener(CommandListener_Real_Noclip, "noclip");

	// hook teamjoins
	AddCommandListener(Command_Jointeam, "jointeam");
	AddCommandListener(Command_Spectate, "spectate");

	// gCV_SpecScoreboardOrder stuff
	AddCommandListener(Command_SpecNextPrev, "spec_next");
	AddCommandListener(Command_SpecNextPrev, "spec_prev");

	// hook radio commands instead of a global listener
	for(int i = 0; i < sizeof(gS_RadioCommands); i++)
	{
		AddCommandListener(Command_Radio, gS_RadioCommands[i]);
	}

	// hooks
	HookEvent("player_spawn", Player_Spawn);
	HookEvent("player_team", Player_Notifications, EventHookMode_Pre);
	HookEvent("player_death", Player_Notifications, EventHookMode_Pre);
	HookEventEx("weapon_fire", Weapon_Fire);
	HookEventEx("weapon_fire_on_empty", Weapon_Fire);
	HookEventEx("weapon_reload", Weapon_Fire);
	AddCommandListener(Command_Drop, "drop");
	AddTempEntHook("EffectDispatch", EffectDispatch);
	AddTempEntHook("World Decal", WorldDecal);
	AddTempEntHook((gEV_Type != Engine_TF2)? "Shotgun Shot":"Fire Bullets", Shotgun_Shot);
	AddNormalSoundHook(NormalSound);

	// phrases
	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-misc.phrases");

	// advertisements
	gA_Advertisements = new ArrayList(ByteCountToCells(300));
	hostname = FindConVar("hostname");
	hostport = FindConVar("hostport");

	RegConsoleCmd("sm_adverts", Command_PrintAdverts, "Prints all the adverts to your chat");

	// cvars and stuff
	gCV_GodMode = new Convar("shavit_misc_godmode", "3", "Enable godmode for players?\n0 - Disabled\n1 - Only prevent fall/world damage.\n2 - Only prevent damage from other players.\n3 - Full godmode.", 0, true, 0.0, true, 3.0);
	gCV_HideTeamChanges = new Convar("shavit_misc_hideteamchanges", "1", "Hide team changes in chat?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnTeam = new Convar("shavit_misc_respawnonteam", "1", "Respawn whenever a player joins a team?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnRestart = new Convar("shavit_misc_respawnonrestart", "1", "Respawn a dead player if they use the timer restart command?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_StartOnSpawn = new Convar("shavit_misc_startonspawn", "1", "Restart the timer for a player after they spawn?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_HideRadar = new Convar("shavit_misc_hideradar", "1", "Should the plugin hide the in-game radar?", 0, true, 0.0, true, 1.0);
	gCV_TeleportCommands = new Convar("shavit_misc_tpcmds", "1", "Enable teleport-related commands? (sm_goto/sm_tpto)\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoWeaponDrops = new Convar("shavit_misc_noweapondrops", "1", "Remove every dropped weapon.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoBlock = new Convar("shavit_misc_noblock", "1", "Disable player collision?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoBlood = new Convar("shavit_misc_noblood", "1", "Hide blood decals and particles?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_AutoRespawn = new Convar("shavit_misc_autorespawn", "1.5", "Seconds to wait before respawning player?\n0 - Disabled", 0, true, 0.0, true, 10.0);
	gCV_CreateSpawnPoints = new Convar("shavit_misc_createspawnpoints", "6", "Amount of spawn points to add for each team.\n0 - Disabled", 0, true, 0.0, true, 32.0);
	gCV_DisableRadio = new Convar("shavit_misc_disableradio", "1", "Block radio commands.\n0 - Disabled (radio commands work)\n1 - Enabled (radio commands are blocked)", 0, true, 0.0, true, 1.0);
	gCV_Scoreboard = new Convar("shavit_misc_scoreboard", "1", "Manipulate scoreboard so score is -{time} and deaths are {rank})?\nDeaths part requires shavit-rankings.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_WeaponCommands = new Convar("shavit_misc_weaponcommands", "5", "Enable sm_usp, sm_glock, sm_knife, and infinite ammo?\n0 - Disabled\n1 - Enabled\n2 - Also give infinite reserve ammo for USP & Glocks.\n3 - Also give infinite clip ammo for USP & Glocks.\n4 - Also give infinite reserve for all weapons (and grenades).\n5 - Also give infinite clip ammo for all weapons (and grenades).", 0, true, 0.0, true, 5.0);
	gCV_PlayerOpacity = new Convar("shavit_misc_playeropacity", "69", "Player opacity (alpha) to set on spawn.\n-1 - Disabled\nValue can go up to 255. 0 for invisibility.", 0, true, -1.0, true, 255.0);
	gCV_StaticPrestrafe = new Convar("shavit_misc_staticprestrafe", "1", "Force prestrafe for every pistol.\n250 is the default value and some styles will have 260.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoclipMe = new Convar("shavit_misc_noclipme", "1", "Allow +noclip, sm_p and all the noclip commands?\n0 - Disabled\n1 - Enabled\n2 - requires 'admin_noclipme' override or ADMFLAG_CHEATS flag.", 0, true, 0.0, true, 2.0);
	gCV_AdvertisementInterval = new Convar("shavit_misc_advertisementinterval", "600.0", "Interval between each chat advertisement.\nConfiguration file for those is configs/shavit-advertisements.cfg.\nSet to 0.0 to disable.\nRequires server restart for changes to take effect.", 0, true, 0.0);
	gCV_RemoveRagdolls = new Convar("shavit_misc_removeragdolls", "1", "Remove ragdolls after death?\n0 - Disabled\n1 - Only remove replay bot ragdolls.\n2 - Remove all ragdolls.", 0, true, 0.0, true, 2.0);
	gCV_ClanTag = new Convar("shavit_misc_clantag", "{tr}{styletag} :: {time}", "Custom clantag for players.\n0 - Disabled\n{styletag} - style tag.\n{style} - style name.\n{time} - formatted time.\n{tr} - first letter of track.\n{rank} - player rank.\n{cr} - player's chatrank from shavit-chat, trimmed, with no colors", 0);
	gCV_DropAll = new Convar("shavit_misc_dropall", "1", "Allow all weapons to be dropped?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_JointeamHook = new Convar("shavit_misc_jointeamhook", "1", "Hook `jointeam`?\n0 - Disabled\n1 - Enabled, players can instantly change teams.", 0, true, 0.0, true, 1.0);
	gCV_SpectatorList = new Convar("shavit_misc_speclist", "1", "Who to show in !specs?\n0 - everyone\n1 - all admins (admin_speclisthide override to bypass)\n2 - players you can target", 0, true, 0.0, true, 2.0);
	gCV_HideChatCommands = new Convar("shavit_misc_hidechatcmds", "1", "Hide commands from chat?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_StopTimerWarning = new Convar("shavit_misc_stoptimerwarning", "180", "Time in seconds to display a warning before stopping the timer with noclip or !stop.\n0 - Disabled");
	gCV_WRMessages = new Convar("shavit_misc_wrmessages", "1", "How many messages to print when break a WR?\n0 - Disabled", 0,  true, 0.0, true, 100.0);
	gCV_BhopSounds = new Convar("shavit_misc_bhopsounds", "1", "Should bhop (landing and jumping) sounds be muted?\n1 - Blocked while !hide is enabled\n2 - Always blocked", 0,  true, 1.0, true, 2.0);
	gCV_RestrictNoclip = new Convar("shavit_misc_restrictnoclip", "0", "Should noclip be be restricted\n0 - Disabled\n1 - No vertical velocity while in noclip in start zone\n2 - No noclip in start zone", 0, true, 0.0, true, 2.0);
	gCV_SpecScoreboardOrder = new Convar("shavit_misc_spec_scoreboard_order", "1", "Use scoreboard ordering for players when changing target when spectating.", 0, true, 0.0, true, 1.0);

	if (gEV_Type != Engine_CSGO)
	{
		gCV_BadSetLocalAnglesFix = new Convar("shavit_misc_bad_setlocalangles_fix", "1", "Fix 'Bad SetLocalAngles' on func_rotating entities.", 0, true, 0.0, true, 1.0);
	}

	gCV_HideRadar.AddChangeHook(OnConVarChanged);
	gCV_NoWeaponDrops.AddChangeHook(OnConVarChanged);
	Convar.AutoExecConfig();

	mp_humanteam = FindConVar((gEV_Type == Engine_TF2) ? "mp_humans_must_join_team" : "mp_humanteam");
	sv_disable_radar = FindConVar("sv_disable_radar");
	tf_dropped_weapon_lifetime = FindConVar("tf_dropped_weapon_lifetime");

	// crons
	CreateTimer(10.0, Timer_Cron, 0, TIMER_REPEAT);

	LoadDHooks();

	if(gEV_Type != Engine_TF2)
	{
		CreateTimer(1.0, Timer_Scoreboard, 0, TIMER_REPEAT);
	}

	// modules
	gB_Checkpoints = LibraryExists("shavit-checkpoints");
	gB_Eventqueuefix = LibraryExists("eventqueuefix");
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_ReplayPlayback = LibraryExists("shavit-replay-playback");
	gB_Chat = LibraryExists("shavit-chat");
	gB_Zones = LibraryExists("shavit-zones");
}

void LoadDHooks()
{
	Handle hGameData = LoadGameConfigFile("shavit.games");

	if (hGameData == null)
	{
		SetFailState("Failed to load shavit gamedata");
	}

	int iOffset;

	if (gEV_Type == Engine_TF2)
	{
		if (!(gH_CalcPlayerScore = DHookCreateDetour(Address_Null, CallConv_CDECL, ReturnType_Int, ThisPointer_Ignore)))
		{
			SetFailState("Failed to create detour for CTFGameRules::CalcPlayerScore");
		}

		if (DHookSetFromConf(gH_CalcPlayerScore, hGameData, SDKConf_Signature, "CTFGameRules::CalcPlayerScore"))
		{
			gH_CalcPlayerScore.AddParam(HookParamType_Int);
			gH_CalcPlayerScore.AddParam(HookParamType_CBaseEntity);
			gH_CalcPlayerScore.Enable(Hook_Pre, Detour_CalcPlayerScore);
		}
		else
		{
			LogError("Couldn't get the address for \"CTFGameRules::CalcPlayerScore\" - make sure your gamedata is updated!");
		}
	}
	else
	{
		if ((iOffset = GameConfGetOffset(hGameData, "CCSPlayer::GetPlayerMaxSpeed")) == -1)
		{
			SetFailState("Couldn't get the offset for \"CCSPlayer::GetPlayerMaxSpeed\" - make sure your gamedata is updated!");
		}

		gH_GetPlayerMaxSpeed = DHookCreate(iOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, CCSPlayer__GetPlayerMaxSpeed);
	}

	if ((iOffset = GameConfGetOffset(hGameData, "CGameRules::IsSpawnPointValid")) != -1)
	{
		gH_IsSpawnPointValid = new DynamicHook(iOffset, HookType_GameRules, ReturnType_Bool, ThisPointer_Ignore);
		gH_IsSpawnPointValid.AddParam(HookParamType_CBaseEntity);
		gH_IsSpawnPointValid.AddParam(HookParamType_CBaseEntity);
	}
	else
	{
		SetFailState("Couldn't get the offset for \"CGameRules::IsSpawnPointValid\" - make sure your gamedata is updated!");
	}

	delete hGameData;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == gCV_HideRadar && sv_disable_radar != null)
	{
		sv_disable_radar.BoolValue = gCV_HideRadar.BoolValue;
	}
	else if (gEV_Type == Engine_TF2 && convar == gCV_NoWeaponDrops)
	{
		if (convar.BoolValue)
		{
			tf_dropped_weapon_lifetime.IntValue = 0;
			TF2_KillDroppedWeapons();
		} else
		{
			tf_dropped_weapon_lifetime.IntValue = 30; // default value
		}
	}
}

public MRESReturn Hook_IsSpawnPointValid(Handle hReturn, Handle hParams)
{
	if (gCV_NoBlock.BoolValue)
	{
		DHookSetReturn(hReturn, true);
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

MRESReturn Detour_CalcPlayerScore(DHookReturn hReturn, DHookParam hParams)
{
	if (!gCV_Scoreboard.BoolValue)
	{
		return MRES_Ignored;
	}

	int client = hParams.Get(2);
	float fPB = Shavit_GetClientPB(client, 0, Track_Main);
	int iScore = (fPB != 0.0 && fPB < 2000)? -RoundToFloor(fPB):-2000;

	hReturn.Value = iScore;
	return MRES_Supercede;
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	char sSetting[8];
	GetClientCookie(client, gH_HideCookie, sSetting, sizeof(sSetting));
	gB_Hide[client] = StringToInt(sSetting) != 0;
	GetClientCookie(client, gH_AutoRestartCookie, sSetting, sizeof(sSetting));
	gB_AutoRestart[client] = StringToInt(sSetting) != 0;

	gI_Style[client] = Shavit_GetBhopStyle(client);
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

	if(!LoadAdvertisementsConfig())
	{
		SetFailState("Cannot open \"configs/shavit-advertisements.cfg\". Make sure this file exists and that the server has read permissions to it.");
	}
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	gI_Style[client] = newstyle;
}

void LoadMapFixes()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-mapfixes.cfg");

	KeyValues kv = new KeyValues("shavit-mapfixes");

	if (kv.ImportFromFile(sPath) && kv.JumpToKey(gS_Map) && kv.GotoFirstSubKey(false))
	{
		do {
			char key[128];
			char value[128];
			kv.GetSectionName(key, sizeof(key));
			kv.GetString(NULL_STRING, value, sizeof(value));

			PrintToServer(">>>> shavit-misc/mapfixes: %s \"%s\"", key, value);

			ConVar cvar = FindConVar(key);

			if (cvar)
			{
				cvar.SetString(value, true, true);
			}
		} while (kv.GotoNextKey(false));
	}

	delete kv;
}

void CreateSpawnPoint(int iTeam, float fOrigin[3], float fAngles[3])
{
	int iSpawnPoint = CreateEntityByName((gEV_Type == Engine_TF2)? "info_player_teamspawn":((iTeam == 2)? "info_player_terrorist":"info_player_counterterrorist"));

	if (DispatchSpawn(iSpawnPoint))
	{
		if (gEV_Type == Engine_TF2)
		{
			SetEntProp(iSpawnPoint, Prop_Send, "m_iTeamNum", iTeam);
		}

		TeleportEntity(iSpawnPoint, fOrigin, fAngles, NULL_VECTOR);
	}
}

public void OnMapStart()
{
	gH_IsSpawnPointValid.HookGamerules(Hook_Post, Hook_IsSpawnPointValid);

	GetLowercaseMapName(gS_Map);

	if (gB_Late)
	{
		gB_Late = false;
		Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount());
		Shavit_OnChatConfigLoaded();
		OnAutoConfigsBuffered();

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);

				if(AreClientCookiesCached(i))
				{
					OnClientCookiesCached(i);
					Shavit_OnStyleChanged(i, 0, Shavit_GetBhopStyle(i), Shavit_GetClientTrack(i), false);
				}
			}
		}
	}
}

public void OnAutoConfigsBuffered()
{
	LoadMapFixes();
}

public void OnConfigsExecuted()
{
	if(sv_disable_immunity_alpha != null)
	{
		sv_disable_immunity_alpha.BoolValue = true;
	}

	if (sv_disable_radar != null && gCV_HideRadar.BoolValue)
	{
		sv_disable_radar.BoolValue = true;
	}

	if (tf_dropped_weapon_lifetime != null && gCV_NoWeaponDrops.BoolValue)
	{
		tf_dropped_weapon_lifetime.IntValue = 0;
	}

	if(gCV_CreateSpawnPoints.IntValue > 0)
	{
		int info_player_terrorist        = FindEntityByClassname(-1, "info_player_terrorist");
		int info_player_counterterrorist = FindEntityByClassname(-1, "info_player_counterterrorist");
		int info_player_teamspawn        = FindEntityByClassname(-1, "info_player_teamspawn");
		int info_player_start            = FindEntityByClassname(-1, "info_player_start");

		int iEntity =
			((info_player_terrorist != -1)        ? info_player_terrorist :
			((info_player_counterterrorist != -1) ? info_player_counterterrorist :
			((info_player_teamspawn != -1)        ? info_player_teamspawn :
			((info_player_start != -1)            ? info_player_start : -1))));

		if (iEntity != -1)
		{
			float fOrigin[3], fAngles[3];
			GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
			GetEntPropVector(iEntity, Prop_Data, "m_angAbsRotation", fAngles);

			if (gEV_Type == Engine_TF2)
			{
				int iSearch = -1;
				bool haveRed = false;
				bool haveBlu = false;

				while ((iSearch = FindEntityByClassname(iSearch, "info_player_teamspawn")) != -1)
				{
					int team = GetEntProp(iSearch, Prop_Send, "m_iTeamNum");
					haveRed = haveRed || team == 2;
					haveBlu = haveBlu || team == 3;
				}

				if (!haveRed)
				{
					CreateSpawnPoint(2, fOrigin, fAngles);
				}

				if (!haveBlu)
				{
					CreateSpawnPoint(3, fOrigin, fAngles);
				}
			}
			else
			{
				if (info_player_terrorist == -1)
				{
					CreateSpawnPoint(2, fOrigin, fAngles);
				}

				if (info_player_counterterrorist == -1)
				{
					CreateSpawnPoint(3, fOrigin, fAngles);
				}
			}
		}
	}

	if(gCV_AdvertisementInterval.FloatValue > 0.0)
	{
		CreateTimer(gCV_AdvertisementInterval.FloatValue, Timer_Advertisement, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

bool LoadAdvertisementsConfig()
{
	gA_Advertisements.Clear();

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-advertisements.cfg");

	KeyValues kv = new KeyValues("shavit-advertisements");

	if(!kv.ImportFromFile(sPath) || !kv.GotoFirstSubKey(false))
	{
		delete kv;

		return false;
	}

	do
	{
		char sTempMessage[300];
		kv.GetString(NULL_STRING, sTempMessage, 300, "<EMPTY ADVERTISEMENT>");

		ReplaceString(sTempMessage, 300, "{text}", gS_ChatStrings.sText);
		ReplaceString(sTempMessage, 300, "{warning}", gS_ChatStrings.sWarning);
		ReplaceString(sTempMessage, 300, "{variable}", gS_ChatStrings.sVariable);
		ReplaceString(sTempMessage, 300, "{variable2}", gS_ChatStrings.sVariable2);
		ReplaceString(sTempMessage, 300, "{style}", gS_ChatStrings.sStyle);

		gA_Advertisements.PushString(sTempMessage);
	}

	while(kv.GotoNextKey(false));

	delete kv;

	gI_AdvertisementsCycle = gA_Advertisements.Length ? (gI_AdvertisementsCycle % gA_Advertisements.Length) : 0;

	return true;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}
	else if(StrEqual(name, "shavit-replay-playback"))
	{
		gB_ReplayPlayback = true;
	}
	else if(StrEqual(name, "shavit-chat"))
	{
		gB_Chat = true;
	}
	else if (StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}
	else if (StrEqual(name, "shavit-checkpoints"))
	{
		gB_Checkpoints = true;
	}
	else if(StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}
	else if(StrEqual(name, "shavit-replay-playback"))
	{
		gB_ReplayPlayback = false;
	}
	else if(StrEqual(name, "shavit-chat"))
	{
		gB_Chat = false;
	}
	else if (StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}
	else if (StrEqual(name, "shavit-checkpoints"))
	{
		gB_Checkpoints = false;
	}
	else if(StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = false;
	}
}

int GetHumanTeam()
{
	char sTeam[8];
	mp_humanteam.GetString(sTeam, 8);

	if(StrEqual(sTeam, "t", false) || StrEqual(sTeam, "red", false))
	{
		return 2;
	}
	else if(StrEqual(sTeam, "ct", false) || StrContains(sTeam, "blu", false) != -1)
	{
		return 3;
	}

	return 0;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "trigger_multiple") || StrEqual(classname, "trigger_once") || StrEqual(classname, "trigger_push") || StrEqual(classname, "trigger_teleport") || StrEqual(classname, "trigger_gravity"))
	{
		SDKHook(entity, SDKHook_StartTouch, HookTrigger);
		SDKHook(entity, SDKHook_EndTouch, HookTrigger);
		SDKHook(entity, SDKHook_Touch, HookTrigger);
	}
}

public Action HookTrigger(int entity, int other)
{
	if(IsValidClient(other))
	{
		if(gB_DisableTriggers[other])
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action Command_Spectate(int client, const char[] command, int args)
{
	if(!IsValidClient(client) || !gCV_JointeamHook.BoolValue)
	{
		return Plugin_Continue;
	}

	Command_Spec(client, 0);
	return Plugin_Stop;
}

public int ScoreboardSort(int index1, int index2, Handle array, Handle hndl)
{
	int a = GetArrayCell(array, index1);
	int b = GetArrayCell(array, index2);

	int a_team = GetClientTeam(a);
	int b_team = GetClientTeam(b);

	if (a_team != b_team)
	{
		return a_team > b_team ? -1 : 1;
	}

	int a_score;
	int b_score;

	if (gEV_Type == Engine_CSGO)
	{
		a_score = CS_GetClientContributionScore(a);
		b_score = CS_GetClientContributionScore(b);
	}
	else
	{
		a_score = GetEntProp(a, Prop_Data, "m_iFrags");
		b_score = GetEntProp(b, Prop_Data, "m_iFrags");
	}

	if (a_score != b_score)
	{
		return a_score > b_score ? -1 : 1;
	}

	int a_deaths = GetEntProp(a, Prop_Data, "m_iDeaths");
	int b_deaths = GetEntProp(b, Prop_Data, "m_iDeaths");

	if (a_deaths != b_deaths)
	{
		return a_deaths < b_deaths ? -1 : 1;
	}

	return a < b ? -1 : 1;
}

public Action Command_SpecNextPrev(int client, const char[] command, int args)
{
	if (!IsValidClient(client) || !gCV_SpecScoreboardOrder.BoolValue)
	{
		return Plugin_Continue;
	}

	int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

	if (iObserverMode <= 3 /* OBS_MODE_FIXED */)
	{
		return Plugin_Continue;
	}

	ArrayList players = new ArrayList(1);

	// add valid alive players
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i != client && IsValidClient(i) && IsPlayerAlive(i) && GetClientTeam(i) > 1)
		{
			players.Push(i);
		}
	}

	if (players.Length < 2)
	{
		delete players;
		return Plugin_Continue;
	}

	players.SortCustom(ScoreboardSort);

	int current_target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

	if (!IsValidClient(current_target))
	{
		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", players.Get(0));
		delete players;
		return Plugin_Stop;
	}

	int pos = players.FindValue(current_target);

	if (pos == -1)
	{
		pos = 0;
	}

	pos += (StrEqual(command, "spec_next", true)) ? 1 : -1;

	if (pos < 0)
	{
		pos = players.Length - 1;
	}

	if (pos >= players.Length)
	{
		pos = 0;
	}

	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", players.Get(pos));
	delete players;
	return Plugin_Stop;
}

public Action Command_Jointeam(int client, const char[] command, int args)
{
	if(!IsValidClient(client) || !gCV_JointeamHook.BoolValue)
	{
		return Plugin_Continue;
	}

	char arg1[8];
	GetCmdArg(1, arg1, 8);

	int iTeam = StringToInt(arg1);
	int iHumanTeam = GetHumanTeam();

	if (iHumanTeam != 0 && iTeam != 1)
	{
		iTeam = iHumanTeam;
	}

	if (iTeam < 1 || iTeam > 3)
	{
		iTeam = GetRandomInt(2, 3);
	}

	CleanSwitchTeam(client, iTeam);

	if(gCV_RespawnOnTeam.BoolValue && iTeam != 1)
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_RespawnPlayer(client);
		}
		else
		{
			RemoveAllWeapons(client); // so weapons are removed and we don't hit the edict limit
			CS_RespawnPlayer(client);
		}

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void CleanSwitchTeam(int client, int team)
{
	if (gEV_Type == Engine_CSGO && GetClientTeam(client) == team)
	{
		// Close the team menu when selecting your own team...
		Event event = CreateEvent("player_team");
		event.SetInt("userid", GetClientUserId(client));
		event.SetInt("team", team);
		event.SetBool("silent", true);
		event.FireToClient(client);
		event.Cancel();
	}

	if(gEV_Type == Engine_TF2)
	{
		TF2_ChangeClientTeam(client, view_as<TFTeam>(team));
	}
	else if(team != 1)
	{
		CS_SwitchTeam(client, team);
	}
	else
	{
		// Remove flashlight :)
		if (gEV_Type == Engine_CSS)
		{
			int EF_DIMLIGHT = 4;
			SetEntProp(client, Prop_Send, "m_fEffects", ~EF_DIMLIGHT & GetEntProp(client, Prop_Send, "m_fEffects"));
		}

		ChangeClientTeam(client, team);
	}
}

public Action Command_Radio(int client, const char[] command, int args)
{
	if(gCV_DisableRadio.BoolValue)
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public MRESReturn CCSPlayer__GetPlayerMaxSpeed(int pThis, DHookReturn hReturn)
{
	if(!gCV_StaticPrestrafe.BoolValue || !IsValidClient(pThis, true))
	{
		return MRES_Ignored;
	}

	hReturn.Value = Shavit_GetStyleSettingFloat(gI_Style[pThis], "runspeed");

	return MRES_Override;
}

float normalize_ang(float ang)
{
	while (ang > 180.0) ang -= 360.0;
	while (ang < -180.0) ang += 360.0; return ang;
}

public Action Timer_Cron(Handle timer)
{
	if(gCV_HideRadar.BoolValue && gEV_Type == Engine_CSS)
	{
		float salt = GetURandomFloat();

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				RemoveRadar(i, salt);
			}
		}
	}

	if (gCV_NoWeaponDrops.BoolValue)
	{
		int ent = -1;

		while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
		{
			if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == -1)
			{
				AcceptEntityInput(ent, "Kill");
			}
		}
	}

	if (gEV_Type != Engine_CSGO && gCV_BadSetLocalAnglesFix.BoolValue)
	{
		int ent = -1;

		while ((ent = FindEntityByClassname(ent, "func_rotating")) != -1)
		{
			float ang[3], newang[3];
			GetEntPropVector(ent, Prop_Send, "m_angRotation", ang);
			newang[0] = normalize_ang(ang[0]);
			newang[1] = normalize_ang(ang[1]);
			newang[2] = normalize_ang(ang[2]);

			if (newang[0] != ang[0] || newang[1] != ang[1] || newang[2] != ang[2])
			{
				SetEntPropVector(ent, Prop_Send, "m_angRotation", newang);
			}
		}
	}

	return Plugin_Continue;
}

public Action Timer_Scoreboard(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i))
		{
			continue;
		}

		if(gCV_Scoreboard.BoolValue)
		{
			UpdateScoreboard(i);
		}

		UpdateClanTag(i);
	}

	return Plugin_Continue;
}

void FillAdvertisementBuffer(char[] buf, int buflen, int index)
{
	char sHostname[128];
	hostname.GetString(sHostname, 128);

	char sTimeLeft[32];
	int iTimeLeft = 0;
	GetMapTimeLeft(iTimeLeft);
	FormatSeconds(float(iTimeLeft), sTimeLeft, 32, false, true);

	char sTimeLeftRaw[8];
	IntToString(iTimeLeft, sTimeLeftRaw, 8);

	char sIPAddress[64];

	if(GetFeatureStatus(FeatureType_Native, "SteamWorks_GetPublicIP") == FeatureStatus_Available)
	{
		int iAddress[4];
		SteamWorks_GetPublicIP(iAddress);

		FormatEx(sIPAddress, 64, "%d.%d.%d.%d:%d", iAddress[0], iAddress[1], iAddress[2], iAddress[3], hostport.IntValue);
	}
	
	int iStageCount = Shavit_GetStageCount(Track_Main);
	char sType[16];	
	char sStageInfo[16];

	if(iStageCount > 1)
	{
		FormatEx(sType, 16, "Staged");
		FormatEx(sStageInfo, 16, "%d Stages", iStageCount);
	}
	else
	{
		iStageCount = Shavit_GetCheckpointCount(Track_Main);

		FormatEx(sType, 16, "Linear");
		FormatEx(sStageInfo, 16, "%d Checkpoint%s", iStageCount, iStageCount > 2 ? "s":"");
	}

	int iBonusCount = Shavit_GetMapTracks(true, false);
	char sTrackInfo[32];

	FormatEx(sTrackInfo, 32, "%d Bonus%s", iBonusCount, iBonusCount > 1 ? "es":"");

	int iTier = gB_Rankings ? Shavit_GetMapTier(gS_Map):0;
	char sTier[8];
	FormatEx(sTier, 8, "Tier %d", iTier);

	gA_Advertisements.GetString(index, buf, buflen);

	ReplaceString(buf, buflen, "{timeleft}", sTimeLeft);
	ReplaceString(buf, buflen, "{timeleftraw}", sTimeLeftRaw);
	ReplaceString(buf, buflen, "{hostname}", sHostname);
	ReplaceString(buf, buflen, "{serverip}", sIPAddress);
	ReplaceString(buf, buflen, "{map}", gS_Map);
	ReplaceString(buf, buflen, "{type}", sType);
	ReplaceString(buf, buflen, "{stage}", sStageInfo);
	ReplaceString(buf, buflen, "{bonus}", sTrackInfo);
	ReplaceString(buf, buflen, "{tier}", sTier);
}

public Action Timer_Advertisement(Handle timer)
{
	if (!gA_Advertisements.Length)
	{
		return Plugin_Continue;
	}

	char sTempMessage[256];
	FillAdvertisementBuffer(sTempMessage, sizeof(sTempMessage), gI_AdvertisementsCycle);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			if ((Shavit_GetMessageSetting(i) & MSG_ADVERTISEMENT) != 0)
			{
				continue;
			}

			char sName[MAX_NAME_LENGTH];
			GetClientName(i, sName, sizeof(sName));
			char sTempTempMessage[256];
			sTempTempMessage = sTempMessage;
			ReplaceString(sTempTempMessage, 256, "{name}", sName);

			Shavit_StopChatSound();
			Shavit_PrintToChat(i, "%s", sTempTempMessage);
		}
	}

	if(++gI_AdvertisementsCycle >= gA_Advertisements.Length)
	{
		gI_AdvertisementsCycle = 0;
	}

	return Plugin_Continue;
}

void UpdateScoreboard(int client)
{
	// this doesn't work on tf2 probably because of CTFGameRules::CalcPlayerScore
	if(gEV_Type == Engine_TF2)
	{
		return;
	}

	float fPB = Shavit_GetClientPB(client, 0, Track_Main);

	int iScore = (fPB != 0.0 && fPB < 2000)? -RoundToFloor(fPB):-2000;

	if(gEV_Type == Engine_CSGO)
	{
		CS_SetClientContributionScore(client, iScore);
	}
	else
	{
		SetEntProp(client, Prop_Data, "m_iFrags", iScore);
	}

	if(gB_Rankings)
	{
		SetEntProp(client, Prop_Data, "m_iDeaths", Shavit_GetRank(client));
	}
}

void UpdateClanTag(int client)
{
	// no clan tags in tf2
	char sCustomTag[32];
	gCV_ClanTag.GetString(sCustomTag, 32);

	if(gEV_Type == Engine_TF2 || StrEqual(sCustomTag, "0"))
	{
		return;
	}

	char sTime[16];

	float fTime = Shavit_GetClientTime(client);

	if(Shavit_GetTimerStatus(client) == Timer_Stopped || fTime < 1.0)
	{
		strcopy(sTime, 16, "N/A");
	}
	else
	{
		FormatSeconds(fTime, sTime, sizeof(sTime), false, true);
	}

	int track = Shavit_GetClientTrack(client);
	char sTrack[4];

	if(track == Track_Main && Shavit_IsOnlyStageMode(client))
	{
		FormatEx(sTrack, 4, "S%d", Shavit_GetClientLastStage(client));
	}
	else if (track >= Track_Bonus)
	{
		FormatEx(sTrack, 4, "B%d", 0 + track);
	}

	char sRank[8];

	if(gB_Rankings)
	{
		IntToString(Shavit_GetRank(client), sRank, 8);
	}

	ReplaceString(sCustomTag, 32, "{style}", gS_StyleStrings[gI_Style[client]].sStyleName);
	ReplaceString(sCustomTag, 32, "{styletag}", gS_StyleStrings[gI_Style[client]].sClanTag);
	ReplaceString(sCustomTag, 32, "{time}", sTime);
	ReplaceString(sCustomTag, 32, "{tr}", sTrack);
	ReplaceString(sCustomTag, 32, "{rank}", sRank);

	if(gB_Chat)
	{
		char sChatrank[32];
		Shavit_GetPlainChatrank(client, sChatrank, sizeof(sChatrank), false);
		ReplaceString(sCustomTag, 32, "{cr}", sChatrank);
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnClanTagChangePre);
	Call_PushCell(client);
	Call_PushStringEx(sCustomTag, 32, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(32);
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}

	CS_SetClientClanTag(client, sCustomTag);

	Call_StartForward(gH_Forwards_OnClanTagChangePost);
	Call_PushCell(client);
	Call_PushStringEx(sCustomTag, 32, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(32);
	Call_Finish();
}

void RemoveRagdoll(int client)
{
	int iEntity = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");

	if(iEntity != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(iEntity, "Kill");
	}
}

void TF2_KillDroppedWeapons()
{
	int ent = -1;

	while ((ent = FindEntityByClassname(ent, "tf_dropped_weapon")) != -1)
	{
		AcceptEntityInput(ent, "Kill");
	}
}

public void Shavit_OnPause(int client, int track)
{
	if (gB_Eventqueuefix)
	{
		SetClientEventsPaused(client, true);
	}
}

public void Shavit_OnResume(int client, int track)
{
	if (gB_Eventqueuefix)
	{
		SetClientEventsPaused(client, false);
	}
}

public void Shavit_OnStop(int client, int track)
{
	if (gB_Eventqueuefix)
	{
		SetClientEventsPaused(client, false);
	}
}

// This is used instead of `TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed)`.
// Why: TeleportEntity somehow triggers the zone EndTouch which fucks with `Shavit_InsideZone`.
void DumbSetVelocity(int client, float fSpeed[3])
{
	// Someone please let me know if any of these are unnecessary.
	SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", ZERO_VECTOR);
	SetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);
	SetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed); // m_vecBaseVelocity+m_vecVelocity
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style)
{
	bool bNoclip = (GetEntityMoveType(client) == MOVETYPE_NOCLIP);

	if (gB_AutoRestart[client])
	{
		float current = Shavit_GetClientTime(client);	
		float bestTime = Shavit_IsOnlyStageMode(client) ? Shavit_GetClientStagePB(client, style, Shavit_GetClientLastStage(client)):Shavit_GetClientPB(client, style, track);

		if (bestTime != 0 && current > bestTime)
		{
			Shavit_RestartTimer(client, track, false, false);
			Shavit_PrintToChat(client, "%T", "AutoRestartTriggered1", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
			Shavit_PrintToChat(client, "%T", "AutoRestartTriggered2", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		}
	}

	int iZoneStage;
	bool bInsideStageZone = track == Track_Main ? Shavit_InsideZoneStage(client, iZoneStage):false;
	bool bInStart = Shavit_InsideZone(client, Zone_Start, track) || 
					(bInsideStageZone && iZoneStage == Shavit_GetClientLastStage(client));
	
	// i will not be adding a setting to toggle this off
	if(bNoclip)
	{
		if(status == Timer_Running)
		{
			Shavit_StopTimer(client);
		}

		if (bInStart)
		{
			int restrictnoclip = Shavit_GetStyleSettingInt(gI_Style[client], "restrictnoclip");

			if (restrictnoclip == -1)
			{
				restrictnoclip = gCV_RestrictNoclip.IntValue;
			}

			if (restrictnoclip == 1)
			{
				float fSpeed[3];
				GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);
				fSpeed[2] = 0.0;
				DumbSetVelocity(client, fSpeed);
			}
			else if (restrictnoclip == 2)
			{
				SetEntityMoveType(client, MOVETYPE_ISOMETRIC);
			}
		}
	}

	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");

	if (!bNoclip && bInStart)
	{
		float prespeed_ez_vel = Shavit_GetStyleSettingFloat(gI_Style[client], "prespeed_ez_vel");

		if (prespeed_ez_vel > 0.0 && iGroundEntity != -1 && (buttons & IN_JUMP))
		{
			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);
			float fSpeedXY = (SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)));

			if (fSpeedXY < prespeed_ez_vel)
			{
				float theta;

				if (fSpeedXY >= 1.0)
				{
					float direction[3];
					GetVectorAngles(fSpeed, direction);
					theta = DegToRad(direction[1]);
				}
				else
				{
					theta = DegToRad(angles[1]);
				}

				fSpeed[0] = prespeed_ez_vel * Cosine(theta);
				fSpeed[1] = prespeed_ez_vel * Sine(theta);
				DumbSetVelocity(client, fSpeed);
			}
		}
	}

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_SetTransmit, OnSetTransmit);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	if(gEV_Type != Engine_TF2)
	{
		SDKHook(client, SDKHook_WeaponDrop, OnWeaponDrop);
	}

	gI_LastWeaponTick[client] = 0;
	gI_LastNoclipTick[client] = 0;
	gB_DisableTriggers[client] = false;

	if(IsFakeClient(client))
	{
		return;
	}

	if(gEV_Type == Engine_TF2)
	{
		SDKHook(client, SDKHook_PreThinkPost, TF2_OnPreThink);
	}
	else
	{
		if(gH_GetPlayerMaxSpeed != null)
		{
			DHookEntity(gH_GetPlayerMaxSpeed, true, client);
		}
	}

	if(!AreClientCookiesCached(client))
	{
		gI_Style[client] = Shavit_GetBhopStyle(client);
		gB_Hide[client] = false;
	}
}

public void OnClientDisconnect(int client)
{
	if(gCV_NoWeaponDrops.BoolValue)
	{
		if (IsClientInGame(client))
		{
			RemoveAllWeapons(client);
		}
	}
}

void ClearViewPunch(int victim)
{
	if (1 <= victim <= MaxClients)
	{
		if(gEV_Type == Engine_CSGO)
		{
			SetEntPropVector(victim, Prop_Send, "m_viewPunchAngle", ZERO_VECTOR);
			SetEntPropVector(victim, Prop_Send, "m_aimPunchAngle", ZERO_VECTOR);
			SetEntPropVector(victim, Prop_Send, "m_aimPunchAngleVel", ZERO_VECTOR);
		}
		else
		{
			SetEntPropVector(victim, Prop_Send, "m_vecPunchAngle", ZERO_VECTOR);
			SetEntPropVector(victim, Prop_Send, "m_vecPunchAngleVel", ZERO_VECTOR);
		}
	}
}

public Action OnTakeDamage(int victim, int& attacker)
{
	bool bBlockDamage;

	switch(gCV_GodMode.IntValue)
	{
		case 0:
		{
			bBlockDamage = false;
		}
		case 1:
		{
			// 0 - world/fall damage
			if(attacker == 0)
			{
				bBlockDamage = true;
			}
		}
		case 2:
		{
			if(IsValidClient(attacker))
			{
				bBlockDamage = true;
			}
		}
		default:
		{
			bBlockDamage = true;
		}
	}

	if (gB_Hide[victim] || bBlockDamage || IsFakeClient(victim))
	{
		ClearViewPunch(victim);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (i != victim && IsValidClient(i) && GetSpectatorTarget(i) == victim)
			{
				ClearViewPunch(i);
			}
		}
	}

	return bBlockDamage ? Plugin_Handled : Plugin_Continue;
}

public void OnWeaponDrop(int client, int entity)
{
	if(gCV_NoWeaponDrops.BoolValue && IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}
}

// hide
public Action OnSetTransmit(int entity, int client)
{
	if (client == entity)
	{
		return Plugin_Continue;
	}

	if (IsPlayerAlive(client))
	{
		if (gB_Hide[client] || !IsPlayerAlive(entity))
		{
			return Plugin_Handled;
		}
	}
	else if (gB_Hide[client])
	{
		if (!IsClientObserver(client) || (GetEntProp(client, Prop_Send, "m_iObserverMode") != 6 && GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") != entity))
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public void TF2_OnPreThink(int client)
{
	if(IsPlayerAlive(client))
	{
		float maxspeed;

		if (GetEntityFlags(client) & FL_ONGROUND)
		{
			maxspeed = Shavit_GetStyleSettingFloat(gI_Style[client], "runspeed");
		}
		else
		{
			// This is used to stop CTFGameMovement::PreventBunnyJumping from destroying
			// player velocity when doing uncrouch stuff. Kind of poopy.
			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);
			maxspeed = GetVectorLength(fSpeed);
		}

		// not the best method, but only one i found for tf2
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", maxspeed);
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	if(IsChatTrigger() && gCV_HideChatCommands.BoolValue)
	{
		// hide commands
		return Plugin_Handled;
	}

	if(sArgs[0] == '!' || sArgs[0] == '/')
	{
		bool bUpper = false;
		char buf[200];
		int size = strcopy(buf, sizeof(buf), sArgs[1]);

		for(int i = 0; i < size; i++)
		{
			if (buf[i] == ' ' || buf[i] == '\n' || buf[i] == '\t')
			{
				break;
			}

			if (IsCharUpper(buf[i]))
			{
				buf[i] = CharToLower(buf[i]);
				bUpper = true;
			}
		}

		if(bUpper)
		{
			FakeClientCommandEx(client, "sm_%s", buf);
			return Plugin_Stop;
		}
	}

	if (StrEqual(sArgs, "1r") || StrEqual(sArgs, "1b"))
	{
		if (gCV_HideChatCommands.BoolValue)
			return Plugin_Handled; // block chat but still do _Post
	}

	return Plugin_Continue;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (StrEqual(sArgs, "1r") || StrEqual(sArgs, "1b"))
	{
		FakeClientCommandEx(client, "sm_%c", sArgs[1]);
	}
}


public Action Command_Hide(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gB_Hide[client] = !gB_Hide[client];
	SetClientCookie(client, gH_HideCookie, gB_Hide[client] ? "1" : "0");

	if(gB_Hide[client])
	{
		Shavit_PrintToChat(client, "%T", "HideEnabled", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
	else
	{
		Shavit_PrintToChat(client, "%T", "HideDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

public Action Command_Spec(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	CleanSwitchTeam(client, 1);

	int target = -1;

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		target = FindTarget(client, sArgs, false, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}
	else if (gB_ReplayPlayback)
	{
		target = Shavit_GetReplayBotIndex(0, -1); // try to find normal bot

		if (target < 1)
		{
			int last_real_player = -1;

			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i, true))
				{
					if (IsFakeClient(i))
					{
						target = i;
						break;
					}

					last_real_player = i;
				}
			}

			if (target < 1)
			{
				target = last_real_player;
			}
		}
	}

	if(IsValidClient(target, true))
	{
		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target);
	}

	return Plugin_Handled;
}

public Action Command_PrintAdverts(int client, int args)
{
	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));

	for (int i = 0; i < gA_Advertisements.Length; i++)
	{
		char sTempMessage[256];
		FillAdvertisementBuffer(sTempMessage, sizeof(sTempMessage), i);
		ReplaceString(sTempMessage, sizeof(sTempMessage), "{name}", sName);
		Shavit_StopChatSound();
		Shavit_PrintToChat(client, "%s", sTempMessage);
	}

	return Plugin_Handled;
}

public Action Command_Teleport(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gCV_TeleportCommands.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		int iTarget = FindTarget(client, sArgs, false, false);

		if(iTarget == -1)
		{
			return Plugin_Handled;
		}

		Teleport(client, GetClientSerial(iTarget));
	}
	else
	{
		Menu menu = new Menu(MenuHandler_Teleport);
		menu.SetTitle("%T", "TeleportMenuTitle", client);

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i, true) || i == client)
			{
				continue;
			}

			char serial[16];
			IntToString(GetClientSerial(i), serial, 16);

			char sName[MAX_NAME_LENGTH];
			GetClientName(i, sName, sizeof(sName));

			menu.AddItem(serial, sName);
		}

		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}

	return Plugin_Handled;
}

public int MenuHandler_Teleport(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(!Teleport(param1, StringToInt(sInfo)))
		{
			Command_Teleport(param1, 0);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

bool Teleport(int client, int targetserial)
{
	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "TeleportAlive", client);

		return false;
	}

	int iTarget = GetClientFromSerial(targetserial);

	if(iTarget == 0)
	{
		Shavit_PrintToChat(client, "%T", "TeleportInvalidTarget", client);

		return false;
	}

	float vecPosition[3];
	GetClientAbsOrigin(iTarget, vecPosition);

	Shavit_StopTimer(client);

	TeleportEntity(client, vecPosition, NULL_VECTOR, NULL_VECTOR);

	return true;
}

public Action Command_Weapon(int client, int args)
{
	if(!IsValidClient(client) || gEV_Type == Engine_TF2)
	{
		return Plugin_Handled;
	}

	if(gCV_WeaponCommands.IntValue == 0)
	{
		Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "WeaponAlive", client, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if (GetGameTickCount() - gI_LastWeaponTick[client] < 10)
	{
		return Plugin_Handled;
	}

	gI_LastWeaponTick[client] = GetGameTickCount();

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	int iSlot = CS_SLOT_SECONDARY;
	char sWeapon[32];

	if(StrContains(sCommand, "usp", false) != -1)
	{
		strcopy(sWeapon, 32, (gEV_Type == Engine_CSS)? "weapon_usp":"weapon_usp_silencer");
	}
	else if(StrContains(sCommand, "glock", false) != -1)
	{
		strcopy(sWeapon, 32, "weapon_glock");
	}
	else
	{
		strcopy(sWeapon, 32, "weapon_knife");
		iSlot = CS_SLOT_KNIFE;
	}

	int iWeapon = GetPlayerWeaponSlot(client, iSlot);

	if(iWeapon != -1)
	{
		RemovePlayerItem(client, iWeapon);
		AcceptEntityInput(iWeapon, "Kill");
	}

	iWeapon = (gEV_Type == Engine_CSGO) ? GiveSkinnedWeapon(client, sWeapon) : GivePlayerItem(client, sWeapon);
	FakeClientCommand(client, "use %s", sWeapon);

	if(iSlot != CS_SLOT_KNIFE)
	{
		SetMaxWeaponAmmo(client, iWeapon, false);
	}

	return Plugin_Handled;
}

bool CanSegment(int client)
{
	return Shavit_GetStyleSettingBool(gI_Style[client], "segments");
}

bool ShouldDisplayStopWarning(int client)
{
	return (!Shavit_IsPracticeMode(client) && gCV_StopTimerWarning.BoolValue && Shavit_GetTimerStatus(client) != Timer_Stopped && Shavit_GetClientTime(client) > gCV_StopTimerWarning.FloatValue && !CanSegment(client));
}

void DoNoclip(int client)
{
	Shavit_StopTimer(client);
	SetEntityMoveType(client, MOVETYPE_NOCLIP);
}

void DoEnd(int client)
{
	Shavit_GotoEnd(client, gI_LastStopInfo[client]);
}

void DoRestart(int client)
{
	Shavit_RestartTimer(client, gI_LastStopInfo[client], false, true);
}

void DoStyleChange(int client)
{
	Shavit_StopTimer(client);
	FakeClientCommandEx(client, "sm_style %d", gI_LastStopInfo[client]);
}

void DoStopTimer(int client)
{
	Shavit_StopTimer(client);
}

void DoToggleTriggers(int client)
{
	Shavit_StopTimer(client);

	gB_DisableTriggers[client] = !gB_DisableTriggers[client];
	Shavit_PrintToChat(client, "%T", gB_DisableTriggers[client] ? "TriggerDisabled" : "TriggerEnabled", client, gB_DisableTriggers[client] ? gS_ChatStrings.sWarning:gS_ChatStrings.sVariable, gS_ChatStrings.sText);
}

void OpenStopWarningMenu(int client, StopTimerCallback after)
{
	gH_AfterWarningMenu[client] = after;

	Menu hMenu = new Menu(MenuHandler_StopWarning);
	hMenu.SetTitle("%T\n ", "StopTimerWarning", client);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "StopTimerYes", client);
	hMenu.AddItem("yes", sDisplay);

	FormatEx(sDisplay, 64, "%T", "StopTimerNo", client);
	hMenu.AddItem("no", sDisplay);

	hMenu.ExitButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_StopWarning(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		if(StrEqual(sInfo, "yes"))
		{
			Call_StartFunction(null, gH_AfterWarningMenu[param1]);
			Call_PushCell(param1);
			Call_Finish();
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public bool Shavit_OnStopPre(int client, int track)
{
	if(ShouldDisplayStopWarning(client))
	{
		OpenStopWarningMenu(client, DoStopTimer);

		return false;
	}

	return true;
}

public Action Shavit_OnTeleport(int client, int index, int target)
{
	if(gB_DisableTriggers[client])
	{
		Shavit_StopTimer(client);
	}

	return Plugin_Handled;
}

public Action Command_MaptimerCheckpoints(int client, int args)
{
	if (client == 0 && args == 1)
	{
		char arg[8];
		GetCmdArg(1, arg, sizeof(arg));
		static float starttime;

		if (StringToInt(arg) == 0)
		{
			starttime = GetGameTime();
		}
		else
		{
			Shavit_PrintToChatAll("Nice! That took %s%.3fs", gS_ChatStrings.sVariable, GetGameTime()-starttime);
		}
	}

	return Plugin_Handled;
}


public Action Command_Noclip(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if (gI_LastNoclipTick[client] == GetGameTickCount())
	{
		return Plugin_Handled;
	}

	gI_LastNoclipTick[client] = GetGameTickCount();

	if(gCV_NoclipMe.IntValue == 0)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}
	else if(gCV_NoclipMe.IntValue == 2 && !CheckCommandAccess(client, "admin_noclipme", ADMFLAG_CHEATS))
	{
		Shavit_PrintToChat(client, "%T", "LackingAccess", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAlive", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(GetEntityMoveType(client) != MOVETYPE_NOCLIP)
	{
		int iFlags = Shavit_CanPause(client);
		int target = GetSpectatorTarget(client, client);
		int iZoneStage;
		int iTrack = Shavit_GetClientTrack(client);
		
		bool bInsideStageZone = iTrack == Track_Main ? Shavit_InsideZoneStage(client, iZoneStage):false;
		bool bPractice = Shavit_IsPracticeMode(target);
		bool bSegmented = Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(target), "segments");
		bool bInStart = gB_Zones && Shavit_InsideZone(client, Zone_Start, iTrack) || 
								(Shavit_IsOnlyStageMode(client) && bInsideStageZone && iZoneStage == Shavit_GetClientLastStage(client));
		
		if (Shavit_IsPaused(client))
		{
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
			return Plugin_Handled;
		}
		else if(bInStart)//(iFlags & CPR_InStartZone) > 0)
		{
			Shavit_SetPracticeMode(client, true, true);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
			return Plugin_Handled;
		}
		else if(Shavit_GetTimerStatus(client) == Timer_Running)
		{
			if(bPractice || bSegmented)
			{
				Shavit_SetPracticeMode(client, true, true);
				Shavit_StopTimer(client);
				SetEntityMoveType(client, MOVETYPE_NOCLIP);
				return Plugin_Handled;
			}

			if((iFlags & CPR_NotOnGround) > 0)
			{
				Shavit_PrintToChat(client, "%T", "PauseNotOnGround", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}

			if((iFlags & CPR_Moving) > 0)
			{
				Shavit_PrintToChat(client, "%T", "PauseMoving", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}

			if((iFlags & CPR_Duck) > 0)
			{
				Shavit_PrintToChat(client, "%T", "PauseDuck", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}

			GetClientAbsOrigin(client, gF_PauseOrigin[client]);
			GetClientEyeAngles(client, gF_PauseAngles[client]);
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", gF_PauseVelocity[client]);
			Shavit_PauseTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
			Shavit_PrintToChat(client, "%T", "MessagePause", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		}
		else
		{
			Shavit_SetPracticeMode(client, true, true);
			Shavit_StopTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
		}
	}
	else
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}

	return Plugin_Handled;
}

public Action CommandListener_Noclip(int client, const char[] command, int args)
{
	if(!IsValidClient(client, true))
	{
		return Plugin_Stop;
	}

	if (gI_LastNoclipTick[client] == GetGameTickCount())
	{
		return Plugin_Stop;
	}

	gI_LastNoclipTick[client] = GetGameTickCount();

	if((gCV_NoclipMe.IntValue == 1 || (gCV_NoclipMe.IntValue == 2 && CheckCommandAccess(client, "noclipme", ADMFLAG_CHEATS))) && command[0] == '+')
	{
		int iFlags = Shavit_CanPause(client);
		int target = GetSpectatorTarget(client, client);
		int iZoneStage;
		int iTrack = Shavit_GetClientTrack(client);
		
		bool bInsideStageZone = iTrack == Track_Main ? Shavit_InsideZoneStage(client, iZoneStage):false;
		bool bPractice = Shavit_IsPracticeMode(target);
		bool bSegmented = Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(target), "segments");
		bool bInStart = gB_Zones && Shavit_InsideZone(client, Zone_Start, iTrack) || 
								(Shavit_IsOnlyStageMode(client) && bInsideStageZone && iZoneStage == Shavit_GetClientLastStage(client));
		
		if (Shavit_IsPaused(client))
		{
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
			return Plugin_Handled;
		}
		else if(bInStart)//(iFlags & CPR_InStartZone) > 0)
		{
			Shavit_SetPracticeMode(client, true, true);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
			return Plugin_Handled;
		}
		else if(Shavit_GetTimerStatus(client) == Timer_Running)
		{
			if(bPractice || bSegmented)
			{
				Shavit_SetPracticeMode(client, true, true);
				Shavit_StopTimer(client);
				SetEntityMoveType(client, MOVETYPE_NOCLIP);
				return Plugin_Handled;
			}

			if((iFlags & CPR_NotOnGround) > 0)
			{
				Shavit_PrintToChat(client, "%T", "PauseNotOnGround", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}

			if((iFlags & CPR_Moving) > 0)
			{
				Shavit_PrintToChat(client, "%T", "PauseMoving", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}

			if((iFlags & CPR_Duck) > 0)
			{
				Shavit_PrintToChat(client, "%T", "PauseDuck", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}

			GetClientAbsOrigin(client, gF_PauseOrigin[client]);
			GetClientEyeAngles(client, gF_PauseAngles[client]);
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", gF_PauseVelocity[client]);
			Shavit_PauseTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
			Shavit_PrintToChat(client, "%T", "MessagePause", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		}
		else
		{
			Shavit_SetPracticeMode(client, true, true);
			Shavit_StopTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
		}
	}
	else if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}

	return Plugin_Stop;
}

public Action CommandListener_funcommands_Noclip(int client, const char[] command, int args)
{
	if (IsValidClient(client, true) && args < 1)
	{
		Command_Noclip(client, 0);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action CommandListener_Real_Noclip(int client, const char[] command, int args)
{
	if (sv_cheats.BoolValue)
	{
		if (gI_LastNoclipTick[client] == GetGameTickCount())
		{
			return Plugin_Stop;
		}

		int iFlags = Shavit_CanPause(client);
		int target = GetSpectatorTarget(client, client);
		int iZoneStage;
		int iTrack = Shavit_GetClientTrack(client);
		
		bool bInsideStageZone = iTrack == Track_Main ? Shavit_InsideZoneStage(client, iZoneStage):false;
		bool bPractice = Shavit_IsPracticeMode(target);
		bool bSegmented = Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(target), "segments");
		bool bInStart = gB_Zones && Shavit_InsideZone(client, Zone_Start, iTrack) || 
								(Shavit_IsOnlyStageMode(client) && bInsideStageZone && iZoneStage == Shavit_GetClientLastStage(client));

		if (Shavit_IsPaused(client))
		{
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
			return Plugin_Handled;
		}
		else if(bInStart)//(iFlags & CPR_InStartZone) > 0)
		{
			Shavit_SetPracticeMode(client, true, true);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
			return Plugin_Handled;
		}
		else if(Shavit_GetTimerStatus(client) == Timer_Running)
		{
			if(bPractice || bSegmented)
			{
				Shavit_SetPracticeMode(client, true, true);
				Shavit_StopTimer(client);
				SetEntityMoveType(client, MOVETYPE_NOCLIP);
				return Plugin_Handled;
			}

			if((iFlags & CPR_NotOnGround) > 0)
			{
				Shavit_PrintToChat(client, "%T", "PauseNotOnGround", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}

			if((iFlags & CPR_Moving) > 0)
			{
				Shavit_PrintToChat(client, "%T", "PauseMoving", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}

			if((iFlags & CPR_Duck) > 0)
			{
				Shavit_PrintToChat(client, "%T", "PauseDuck", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}

			GetClientAbsOrigin(client, gF_PauseOrigin[client]);
			GetClientEyeAngles(client, gF_PauseAngles[client]);
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", gF_PauseVelocity[client]);
			Shavit_PauseTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
			Shavit_PrintToChat(client, "%T", "MessagePause", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		}
		else
		{
			Shavit_SetPracticeMode(client, true, true);
			Shavit_StopTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
		}		

		gI_LastNoclipTick[client] = GetGameTickCount();
	}

	return Plugin_Continue;
}

// copy from Anie1337
public Action Command_Help(int client, int args)
{
	OpenCommandsMenu(client);

	return Plugin_Continue;
}

void OpenCommandsMenu(int client)
{
	Menu menu = new Menu(CommandsMenu_Handler);
	menu.SetTitle("%T\n ", "MenuTitle_Command", client);

	CommandIterator CmdIt = new CommandIterator();
	while(CmdIt.Next())
	{
		char sCommand[32];
		CmdIt.GetName(sCommand, sizeof(sCommand));
		if(!CheckCommandAccess(client, sCommand, CmdIt.Flags) || 
			StrEqual(sCommand, "ff") || 
			StrEqual(sCommand, "motd") || 
			StrEqual(sCommand, "nextmap"))
		{
			continue;
		}

		char sDescription[128];
		CmdIt.GetDescription(sDescription, sizeof(sDescription));

		char sItem[160];
		FormatEx(sItem, sizeof(sItem), "%s - %s", sCommand, sDescription);

		menu.AddItem(sCommand, sItem, ITEMDRAW_DISABLED);
	}

	delete CmdIt;

	menu.Display(client, -1);
}

public int CommandsMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sCommand[32];
		menu.GetItem(param2, sCommand, sizeof(sCommand));
		FakeClientCommand(param1, sCommand);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_ToggleTriggers(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gB_DisableTriggers[client])
	{
		Action result = CallOnDisableTriggersPre(client);

		if (result > Plugin_Continue)
		{
			return Plugin_Handled;
		}

		if(!Shavit_StopTimer(client, false))
		{
			return Plugin_Handled;
		}
	}

	gB_DisableTriggers[client] = !gB_DisableTriggers[client];
	Shavit_PrintToChat(client, "%T", gB_DisableTriggers[client] ? "TriggerDisabled" : "TriggerEnabled", client, gB_DisableTriggers[client] ? gS_ChatStrings.sWarning:gS_ChatStrings.sVariable, gS_ChatStrings.sText);

	return Plugin_Handled;
}

public Action Command_Specs(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	int iObserverTarget = GetSpectatorTarget(client, client);

	if(args > 0)
	{
		char sTarget[MAX_TARGET_LENGTH];
		GetCmdArgString(sTarget, MAX_TARGET_LENGTH);

		int iNewTarget = FindTarget(client, sTarget, false, false);

		if(iNewTarget == -1)
		{
			return Plugin_Handled;
		}

		if(!IsPlayerAlive(iNewTarget))
		{
			Shavit_PrintToChat(client, "%T", "SpectateDead", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

			return Plugin_Handled;
		}

		iObserverTarget = iNewTarget;
	}

	int iCount = 0;
	bool bIsAdmin = CheckCommandAccess(client, "admin_speclisthide", ADMFLAG_KICK);
	char sSpecs[192];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetClientTeam(i) < 1)
		{
			continue;
		}

		if((gCV_SpectatorList.IntValue == 1 && !bIsAdmin && CheckCommandAccess(i, "admin_speclisthide", ADMFLAG_KICK)) ||
			(gCV_SpectatorList.IntValue == 2 && !CanUserTarget(client, i)))
		{
			continue;
		}

		if(GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == iObserverTarget)
		{
			iCount++;

			if(iCount == 1)
			{
				FormatEx(sSpecs, 192, "%s%N", gS_ChatStrings.sVariable2, i);
			}
			else
			{
				Format(sSpecs, 192, "%s%s, %s%N", sSpecs, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, i);
			}
		}
	}

	if(iCount > 0)
	{
		Shavit_PrintToChat(client, "%T", "SpectatorCount", client, gS_ChatStrings.sVariable2, iObserverTarget, gS_ChatStrings.sText, gS_ChatStrings.sVariable, iCount, gS_ChatStrings.sText, sSpecs);
	}
	else
	{
		Shavit_PrintToChat(client, "%T", "SpectatorCountZero", client, gS_ChatStrings.sVariable2, iObserverTarget, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

public Action Shavit_OnStartPre(int client)
{
	if(gB_DisableTriggers[client])
	{
		return Plugin_Stop;
	}

	if (GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Shavit_OnStart(int client)
{
	if (gB_Eventqueuefix)
	{
		SetClientEventsPaused(client, false);
	}

	return Plugin_Continue;
}

public void Shavit_OnWorldRecord(int client, int style, float time, int jumps, int strafes, float sync, int track, int stage, float oldwr, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
	char sName[32+1];
	GetClientName(client, sName, sizeof(sName));

	char sTrack[32];
	char sMessage[256];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || (Shavit_GetMessageSetting(i) & MSG_WORLDRECORD) != 0)
		{
			continue;
		}

		if(stage == 0)
		{
			if(track == Track_Main)
			{
				FormatEx(sMessage, sizeof(sMessage), "%T", "WRNotice", i,
					gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText);				
			}
			else
			{
				GetTrackName(i, track, sTrack, 32);
				FormatEx(sMessage, sizeof(sMessage), "%T", "WRNoticeBonus", i,
					gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);	
			}
		}
		else
		{
			FormatEx(sTrack, 32, "%T %d", "StageText", i, stage);
			FormatEx(sMessage, sizeof(sMessage), "%T", "WRNoticeStage", i, 
				gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);
		}

		for(int j = 0; j < gCV_WRMessages.IntValue; j++)
		{
			Shavit_PrintToChat(i, sMessage);
		}
	}
}

public void Shavit_OnRestart(int client, int track, bool tostartzone)
{
	if(gEV_Type != Engine_TF2)
	{
		SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
	}
}

public Action Shavit_OnStyleCommandPre(int client, int oldstyle, int newstyle, int track)
{
	if (ShouldDisplayStopWarning(client))
	{
		gI_LastStopInfo[client] = newstyle;
		OpenStopWarningMenu(client, DoStyleChange);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Shavit_OnEndPre(int client, int track)
{
	if (ShouldDisplayStopWarning(client))
	{
		gI_LastStopInfo[client] = track;
		OpenStopWarningMenu(client, DoEnd);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action CallOnDisableTriggersPre(int client)
{
	if (ShouldDisplayStopWarning(client))
	{
		OpenStopWarningMenu(client, DoToggleTriggers);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Shavit_OnRestartPre(int client, int track)
{
	if(gCV_RespawnOnRestart.BoolValue && !IsPlayerAlive(client))
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_ChangeClientTeam(client, view_as<TFTeam>(GetRandomInt(2, 3)));
		}
		else
		{
			CS_SwitchTeam(client, GetRandomInt(2, 3));
		}

		if(gEV_Type == Engine_TF2)
		{
			TF2_RespawnPlayer(client);
		}
		else
		{
			CS_RespawnPlayer(client);
		}

		return Plugin_Handled;
	}

	if (ShouldDisplayStopWarning(client))
	{
		gI_LastStopInfo[client] = track;
		OpenStopWarningMenu(client, DoRestart);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Respawn(Handle timer, any data)
{
	int client = GetClientFromSerial(data);

	if(IsValidClient(client) && !IsPlayerAlive(client) && GetClientTeam(client) >= 2)
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_RespawnPlayer(client);
		}
		else
		{
			CS_RespawnPlayer(client);
		}

		if(gCV_RespawnOnRestart.BoolValue)
		{
			Shavit_RestartTimer(client, Shavit_GetClientTrack(client), true, true);
		}
	}

	return Plugin_Handled;
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsFakeClient(client))
	{
		int serial = GetClientSerial(client);

		if(gCV_HideRadar.BoolValue && gEV_Type == Engine_CSS)
		{
			RequestFrame(Frame_RemoveRadar, serial);
		}

		if (gCV_StartOnSpawn.BoolValue && !(gB_Checkpoints && Shavit_HasSavestate(client)))
		{
			Shavit_RestartTimer(client, Shavit_GetClientTrack(client), true, true);
		}

		if(gCV_Scoreboard.BoolValue)
		{
			UpdateScoreboard(client);
		}
	}

	if(gCV_NoBlock.BoolValue)
	{
		SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
	}

	if(gCV_PlayerOpacity.IntValue != -1)
	{
		SetEntityRenderMode(client, RENDER_TRANSCOLOR);
		SetEntityRenderColor(client, 255, 255, 255, gCV_PlayerOpacity.IntValue);
	}
}

void RemoveRadar(int client, float salt)
{
	if(client == 0 || !IsPlayerAlive(client))
	{
		return;
	}

	SetEntPropFloat(client, Prop_Send, "m_flFlashDuration", 20.0 + salt);
	SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", 0.5);
}

void Frame_RemoveRadar(any data)
{
	int client = GetClientFromSerial(data);
	RemoveRadar(client, GetURandomFloat());
}

public Action Player_Notifications(Event event, const char[] name, bool dontBroadcast)
{
	if(gCV_HideTeamChanges.BoolValue)
	{
		if (StrEqual(name, "player_team") && gEV_Type == Engine_CSGO)
		{
			event.SetBool("silent", true);
		}
		else
		{
			event.BroadcastDisabled = true;
		}
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsFakeClient(client))
	{
		if(gCV_AutoRespawn.FloatValue > 0.0 && StrEqual(name, "player_death"))
		{
			CreateTimer(gCV_AutoRespawn.FloatValue, Respawn, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	if ((gCV_RemoveRagdolls.IntValue == 1 && IsFakeClient(client)) || gCV_RemoveRagdolls.IntValue == 2)
	{
		RemoveRagdoll(client);
	}

	return Plugin_Continue;
}

public void Weapon_Fire(Event event, const char[] name, bool dB)
{
	int weaponcvar = gCV_WeaponCommands.IntValue;

	if (weaponcvar < 2)
	{
		return;
	}

	char sWeapon[16];
	event.GetString("weapon", sWeapon, 16);

	if (weaponcvar >= 4 || StrContains(sWeapon, "usp") != -1 || StrContains(sWeapon, "hkp") != -1 || StrContains(sWeapon, "glock") != -1)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		SetMaxWeaponAmmo(client, GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"), weaponcvar == 3 || weaponcvar == 5);
	}
}

public Action Shotgun_Shot(const char[] te_name, const int[] Players, int numClients, float delay)
{
	int client = (TE_ReadNum("m_iPlayer") + 1);

	if(!(1 <= client <= MaxClients) || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	int ticks = GetGameTickCount();

	if(gI_LastShot[client] == ticks)
	{
		return Plugin_Continue;
	}

	gI_LastShot[client] = ticks;

	int clients[MAXPLAYERS+1];
	int count = 0;

	for(int i = 0; i < numClients; i++)
	{
		int x = Players[i];

		if (!IsClientInGame(x) || x == client)
		{
			continue;
		}

		if (!gB_Hide[x] || GetSpectatorTarget(x) == client)
		{
			clients[count++] = x;
		}
	}

	if(numClients == count)
	{
		return Plugin_Continue;
	}

	TE_Start(te_name);

	float temp[3];
	TE_ReadVector("m_vecOrigin", temp);
	TE_WriteVector("m_vecOrigin", temp);

	TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
	TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
	TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
	TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
	TE_WriteNum("m_iPlayer", (client - 1));

	if(gEV_Type == Engine_CSS)
	{
		TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
		TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
		TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
	}
	else if(gEV_Type == Engine_CSGO)
	{
		TE_WriteNum("m_weapon", TE_ReadNum("m_weapon"));
		TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
		TE_WriteFloat("m_flRecoilIndex", TE_ReadFloat("m_flRecoilIndex"));
		TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
		TE_WriteNum("m_nItemDefIndex", TE_ReadNum("m_nItemDefIndex"));
		TE_WriteNum("m_iSoundType", TE_ReadNum("m_iSoundType"));
	}
	else if(gEV_Type == Engine_TF2)
	{
		TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
		TE_WriteFloat("m_flSpread", TE_ReadFloat("m_flSpread"));
		TE_WriteNum("m_bCritical", TE_ReadNum("m_bCritical"));
	}

	TE_Send(clients, count, delay);

	return Plugin_Stop;
}

public Action EffectDispatch(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if(!gCV_NoBlood.BoolValue)
	{
		return Plugin_Continue;
	}

	int iEffectIndex = TE_ReadNum("m_iEffectName");
	int nHitBox = TE_ReadNum("m_nHitBox");

	char sEffectName[32];
	GetEffectName(iEffectIndex, sEffectName, 32);

	if(StrEqual(sEffectName, "csblood"))
	{
		return Plugin_Handled;
	}

	if(StrEqual(sEffectName, "ParticleEffect"))
	{
		char sParticleEffectName[32];
		GetParticleEffectName(nHitBox, sParticleEffectName, 32);

		if(StrEqual(sParticleEffectName, "impact_helmet_headshot") || StrEqual(sParticleEffectName, "impact_physics_dust"))
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action WorldDecal(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if(!gCV_NoBlood.BoolValue)
	{
		return Plugin_Continue;
	}

	float vecOrigin[3];
	TE_ReadVector("m_vecOrigin", vecOrigin);

	int nIndex = TE_ReadNum("m_nIndex");

	char sDecalName[32];
	GetDecalName(nIndex, sDecalName, 32);

	if(StrContains(sDecalName, "decals/blood") == 0 && StrContains(sDecalName, "_subrect") != -1)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action NormalSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (gEV_Type != Engine_CSGO && IsValidClient(entity) && IsFakeClient(entity) && StrContains(sample, "footsteps/") != -1)
	{
		numClients = 0;

		if (gCV_BhopSounds.IntValue < 2)
		{
			// The server removes recipients that are in the PVS because CS:S generates the footsteps clientside.
			// UpdateStepSound clientside bails because of MOVETYPE_NOCLIP though.
			// So fuck it, add all the clients xd.
			// Alternatively and preferably you'd patch out the RemoveRecipientsByPVS call in PlayStepSound.
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i) && (!gB_Hide[i] || GetSpectatorTarget(i) == entity))
				{
					clients[numClients++] = i;
				}
			}
		}

		return Plugin_Changed;
	}

	if(StrContains(sample, "physics/") != -1 || StrContains(sample, "weapons/") != -1 || StrContains(sample, "player/") != -1 || StrContains(sample, "items/") != -1)
	{
		if(gCV_BhopSounds.IntValue == 2)
		{
			numClients = 0;
		}
		else
		{
			for(int i = 0; i < numClients; ++i)
			{
				if(!IsValidClient(clients[i]) || (clients[i] != entity && gB_Hide[clients[i]] && GetSpectatorTarget(clients[i]) != entity))
				{
					for (int j = i; j < numClients-1; j++)
					{
						clients[j] = clients[j+1];
					}

					numClients--;
					i--;
				}
			}
		}

		return Plugin_Changed;
	}

	return Plugin_Continue;
}

int GetParticleEffectName(int index, char[] sEffectName, int maxlen)
{
	static int table = INVALID_STRING_TABLE;

	if(table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("ParticleEffectNames");
	}

	return ReadStringTable(table, index, sEffectName, maxlen);
}

int GetEffectName(int index, char[] sEffectName, int maxlen)
{
	static int table = INVALID_STRING_TABLE;

	if(table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("EffectDispatch");
	}

	return ReadStringTable(table, index, sEffectName, maxlen);
}

int GetDecalName(int index, char[] sDecalName, int maxlen)
{
	static int table = INVALID_STRING_TABLE;

	if(table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("decalprecache");
	}

	return ReadStringTable(table, index, sDecalName, maxlen);
}

public void Shavit_OnFinish(int client)
{
	if(!gCV_Scoreboard.BoolValue)
	{
		return;
	}

	UpdateScoreboard(client);
	UpdateClanTag(client);
}

public Action Command_Drop(int client, const char[] command, int argc)
{
	if(!gCV_DropAll.BoolValue || !IsValidClient(client) || gEV_Type == Engine_TF2)
	{
		return Plugin_Continue;
	}

	int iWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

	if(iWeapon != -1 && IsValidEntity(iWeapon) && GetEntPropEnt(iWeapon, Prop_Send, "m_hOwnerEntity") == client)
	{
		CS_DropWeapon(client, iWeapon, true);
	}

	return Plugin_Stop;
}

public Action Command_AutoRestart(int client, int args)
{
	gB_AutoRestart[client] = !gB_AutoRestart[client];
	SetClientCookie(client, gH_AutoRestartCookie, gB_AutoRestart[client] ? "1" : "0");

	Shavit_PrintToChat(client, "%T", gB_AutoRestart[client] ? "AutoRestartEnabled" : "AutoRestartDisabled", client, gB_AutoRestart[client] ?  gS_ChatStrings.sVariable : gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	return Plugin_Handled;
}

public int Native_IsClientUsingHide(Handle plugin, int numParams)
{
	return gB_Hide[GetNativeCell(1)];
}
