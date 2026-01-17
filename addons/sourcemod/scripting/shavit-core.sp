/*
 * shavit's Timer - Core
 * by: shavit, rtldg, KiD Fearless, GAMMA CASE, Technoblazed, carnifex, ofirgall, Nairda, Extan, rumour, OliviaMourning, Nickelony, sh4hrazad, BoomShotKapow, strafe
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
#include <sdkhooks>
#include <sdktools>
#include <geoip>
#include <clientprefs>
#include <convar_class>
#include <dhooks>

#define DEBUG 0

#include <shavit/core>

#undef REQUIRE_PLUGIN
#include <shavit/hud>
#include <shavit/rankings>
#include <shavit/replay-playback>
#include <shavit/wr>
#include <shavit/zones>
#include <eventqueuefix>

#include <shavit/chat-colors>
#include <shavit/anti-sv_cheats.sp>
#include <shavit/steamid-stocks>
#include <shavit/style-settings.sp>
#include <shavit/sql-create-tables-and-migrations.sp>
#include <shavit/physicsuntouch>

#include <adminmenu>

#pragma newdecls required
#pragma semicolon 1

// game type (CS:S/CS:GO/TF2)
EngineVersion gEV_Type = Engine_Unknown;
bool gB_Protobuf = false;

// hook stuff
DynamicHook gH_AcceptInput; // used for hooking player_speedmod's AcceptInput
DynamicHook gH_TeleportDhook = null;

// database handle
Database gH_SQL = null;
int gI_Driver = Driver_unknown;

// forwards
Handle gH_Forwards_Start = null;
Handle gH_Forwards_StartPre = null;
Handle gH_Forwards_StageStart = null;
Handle gH_Forawrds_Started = null;
Handle gH_Forwards_Stop = null;
Handle gH_Forwards_StopPre = null;
Handle gH_Forwards_FinishPre = null;
Handle gH_Forwards_Finish = null;
Handle gH_Forwards_FinishStagePre = null;
Handle gH_Forwards_FinishStage = null;
Handle gH_Forwards_OnRestartPre = null;
Handle gH_Forwards_OnRestart = null;
Handle gH_Forwards_OnEndPre = null;
Handle gH_Forwards_OnEnd = null;
Handle gH_Forwards_OnPause = null;
Handle gH_Forwards_OnResume = null;
Handle gH_Forwards_OnStyleCommandPre = null;
Handle gH_Forwards_OnStyleChanged = null;
Handle gH_Forwards_OnTrackChanged = null;
Handle gH_Forwards_OnStageChanged = null;
Handle gH_Forwards_OnChatConfigLoaded = null;
Handle gH_Forwards_OnUserCmdPre = null;
Handle gH_Forwards_OnTimeIncrement = null;
Handle gH_Forwards_OnTimeIncrementPost = null;
Handle gH_Forwards_OnTimescaleChanged = null;
Handle gH_Forwards_OnTimeOffsetCalculated = null;
Handle gH_Forwards_OnProcessMovement = null;
Handle gH_Forwards_OnProcessMovementPost = null;
Handle gH_Forwards_OnTimerMenuCreate = null;
Handle gH_Forwards_OnTimerMenuSelected = null;
Handle gH_Forwards_OnToggleTriggersPre = null;
Handle gH_Forwards_OnToggleTriggers = null;

// player timer variables
timer_snapshot_t gA_Timers[MAXPLAYERS+1];
bool gB_Auto[MAXPLAYERS+1];
bool gB_DisableTriggers[MAXPLAYERS+1];
int gI_FirstTouchedGround[MAXPLAYERS+1];
int gI_LastTickcount[MAXPLAYERS+1];
int gI_LastNoclipTick[MAXPLAYERS+1];
int gI_LastButtons[MAXPLAYERS+1];

// these are here until the compiler bug is fixed
float gF_PauseOrigin[MAXPLAYERS+1][3];
float gF_PauseAngles[MAXPLAYERS+1][3];
float gF_PauseVelocity[MAXPLAYERS+1][3];

// potentially temporary more effective hijack angles
int gI_HijackFrames[MAXPLAYERS+1];
float gF_HijackedAngles[MAXPLAYERS+1][2];

// used for offsets
float gF_SmallestDist[MAXPLAYERS + 1];
float gF_Origin[MAXPLAYERS + 1][2][3];
float gF_Fraction[MAXPLAYERS + 1];

// client noclip speed
float gF_NoclipSpeed[MAXPLAYERS + 1];

// message setting bits
int gI_MessageSettings[MAXPLAYERS + 1];

// cookies
Handle gH_StyleCookie = null;
Handle gH_AutoBhopCookie = null;
Handle gH_MessageCookie = null;
Cookie gH_IHateMain = null;

// late load
bool gB_Late = false;

// modules
bool gB_Eventqueuefix = false;
bool gB_Zones = false;
bool gB_ReplayPlayback = false;
bool gB_Rankings = false;
bool gB_AdminMenu = false;

// use to clear players checkpoint times
float empty_times[MAX_STAGES] = {-1.0, ...};
int empty_attempts[MAX_STAGES] = {0, ...};

TopMenu gH_AdminMenu = null;
TopMenuObject gH_TimerCommands = INVALID_TOPMENUOBJECT;

// cvars
Convar gCV_Restart = null;
Convar gCV_Pause = null;
Convar gCV_PauseMovement = null;
Convar gCV_DisablePracticeModeOnStart = null;
Convar gCV_VelocityTeleport = null;
Convar gCV_DefaultStyle = null;
Convar gCV_NoChatSound = null;
Convar gCV_SimplerLadders = null;
Convar gCV_UseOffsets = null;
Convar gCV_TimeInMessages;
Convar gCV_DebugOffsets = null;
Convar gCV_SaveIps = null;
Convar gCV_HijackTeleportAngles = null;
Convar gCV_PrestrafeZone = null;
Convar gCV_PrestrafeLimit = null;

// cached cvars
int gI_DefaultStyle = 0;
bool gB_StyleCookies = true;

// table prefix
char gS_MySQLPrefix[32];

// server side
ConVar sv_accelerate = null;
ConVar sv_airaccelerate = null;
ConVar sv_autobunnyhopping = null;
ConVar sv_enablebunnyhopping = null;
ConVar sv_friction = null;
ConVar sv_noclipspeed = null;

// chat settings
chatstrings_t gS_ChatStrings;

// misc cache
bool gB_StopChatSound = false;
bool gB_HookedJump = false;
bool gB_PlayerRepeat[MAXPLAYERS+1];
char gS_LogPath[PLATFORM_MAX_PATH];
char gS_DeleteMap[MAXPLAYERS+1][PLATFORM_MAX_PATH];
int gI_WipePlayerID[MAXPLAYERS+1];
char gS_Verification[MAXPLAYERS+1][8];
bool gB_CookiesRetrieved[MAXPLAYERS+1];
float gF_ZoneAiraccelerate[MAXPLAYERS+1];
float gF_ZoneSpeedLimit[MAXPLAYERS+1];
int gI_LastPrintedSteamID[MAXPLAYERS+1];
int gI_GroundEntity[MAXPLAYERS+1];

// kz support
bool gB_KZMap[TRACKS_SIZE];


#include <shavit/bhopstats-timerified.sp> // down here to get includes from replay-playback & to inherit gB_ReplayPlayback


public Plugin myinfo =
{
	name = "[shavit-surf] Core",
	author = "shavit, rtldg, KiD Fearless, GAMMA CASE, Technoblazed, carnifex, ofirgall, Nairda, Extan, rumour, OliviaMourning, Nickelony, sh4hrazad, BoomShotKapow, strafe, *Surf integration version modified by KikI",
	description = "The core for shavit surf timer. (This plugin is base on shavit's bhop timer)",
	version = SHAVIT_SURF_VERSION,
	url = "https://github.com/shavitush/bhoptimer  https://github.com/bhopppp/Shavit-Surf-Timer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	new Convar("shavit_core_log_sql", "0", "Whether to log SQL queries from the timer.", 0, true, 0.0, true, 1.0);

	Bhopstats_CreateNatives();
	Shavit_Style_Settings_Natives();

	CreateNative("Shavit_CanPause", Native_CanPause);
	CreateNative("Shavit_ChangeClientStyle", Native_ChangeClientStyle);
	CreateNative("Shavit_FinishMap", Native_FinishMap);
	CreateNative("Shavit_FinishStage", Native_FinishStage);
	CreateNative("Shavit_GetBhopStyle", Native_GetBhopStyle);
	CreateNative("Shavit_GetChatStrings", Native_GetChatStrings);
	CreateNative("Shavit_GetChatStringsStruct", Native_GetChatStringsStruct);
	CreateNative("Shavit_GetClientJumps", Native_GetClientJumps);
	CreateNative("Shavit_GetClientTime", Native_GetClientTime);
	CreateNative("Shavit_GetClientStageTime", Native_GetClientStageTime);
	CreateNative("Shavit_GetClientTrack", Native_GetClientTrack);
	CreateNative("Shavit_GetClientLastStage", Native_GetClientLastStage);
	CreateNative("Shavit_SetClientLastStage", Native_SetClientLastStage);
	CreateNative("Shavit_GetClientCPTimes", Native_GetClientCPTimes);
	CreateNative("Shavit_SetClientCPTimes", Native_SetClientCPTimes);
	CreateNative("Shavit_GetClientCPTime", Native_GetClientCPTime);
	CreateNative("Shavit_SetClientCPTime", Native_SetClientCPTime);
	CreateNative("Shavit_GetClientStageFinishTimes", Native_GetClientStageFinishTimes);
	CreateNative("Shavit_SetClientStageFinishTimes", Native_SetClientStageFinishTimes);
	CreateNative("Shavit_GetClientStageFinishTime", Native_GetClientStageFinishTime);
	CreateNative("Shavit_SetClientStageFinishTime", Native_SetClientStageFinishTime);
	CreateNative("Shavit_GetClientStageAttempts", Native_GetClientStageAttempts);
	CreateNative("Shavit_SetClientStageAttempts", Native_SetClientStageAttempts);
	CreateNative("Shavit_GetClientStageAttempt", Native_GetClientStageAttempt);
	CreateNative("Shavit_SetClientStageAttempt", Native_SetClientStageAttempt);
	CreateNative("Shavit_StageTimeValid", Native_StageTimeValid);
	CreateNative("Shavit_SetStageTimeValid", Native_SetStageTimeValid);
	CreateNative("Shavit_GetDatabase", Native_GetDatabase);
	CreateNative("Shavit_GetPerfectJumps", Native_GetPerfectJumps);
	CreateNative("Shavit_GetStrafeCount", Native_GetStrafeCount);
	CreateNative("Shavit_GetSync", Native_GetSync);
	CreateNative("Shavit_GetZoneOffset", Native_GetZoneOffset);
	CreateNative("Shavit_GetDistanceOffset", Native_GetDistanceOffset);
	CreateNative("Shavit_GetTimerStatus", Native_GetTimerStatus);
	CreateNative("Shavit_IsKZMap", Native_IsKZMap);
	CreateNative("Shavit_IsPaused", Native_IsPaused);
	CreateNative("Shavit_IsPracticeMode", Native_IsPracticeMode);
	CreateNative("Shavit_LoadSnapshot", Native_LoadSnapshot);
	CreateNative("Shavit_LogMessage", Native_LogMessage);
	CreateNative("Shavit_MarkKZMap", Native_MarkKZMap);
	CreateNative("Shavit_PauseTimer", Native_PauseTimer);
	CreateNative("Shavit_PrintToChat", Native_PrintToChat);
	CreateNative("Shavit_PrintToChatAll", Native_PrintToChatAll);
	CreateNative("Shavit_RestartTimer", Native_RestartTimer);
	CreateNative("Shavit_ResumeTimer", Native_ResumeTimer);
	CreateNative("Shavit_SaveSnapshot", Native_SaveSnapshot);
	CreateNative("Shavit_SetPracticeMode", Native_SetPracticeMode);
	CreateNative("Shavit_StartTimer", Native_StartTimer);
	CreateNative("Shavit_StartStageTimer", Native_StartStageTimer);
	CreateNative("Shavit_StopChatSound", Native_StopChatSound);
	CreateNative("Shavit_StopTimer", Native_StopTimer);
	CreateNative("Shavit_GetClientTimescale", Native_GetClientTimescale);
	CreateNative("Shavit_SetClientTimescale", Native_SetClientTimescale);
	CreateNative("Shavit_GetAvgVelocity", Native_GetAvgVelocity);
	CreateNative("Shavit_GetMaxVelocity", Native_GetMaxVelocity);
	CreateNative("Shavit_SetAvgVelocity", Native_SetAvgVelocity);
	CreateNative("Shavit_SetMaxVelocity", Native_SetMaxVelocity);
	CreateNative("Shavit_GetStartVelocity", Native_GetStartVelocity);
	CreateNative("Shavit_GetStageStartVelocity", Native_GetStageStartVelocity);
	CreateNative("Shavit_SetStartVelocity", Native_SetStartVelocity);
	CreateNative("Shavit_SetStageStartVelocity", Native_SetStageStartVelocity);
	CreateNative("Shavit_ShouldProcessFrame", Native_ShouldProcessFrame);
	CreateNative("Shavit_GotoEnd", Native_GotoEnd);
	CreateNative("Shavit_UpdateLaggedMovement", Native_UpdateLaggedMovement);
	CreateNative("Shavit_PrintSteamIDOnce", Native_PrintSteamIDOnce);
	CreateNative("Shavit_IsOnlyStageMode", Native_IsOnlyStageMode);
	CreateNative("Shavit_SetOnlyStageMode", Native_SetOnlyStageMode);
	CreateNative("Shavit_IsClientRepeat", Native_IsClientRepeat);
	CreateNative("Shavit_SetClientRepeat", Native_SetClientRepeat);
	CreateNative("Shavit_GetMessageSetting", Native_GetMessageSetting);
	CreateNative("Shavit_SetTriggerDisable", Native_SetTriggerDisable);
	CreateNative("Shavit_IsTriggerDisabled", Native_IsTriggerDisabled);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// forwards
	gH_Forwards_Start = CreateGlobalForward("Shavit_OnStart", ET_Ignore, Param_Cell, Param_Cell);
	gH_Forwards_StartPre = CreateGlobalForward("Shavit_OnStartPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_StageStart = CreateGlobalForward("Shavit_OnStageStart", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forawrds_Started = CreateGlobalForward("Shavit_OnStarted", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_Stop = CreateGlobalForward("Shavit_OnStop", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_StopPre = CreateGlobalForward("Shavit_OnStopPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_FinishPre = CreateGlobalForward("Shavit_OnFinishPre", ET_Hook, Param_Cell, Param_Array);
	gH_Forwards_Finish = CreateGlobalForward("Shavit_OnFinish", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_FinishStagePre = CreateGlobalForward("Shavit_OnFinishStagePre", ET_Event, Param_Cell, Param_Array);
	gH_Forwards_FinishStage = CreateGlobalForward("Shavit_OnFinishStage", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnRestartPre = CreateGlobalForward("Shavit_OnRestartPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnRestart = CreateGlobalForward("Shavit_OnRestart", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnEndPre = CreateGlobalForward("Shavit_OnEndPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnEnd = CreateGlobalForward("Shavit_OnEnd", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnPause = CreateGlobalForward("Shavit_OnPause", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnResume = CreateGlobalForward("Shavit_OnResume", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnStyleCommandPre = CreateGlobalForward("Shavit_OnStyleCommandPre", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnStyleChanged = CreateGlobalForward("Shavit_OnStyleChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnTrackChanged = CreateGlobalForward("Shavit_OnTrackChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnStageChanged = CreateGlobalForward("Shavit_OnStageChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnChatConfigLoaded = CreateGlobalForward("Shavit_OnChatConfigLoaded", ET_Event);
	gH_Forwards_OnUserCmdPre = CreateGlobalForward("Shavit_OnUserCmdPre", ET_Event, Param_Cell, Param_CellByRef, Param_CellByRef, Param_Array, Param_Array, Param_Cell, Param_Cell, Param_Cell, Param_Array, Param_Array);
	gH_Forwards_OnTimeIncrement = CreateGlobalForward("Shavit_OnTimeIncrement", ET_Event, Param_Cell, Param_Array, Param_CellByRef, Param_Array);
	gH_Forwards_OnTimeIncrementPost = CreateGlobalForward("Shavit_OnTimeIncrementPost", ET_Event, Param_Cell, Param_Cell, Param_Array);
	gH_Forwards_OnTimescaleChanged = CreateGlobalForward("Shavit_OnTimescaleChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnTimeOffsetCalculated = CreateGlobalForward("Shavit_OnTimeOffsetCalculated", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnProcessMovement = CreateGlobalForward("Shavit_OnProcessMovement", ET_Event, Param_Cell);
	gH_Forwards_OnProcessMovementPost = CreateGlobalForward("Shavit_OnProcessMovementPost", ET_Event, Param_Cell);
	gH_Forwards_OnTimerMenuCreate = CreateGlobalForward("Shavit_OnTimerMenuMade", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnTimerMenuSelected = CreateGlobalForward("Shavit_OnTimerMenuSelect", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);
	gH_Forwards_OnToggleTriggersPre = CreateGlobalForward("Shavit_OnToggleTriggersPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnToggleTriggers = CreateGlobalForward("Shavit_OnToggleTriggers", ET_Event, Param_Cell, Param_Cell);

	Bhopstats_CreateForwards();
	Shavit_Style_Settings_Forwards();

	LoadTranslations("shavit-core.phrases");
	LoadTranslations("shavit-common.phrases");

	// game types
	gEV_Type = GetEngineVersion();
	gB_Protobuf = (GetUserMessageType() == UM_Protobuf);

	sv_autobunnyhopping = FindConVar("sv_autobunnyhopping");
	if (sv_autobunnyhopping) sv_autobunnyhopping.BoolValue = false;

	if (gEV_Type != Engine_CSGO && gEV_Type != Engine_CSS && gEV_Type != Engine_TF2)
	{
		SetFailState("This plugin was meant to be used in CS:S, CS:GO and TF2 *only*.");
	}

	LoadDHooks();

	// hooks
	gB_HookedJump = HookEventEx("player_jump", Player_Jump);
	HookEvent("player_death", Player_Death);
	HookEvent("player_team", Player_Death);
	HookEvent("player_spawn", Player_Death);

	// commands START
	RegConsoleCmd("sm_timer", Command_Timer, "Show timer menu");
	RegConsoleCmd("sm_surftimer", Command_Timer, "Show timer menu");

	// style
	RegConsoleCmd("sm_style", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_styles", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_diff", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_difficulty", Command_Style, "Choose your bhop style.");
	gH_StyleCookie = RegClientCookie("shavit_style", "Style cookie", CookieAccess_Protected);

	// timer start
	RegConsoleCmd("sm_start", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_r", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_restart", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_m", Command_StartTimer, "Start your timer on the main track.");
	RegConsoleCmd("sm_main", Command_StartTimer, "Start your timer on the main track.");
	RegConsoleCmd("sm_ihate!main", Command_IHateMain, "If you really hate !main :(((");
	gH_IHateMain = new Cookie("shavit_mainhater", "If you really hate !main :(((", CookieAccess_Protected);

	RegConsoleCmd("sm_b", Command_StartTimer, "Start your timer on the bonus track.");
	RegConsoleCmd("sm_bonus", Command_StartTimer, "Start your timer on the bonus track.");

	RegConsoleCmd("sm_track", Command_Track, "Draw a menu to client shows all map tracks");

	//change noclip speed
	RegConsoleCmd("sm_noclipspeed", Command_NoclipSpeed, "Change client's sv_noclipspeed to specific value");
	RegConsoleCmd("sm_ns", Command_NoclipSpeed, "Change client's sv_noclipspeed to specific value");	

	//repeat command
	RegConsoleCmd("sm_repeat", Command_ToggleRepeat, "Repeat client's timer to a stage or a bonus.");


	for (int i = Track_Bonus; i <= Track_Bonus_Last; i++)
	{
		char cmd[10], helptext[50];
		FormatEx(cmd, sizeof(cmd), "sm_b%d", i);
		FormatEx(helptext, sizeof(helptext), "Start your timer on the bonus %d track.", i);
		RegConsoleCmd(cmd, Command_StartTimer, helptext);
	}

	// teleport to end
	RegConsoleCmd("sm_end", Command_TeleportEnd, "Teleport to endzone.");

	RegConsoleCmd("sm_bend", Command_TeleportEnd, "Teleport to endzone of the bonus track.");
	RegConsoleCmd("sm_bonusend", Command_TeleportEnd, "Teleport to endzone of the bonus track.");

	// timer stop
	RegConsoleCmd("sm_stop", Command_StopTimer, "Stop your timer.");

	// timer pause / resume
	RegConsoleCmd("sm_pause", Command_TogglePause, "Toggle pause.");
	RegConsoleCmd("sm_unpause", Command_TogglePause, "Toggle pause.");
	RegConsoleCmd("sm_resume", Command_TogglePause, "Toggle pause");

	// autobhop toggle
	RegConsoleCmd("sm_auto", Command_AutoBhop, "Toggle autobhop.");
	RegConsoleCmd("sm_autobhop", Command_AutoBhop, "Toggle autobhop.");
	gH_AutoBhopCookie = RegClientCookie("shavit_autobhop", "Autobhop cookie", CookieAccess_Protected);

	// Timescale commandssssssssss
	RegConsoleCmd("sm_timescale", Command_Timescale, "Sets your timescale on TAS styles.");
	RegConsoleCmd("sm_ts", Command_Timescale, "Sets your timescale on TAS styles.");
	RegConsoleCmd("sm_timescaleplus", Command_TimescalePlus, "Adds the value to your current timescale.");
	RegConsoleCmd("sm_tsplus", Command_TimescalePlus, "Adds the value to your current timescale.");
	RegConsoleCmd("sm_timescaleminus", Command_TimescaleMinus, "Subtracts the value from your current timescale.");
	RegConsoleCmd("sm_tsminus", Command_TimescaleMinus, "Subtracts the value from your current timescale.");

	// toggle triggers
	RegConsoleCmd("sm_toggletriggers", Command_ToggleTriggers, "Disable triggers for a client");
	RegConsoleCmd("sm_triggers", Command_ToggleTriggers, "Disable triggers for a client");
	RegConsoleCmd("sm_disabletriggers", Command_ToggleTriggers, "Disable triggers for a client");

	// Message settings
	RegConsoleCmd("sm_message", Command_Message, "Open message setting menu.");
	RegConsoleCmd("sm_msg", Command_Message, "Open message setting menu.");
	gH_MessageCookie = RegClientCookie("shavit_message", "Message setting cookie", CookieAccess_Protected);

	#if DEBUG
	RegConsoleCmd("sm_finishtest", Command_FinishTest);
	RegConsoleCmd("sm_fling", Command_Fling);
	#endif

	// admin
	RegAdminCmd("sm_deletemap", Command_DeleteMap, ADMFLAG_ROOT, "Deletes all map data. Usage: sm_deletemap <map>");
	RegAdminCmd("sm_wipeplayer", Command_WipePlayer, ADMFLAG_BAN, "Wipes all bhoptimer data for specified player. Usage: sm_wipeplayer <steamid3>");
	RegAdminCmd("sm_wipetrack", Command_WipeTrack, ADMFLAG_ROOT, "Deletes all runs on a track.");
	RegAdminCmd("sm_migration", Command_Migration, ADMFLAG_ROOT, "Force a database migration to run. Usage: sm_migration <migration id> or \"all\" to run all migrations.");
	// commands END

	// logs
	BuildPath(Path_SM, gS_LogPath, PLATFORM_MAX_PATH, "logs/shavit.log");

	CreateConVar("shavit_version", SHAVIT_VERSION, "Plugin version.", (FCVAR_NOTIFY | FCVAR_DONTRECORD));
	CreateConVar("shavit_surf_version", SHAVIT_SURF_VERSION, "Plugin version.", (FCVAR_NOTIFY | FCVAR_DONTRECORD));

	gCV_Restart = new Convar("shavit_core_restart", "1", "Allow commands that restart the timer?", 0, true, 0.0, true, 1.0);
	gCV_Pause = new Convar("shavit_core_pause", "1", "Allow pausing?", 0, true, 0.0, true, 1.0);
	gCV_PauseMovement = new Convar("shavit_core_pause_movement", "0", "Allow movement/noclip while paused?", 0, true, 0.0, true, 1.0);
	gCV_DisablePracticeModeOnStart = new Convar("shavit_core_disable_practicemode_onstart", "0", "Disable practice mode when client enter start zone?", 0, true, 0.0, true, 1.0);
	gCV_VelocityTeleport = new Convar("shavit_core_velocityteleport", "0", "Teleport the client when changing its velocity? (for special styles)", 0, true, 0.0, true, 1.0);
	gCV_DefaultStyle = new Convar("shavit_core_defaultstyle", "0", "Default style ID.\nAdd the '!' prefix to disable style cookies - i.e. \"!3\" to *force* scroll to be the default style.", 0, true, 0.0);
	gCV_NoChatSound = new Convar("shavit_core_nochatsound", "0", "Disables click sound for chat messages.", 0, true, 0.0, true, 1.0);
	gCV_SimplerLadders = new Convar("shavit_core_simplerladders", "1", "Allows using all keys on limited styles (such as sideways) after touching ladders\nTouching the ground enables the restriction again.", 0, true, 0.0, true, 1.0);
	gCV_UseOffsets = new Convar("shavit_core_useoffsets", "1", "Calculates more accurate times by subtracting/adding tick offsets from the time the server uses to register that a player has left or entered a trigger", 0, true, 0.0, true, 1.0);
	gCV_TimeInMessages = new Convar("shavit_core_timeinmessages", "0", "Whether to prefix SayText2 messages with the time.", 0, true, 0.0, true, 1.0);
	gCV_DebugOffsets = new Convar("shavit_core_debugoffsets", "0", "Print offset upon leaving or entering a zone?", 0, true, 0.0, true, 1.0);
	gCV_SaveIps = new Convar("shavit_core_save_ips", "1", "Whether to save player IPs in the 'users' database table. IPs are used to show player location on the !profile menu.\nTurning this on will not wipe existing IPs from the 'users' table.", 0, true, 0.0, true, 1.0);
	gCV_HijackTeleportAngles = new Convar("shavit_core_hijack_teleport_angles", "0", "Whether to hijack player angles on teleport so their latency doesn't fuck up their shit.", 0, true, 0.0, true, 1.0);
	gCV_PrestrafeZone = new Convar("shavit_core_prestrafezones", "3", "What situation should prestrafe limit excute when player inside a start zone?\n0 - Disabled, no prestrafe limit in any start zone.\n1 - Only excute prestrafe limit in track start zone.\n2 - Excute prestrafe limit in both track start zone and stage start zone, but prestrafe limit would not excute in stage start zone when player's main timer is running.\n3 - Excute prestrafe limit in both track start zone and stage start zone.", 0, true, 0.0, true, 3.0);
	gCV_PrestrafeLimit = new Convar("shavit_core_prestrafelimit", "100", "Prestrafe limitation in startzone.\nThe value used internally is style run speed + this.\ni.e. run speed of 250 can prestrafe up to 278 (+28) with regular settings.", 0, true, 0.0, false);
	gCV_DefaultStyle.AddChangeHook(OnConVarChanged);

	Anti_sv_cheats_cvars();

	Convar.AutoExecConfig();

	sv_accelerate = FindConVar("sv_accelerate");
	sv_airaccelerate = FindConVar("sv_airaccelerate");
	sv_airaccelerate.Flags &= ~(FCVAR_NOTIFY | FCVAR_REPLICATED);

	sv_noclipspeed = FindConVar("sv_noclipspeed");
	sv_noclipspeed.Flags &= ~(FCVAR_NOTIFY | FCVAR_REPLICATED);


	sv_enablebunnyhopping = FindConVar("sv_enablebunnyhopping");

	if(sv_enablebunnyhopping != null)
	{
		sv_enablebunnyhopping.Flags &= ~(FCVAR_NOTIFY | FCVAR_REPLICATED);
	}

	sv_friction = FindConVar("sv_friction");

	gB_Eventqueuefix = LibraryExists("eventqueuefix");
	gB_Zones = LibraryExists("shavit-zones");
	gB_ReplayPlayback = LibraryExists("shavit-replay-playback");
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_AdminMenu = LibraryExists("adminmenu");

	// database connections
	SQL_DBConnect();

	// late
	if(gB_Late)
	{
		if (gB_AdminMenu && (gH_AdminMenu = GetAdminTopMenu()) != null)
		{
			OnAdminMenuCreated(gH_AdminMenu);
			OnAdminMenuReady(gH_AdminMenu);
		}

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnAdminMenuCreated(Handle topmenu)
{
	gH_AdminMenu = TopMenu.FromHandle(topmenu);

	if ((gH_TimerCommands = gH_AdminMenu.FindCategory("Timer Commands")) == INVALID_TOPMENUOBJECT)
	{
		gH_TimerCommands = gH_AdminMenu.AddCategory("Timer Commands", CategoryHandler, "shavit_admin", ADMFLAG_RCON);
	}
}

public void CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayTitle)
	{
		FormatEx(buffer, maxlength, "%T:", "TimerCommands", param);
	}
	else if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "TimerCommands", param);
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	gH_AdminMenu = TopMenu.FromHandle(topmenu);
}

void LoadDHooks()
{
	Handle gamedataConf = LoadGameConfigFile("shavit.games");

	if(gamedataConf == null)
	{
		SetFailState("Failed to load shavit gamedata");
	}

	StartPrepSDKCall(SDKCall_Static);
	if(!PrepSDKCall_SetFromConf(gamedataConf, SDKConf_Signature, "CreateInterface_Server"))
	{
		SetFailState("Failed to get CreateInterface");
	}
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	Handle CreateInterface = EndPrepSDKCall();

	if(CreateInterface == null)
	{
		SetFailState("Unable to prepare SDKCall for CreateInterface");
	}

	char interfaceName[64];

	// ProcessMovement
	if(!GameConfGetKeyValue(gamedataConf, "IGameMovement", interfaceName, sizeof(interfaceName)))
	{
		SetFailState("Failed to get IGameMovement interface name");
	}

	Address IGameMovement = SDKCall(CreateInterface, interfaceName, 0);

	if(!IGameMovement)
	{
		SetFailState("Failed to get IGameMovement pointer");
	}

	int offset = GameConfGetOffset(gamedataConf, "ProcessMovement");
	if(offset == -1)
	{
		SetFailState("Failed to get ProcessMovement offset");
	}

	Handle processMovement = DHookCreate(offset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore, DHook_ProcessMovementPre);
	DHookAddParam(processMovement, HookParamType_CBaseEntity);
	DHookAddParam(processMovement, HookParamType_ObjectPtr);
	DHookRaw(processMovement, false, IGameMovement);

	Handle processMovementPost = DHookCreate(offset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore, DHook_ProcessMovementPost);
	DHookAddParam(processMovementPost, HookParamType_CBaseEntity);
	DHookAddParam(processMovementPost, HookParamType_ObjectPtr);
	DHookRaw(processMovementPost, true, IGameMovement);

	LoadPhysicsUntouch(gamedataConf);

	delete CreateInterface;
	delete gamedataConf;

	gamedataConf = LoadGameConfigFile("sdktools.games");

	offset = GameConfGetOffset(gamedataConf, "AcceptInput");
	gH_AcceptInput = new DynamicHook(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity);
	gH_AcceptInput.AddParam(HookParamType_CharPtr);
	gH_AcceptInput.AddParam(HookParamType_CBaseEntity);
	gH_AcceptInput.AddParam(HookParamType_CBaseEntity);
	gH_AcceptInput.AddParam(HookParamType_Object, 20, DHookPass_ByVal|DHookPass_ODTOR|DHookPass_OCTOR|DHookPass_OASSIGNOP); //variant_t is a union of 12 (float[3]) plus two int type params 12 + 8 = 20
	gH_AcceptInput.AddParam(HookParamType_Int);

	offset = GameConfGetOffset(gamedataConf, "Teleport");
	if (offset == -1)
	{
		SetFailState("Couldn't get the offset for \"Teleport\"!");
	}

	gH_TeleportDhook = new DynamicHook(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity);

	gH_TeleportDhook.AddParam(HookParamType_VectorPtr);
	gH_TeleportDhook.AddParam(HookParamType_VectorPtr);
	gH_TeleportDhook.AddParam(HookParamType_VectorPtr);
	if (gEV_Type == Engine_CSGO)
	{
		gH_TeleportDhook.AddParam(HookParamType_Bool);
	}

	delete gamedataConf;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == sv_autobunnyhopping)
	{
		if (convar.BoolValue)
			convar.BoolValue = false;
		return;
	}

	gB_StyleCookies = (newValue[0] != '!');
	gI_DefaultStyle = StringToInt(newValue[1]);
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}
	else if(StrEqual(name, "shavit-replay-playback"))
	{
		gB_ReplayPlayback = true;
	}
	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}
	else if(StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = true;
	}
	else if (StrEqual(name, "adminmenu"))
	{
		gB_AdminMenu = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}
	else if(StrEqual(name, "shavit-replay-playback"))
	{
		gB_ReplayPlayback = false;
	}
	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}
	else if(StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = false;
	}
	else if (StrEqual(name, "adminmenu"))
	{
		gB_AdminMenu = false;
		gH_AdminMenu = null;
		gH_TimerCommands = INVALID_TOPMENUOBJECT;
	}
}

public void OnMapStart()
{
	// styles
	if(!LoadStyles())
	{
		SetFailState("Could not load the styles configuration file. Make sure it exists (addons/sourcemod/configs/shavit-styles.cfg) and follows the proper syntax!");
	}

	// messages
	if(!LoadMessages())
	{
		SetFailState("Could not load the chat messages configuration file. Make sure it exists (addons/sourcemod/configs/shavit-messages.cfg) and follows the proper syntax!");
	}
}

public void OnConfigsExecuted()
{
	Anti_sv_cheats_OnConfigsExecuted();
}

public void OnMapEnd()
{
	bool empty[TRACKS_SIZE];
	gB_KZMap = empty;
}

public Action Command_Timer(int client, int args)
{
	Menu menu = new Menu(MenuHandler_Timer);
	menu.SetTitle("%T", "TimerMenuTitle", client);

	char sMenu[32];
	FormatEx(sMenu, 32, "%T", "ChatMessageOption", client);
	menu.AddItem("chat", sMenu);

	Call_StartForward(gH_Forwards_OnTimerMenuCreate);
	Call_PushCell(client);
	Call_PushCell(menu);
	Call_Finish();

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_Timer(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		Action aResult = Plugin_Continue;
		Call_StartForward(gH_Forwards_OnTimerMenuSelected);
		Call_PushCell(param1);
		Call_PushCell(param2);
		Call_PushStringEx(sInfo, 16, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		Call_PushCell(16);
		Call_Finish(aResult);

		if(StrEqual(sInfo, "chat"))
		{
			ShowMessageSettingMenu(param1, 0);
			return 0;
		}

		if(aResult == Plugin_Stop)
		{
			return 0;
		}

		Command_Timer(param1, 0);			
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_StartTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	if(!gCV_Restart.BoolValue)
	{
		if(args != -1)
		{
			Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings.sVariable, sCommand, gS_ChatStrings.sText);
		}

		return Plugin_Handled;
	}

	int track = Track_Main;
	bool bForceTeleToStartZone = StrContains(sCommand, "sm_m", false) == 0;

	if(StrContains(sCommand, "sm_b", false) == 0)
	{
		bForceTeleToStartZone = true;
		// Pull out bonus number for commands like sm_b1 and sm_b2.
		if ('1' <= sCommand[4] <= ('0' + Track_Bonus_Last))
		{
			track = StringToInt(sCommand[4]);
		}
		else if (args < 1)
		{
			ShowTrackMenu(client, true);
			return Plugin_Handled;
		}
		else
		{
			char arg[6];
			GetCmdArg(1, arg, sizeof(arg));
			track = StringToInt(arg);
		}

		if (track < Track_Bonus || track > Track_Bonus_Last)
		{
			track = Track_Bonus;
		}
	}
	else if(StrContains(sCommand, "sm_r", false) == 0 || StrContains(sCommand, "sm_s", false) == 0)
	{
		track = (DoIHateMain(client)) ? Track_Main : gA_Timers[client].iTimerTrack;
	}

	if (!gB_Zones || !(Shavit_ZoneExists(Zone_Start, track) || gB_KZMap[track]))
	{
		char sTrack[32];
		GetTrackName(client, track, sTrack, 32);

		Shavit_PrintToChat(client, "%T", "StartZoneUndefined", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTrack, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	Shavit_RestartTimer(client, track, bForceTeleToStartZone, false);

	return Plugin_Handled;
}

public Action Command_Track(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	ShowTrackMenu(client, false);

	return Plugin_Handled;
}

public void ShowTrackMenu(int client, bool bonus)
{
	int iTrackMask = Shavit_GetMapTracks(false, true);

	Menu menu = new Menu(MenuHandler_Track);
	menu.SetTitle("%T\n ", bonus ? "MenuSelectBonus":"MenuSelectTrack", client);

	int iLastTrack;
	char sTrack[32];
	for(int i = bonus ? 1:0; i < TRACKS_SIZE; i++)
	{
		if(iTrackMask < 0)
		{
			break;
		}
		
		if (((iTrackMask >> i) & 1) == 1)
		{
			GetTrackName(client, i, sTrack, sizeof(sTrack));
			
			char sInfo[8];
			IntToString(i, sInfo, 8);

			menu.AddItem(sInfo, sTrack, ITEMDRAW_DEFAULT);

			iLastTrack = i;
		}
	}

	if(bonus && menu.ItemCount == 1)
	{
		Shavit_RestartTimer(client, iLastTrack, true, false);
		delete menu;
		return;
	}	

	if(menu.ItemCount == 0)
	{
		Shavit_PrintToChat(client, "%T", bonus ? "MapNoBonus":"UnZonedMap", client);

		delete menu;
		return;
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Track(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		int track = StringToInt(sInfo);

		Shavit_RestartTimer(param1, track, true, false);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

bool DoIHateMain(int client)
{
	char data[2];
	gH_IHateMain.Get(client, data, sizeof(data));
	return (data[0] == '1');
}

public Action Command_IHateMain(int client, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	bool bIHateMain = DoIHateMain(client);
	gH_IHateMain.Set(client, (bIHateMain) ? "0" : "1");
	Shavit_PrintToChat(client, (bIHateMain) ? ":)" : ":(");

	return Plugin_Handled;
}

public Action Command_TeleportEnd(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	int track = Track_Main;

	if(StrContains(sCommand, "sm_b", false) == 0)
	{
		if (args < 1)
		{
			track = Shavit_GetClientTrack(client);
		}
		else
		{
			char arg[6];
			GetCmdArg(1, arg, sizeof(arg));
			track = StringToInt(arg);
		}

		if (track < Track_Bonus || track > Track_Bonus_Last)
		{
			track = Track_Bonus;
		}
	}

	if (!gB_Zones || !(Shavit_ZoneExists(Zone_End, track) || gB_KZMap[track]))
	{
		Shavit_PrintToChat(client, "%T", "TPToEndZoneUndefined", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return Plugin_Handled;
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnEndPre);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_Finish(result);

	if (result > Plugin_Continue)
	{
		return Plugin_Handled;
	}

	if (!Shavit_StopTimer(client, false))
	{
		return Plugin_Handled;
	}

	Shavit_SetPracticeMode(client, true, false);

	Call_StartForward(gH_Forwards_OnEnd);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_Finish();

	return Plugin_Handled;
}

public Action Command_StopTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Shavit_StopTimer(client, false);

	return Plugin_Handled;
}

public Action Command_TogglePause(int client, int args)
{
	if(!(1 <= client <= MaxClients) || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}

	int iFlags = Shavit_CanPause(client);

	if((iFlags & CPR_NoTimer) > 0)
	{
		return Plugin_Handled;
	}

	if((iFlags & CPR_InStartZone) > 0)
	{
		Shavit_PrintToChat(client, "%T", "PauseStartZone", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if((iFlags & CPR_InEndZone) > 0)
	{
		Shavit_PrintToChat(client, "%T", "PauseEndZone", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	int iZoneStage;
	int iTrack = Shavit_GetClientTrack(client);
	bool InsideStage = iTrack == Track_Main ? Shavit_InsideZoneStage(client, iZoneStage):false;
	if((Shavit_IsOnlyStageMode(client) && InsideStage && iZoneStage == gA_Timers[client].iLastStage))
	{
		Shavit_PrintToChat(client, "%T", "PauseStageStartZone", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		return Plugin_Handled;
	}

	if((iFlags & CPR_ByConVar) > 0)
	{
		char sCommand[16];
		GetCmdArg(0, sCommand, 16);

		Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings.sVariable, sCommand, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if (gA_Timers[client].bClientPaused)
	{
		TeleportEntity(client, gF_PauseOrigin[client], gF_PauseAngles[client], gF_PauseVelocity[client]);
		ResumeTimer(client);

		Shavit_PrintToChat(client, "%T", "MessageUnpause", client, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
	else
	{
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

		PauseTimer(client);

		Shavit_PrintToChat(client, "%T", "MessagePause", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

public Action Command_Message(int client, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	ShowMessageSettingMenu(client, 0);

	return Plugin_Handled;
}

public Action Command_ToggleRepeat(int client, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if (!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "RepeatCommandAlive", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		return Plugin_Handled;
	}

	ChangeClientRepeat(client, !gB_PlayerRepeat[client]);

	return Plugin_Handled;
}

public Action Command_ToggleTriggers(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Shavit_SetTriggerDisable(client, !gB_DisableTriggers[client], false);

	return Plugin_Handled;
}

public void ChangeClientRepeat(int client, bool repeat)
{
	if(gB_PlayerRepeat[client] == repeat)
	{
		return;
	}

	CallOnRepeatChanged(client, gB_PlayerRepeat[client], repeat);
}

public void CallOnRepeatChanged(int client, bool old_value, bool new_value)
{
	gB_PlayerRepeat[client] = new_value;

	char sTrack[32];
	if(gA_Timers[client].iTimerTrack != Track_Main)
	{
		GetTrackName(client, gA_Timers[client].iTimerTrack, sTrack, 32);		
	}
	else
	{
		if(Shavit_GetStageCount(Track_Main) > 1)
		{
			FormatEx(sTrack, 32, "%T %d", "StageText", client, gA_Timers[client].iLastStage);			
		}
		else
		{
			gB_PlayerRepeat[client] = false;
			Shavit_PrintToChat(client, "%T", "RepeatOnLinearMap", client);
			return;
		}
	}

	if(gB_PlayerRepeat[client])
	{
		if(Shavit_RestartTimer(client, gA_Timers[client].iTimerTrack, false, false))
		{
			gA_Timers[client].bOnlyStageMode = true;
			Shavit_PrintToChat(client, "%T",  "EnabledTimerRepeat", client, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);
		}
		else
		{
			gB_PlayerRepeat[client] = false;
		}
	}
	else
	{
		Shavit_PrintToChat(client, "%T",  "DisableTimerRepeat", client, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);
	}
}

public Action Command_Timescale(int client, int args)
{
	if (!IsValidClient(client, true))
	{
		return Plugin_Handled;
	}

	if (GetStyleSettingFloat(gA_Timers[client].bsStyle, "tas_timescale") != -1.0)
	{
		Shavit_PrintToChat(client, "%T", "NoEditingTimescale", client);
		return Plugin_Handled;
	}

	if (args < 1)
	{
		Shavit_PrintToChat(client, "!timescale <number>");
		return Plugin_Handled;
	}

	char sArg[16];
	GetCmdArg(1, sArg, 16);
	float ts = StringToFloat(sArg);

	if (ts >= 0.01 && ts <= 1.0)
	{
		Shavit_SetClientTimescale(client, ts);
	}

	return Plugin_Handled;
}

public Action Command_TimescalePlus(int client, int args)
{
	if (!IsValidClient(client, true))
	{
		return Plugin_Handled;
	}

	if (GetStyleSettingFloat(gA_Timers[client].bsStyle, "tas_timescale") != -1.0)
	{
		Shavit_PrintToChat(client, "%T", "NoEditingTimescale", client);
		return Plugin_Handled;
	}

	float ts = 0.1;

	if (args > 0)
	{
		char sArg[16];
		GetCmdArg(1, sArg, 16);
		ts = StringToFloat(sArg);
	}

	if (ts >= 0.01)
	{
		ts += gA_Timers[client].fTimescale;

		if (ts > 1.0)
		{
			ts = 1.0;
		}

		Shavit_SetClientTimescale(client, ts);
	}

	return Plugin_Handled;
}

public Action Command_TimescaleMinus(int client, int args)
{
	if (!IsValidClient(client, true))
	{
		return Plugin_Handled;
	}

	if (GetStyleSettingFloat(gA_Timers[client].bsStyle, "tas_timescale") != -1.0)
	{
		Shavit_PrintToChat(client, "%T", "NoEditingTimescale", client);
		return Plugin_Handled;
	}

	float ts = 0.1;

	if (args > 0)
	{
		char sArg[16];
		GetCmdArg(1, sArg, 16);
		ts = StringToFloat(sArg);
	}

	if (ts >= 0.01)
	{
		float newts = ts;

		// very hacky I know but I hate formatting timescales and seeing 0.39999 because float subtraction is stupid
		for (int i = 0; i < 99; i++)
		{
			float x = newts + ts;

			if (x >= gA_Timers[client].fTimescale)
			{
				break;
			}

			newts = x;
		}

		if (newts < ts)
		{
			newts = ts;
		}

		if (newts < 0.01)
		{
			newts = 0.01;
		}

		Shavit_SetClientTimescale(client, newts);
	}

	return Plugin_Handled;
}

#if DEBUG
public Action Command_FinishTest(int client, int args)
{
	Shavit_FinishMap(client, gA_Timers[client].iTimerTrack);

	return Plugin_Handled;
}

public Action Command_Fling(int client, int args)
{
	float up[3];
	up[2] = 1000.0;
	SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", up);

	return Plugin_Handled;
}
#endif

public Action Command_DeleteMap(int client, int args)
{
	if(args == 0)
	{
		ReplyToCommand(client, "Usage: sm_deletemap <map>\nOnce a map is chosen, \"sm_deletemap confirm\" to run the deletion.");

		return Plugin_Handled;
	}

	char sArgs[PLATFORM_MAX_PATH];
	GetCmdArgString(sArgs, sizeof(sArgs));
	LowercaseString(sArgs);

	if(StrEqual(sArgs, "confirm") && strlen(gS_DeleteMap[client]) > 0)
	{
		Shavit_WR_DeleteMap(gS_DeleteMap[client]);
		ReplyToCommand(client, "Deleted all records for %s.", gS_DeleteMap[client]);

		if(gB_Zones)
		{
			Shavit_Zones_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all zones for %s.", gS_DeleteMap[client]);
		}

		if (gB_ReplayPlayback)
		{
			Shavit_Replay_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all replay data for %s.", gS_DeleteMap[client]);
		}

		if(gB_Rankings)
		{
			Shavit_Rankings_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all rankings for %s.", gS_DeleteMap[client]);
		}

		Shavit_LogMessage("%L - deleted all map data for `%s`", client, gS_DeleteMap[client]);
		ReplyToCommand(client, "Finished deleting data for %s.", gS_DeleteMap[client]);
		gS_DeleteMap[client] = "";
	}
	else
	{
		gS_DeleteMap[client] = sArgs;
		ReplyToCommand(client, "Map to delete is now %s.\nRun \"sm_deletemap confirm\" to delete all data regarding the map %s.", gS_DeleteMap[client], gS_DeleteMap[client]);
	}

	return Plugin_Handled;
}

public Action Command_NoclipSpeed(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(args == 0)
	{
		Shavit_PrintToChat(client, "%T", "ArgumentsMissing", client, "sm_noclipspeed <value> (2-30)");
		return Plugin_Handled;
	}

	char sCommand[8];
	GetCmdArg(1, sCommand, 8);
	float fNewNoclipSpeed = StringToFloat(sCommand);
	float fOldNoclipSpeed = sv_noclipspeed.FloatValue;

	if(fNewNoclipSpeed == fOldNoclipSpeed)
	{
		return Plugin_Handled;
	}

	if (fNewNoclipSpeed < 2.0 || fNewNoclipSpeed > 30.0)
	{
		Shavit_PrintToChat(client, "%T", "ArgumentsMissing", client, "sm_noclipspeed <value> (2-30)");
		return Plugin_Handled;
	}

	sv_noclipspeed.ReplicateToClient(client, sCommand);
	gF_NoclipSpeed[client] = fNewNoclipSpeed;

	Shavit_PrintToChat(client, "%T", "NoclipSpeedChanged", client, 
	gS_ChatStrings.sVariable, gS_ChatStrings.sText, 
	gS_ChatStrings.sVariable2, fOldNoclipSpeed, gS_ChatStrings.sText,
	gS_ChatStrings.sVariable2, fNewNoclipSpeed, gS_ChatStrings.sText);

	return Plugin_Handled;
}

public Action Command_Migration(int client, int args)
{
	if(args == 0)
	{
		ReplyToCommand(client, "Usage: sm_migration <migration id or \"all\" to run all migrationsd>.");

		return Plugin_Handled;
	}

	char sArg[16];
	GetCmdArg(1, sArg, 16);

	bool bApplyMigration[MIGRATIONS_END];

	if(StrEqual(sArg, "all"))
	{
		for(int i = 0; i < MIGRATIONS_END; i++)
		{
			bApplyMigration[i] = true;
		}
	}
	else
	{
		int iMigration = StringToInt(sArg);

		if(0 <= iMigration < MIGRATIONS_END)
		{
			bApplyMigration[iMigration] = true;
		}
	}

	for(int i = 0; i < MIGRATIONS_END; i++)
	{
		if(bApplyMigration[i])
		{
			ReplyToCommand(client, "Applying database migration %d", i);
			ApplyMigration(i);
		}
	}

	return Plugin_Handled;
}

public Action Command_WipePlayer(int client, int args)
{
	if(args == 0)
	{
		ReplyToCommand(client, "Usage: sm_wipeplayer <steamid3>\nAfter entering a SteamID, you will be prompted with a verification captcha.");

		return Plugin_Handled;
	}

	char sArgString[32];
	GetCmdArgString(sArgString, 32);

	if(strlen(gS_Verification[client]) == 0 || !StrEqual(sArgString, gS_Verification[client]))
	{
		gI_WipePlayerID[client] = SteamIDToAccountID(sArgString);

		if(gI_WipePlayerID[client] == 0)
		{
			Shavit_PrintToChat(client, "Entered SteamID (%s) is invalid. The range for valid SteamIDs is [U:1:1] to [U:1:4294967295].", sArgString);

			return Plugin_Handled;
		}

		char sAlphabet[] = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#";
		strcopy(gS_Verification[client], 8, "");

		for(int i = 0; i < 5; i++)
		{
			gS_Verification[client][i] = sAlphabet[GetRandomInt(0, sizeof(sAlphabet) - 1)];
		}

		Shavit_PrintToChat(client, "Preparing to delete all user data for SteamID %s[U:1:%u]%s. To confirm, enter %s!wipeplayer %s",
			gS_ChatStrings.sVariable, gI_WipePlayerID[client], gS_ChatStrings.sText, gS_ChatStrings.sVariable2, gS_Verification[client]);
	}
	else
	{
		Shavit_PrintToChat(client, "Deleting data for SteamID %s[U:1:%u]%s...",
			gS_ChatStrings.sVariable, gI_WipePlayerID[client], gS_ChatStrings.sText);

		Shavit_LogMessage("%L - wiped [U:1:%u]'s player data", client, gI_WipePlayerID[client]);
		DeleteUserData(client, gI_WipePlayerID[client]);

		strcopy(gS_Verification[client], 8, "");
		gI_WipePlayerID[client] = -1;
	}

	return Plugin_Handled;
}

public Action Command_WipeTrack(int client, int args)
{

	return Plugin_Handled;
}

public void Trans_DeleteRestOfUserSuccess(Database db, DataPack hPack, int numQueries, DBResultSet[] results, any[] queryData)
{
	hPack.Reset();
	int client = hPack.ReadCell();
	int iSteamID = hPack.ReadCell();
	delete hPack;

	Shavit_ReloadLeaderboards();

	Shavit_LogMessage("%L - wiped user data for [U:1:%u].", client, iSteamID);
	Shavit_PrintToChat(client, "Finished wiping timer data for user %s[U:1:%u]%s.", gS_ChatStrings.sVariable, iSteamID, gS_ChatStrings.sText);
}

public void Trans_DeleteRestOfUserFailed(Database db, DataPack hPack, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	hPack.Reset();
	hPack.ReadCell();
	int iSteamID = hPack.ReadCell();
	delete hPack;
	LogError("Timer error! Failed to wipe user data (wipe | delete user data/times, id [U:1:%u]). Reason: %s", iSteamID, error);
}

void DeleteRestOfUser(int iSteamID, DataPack hPack)
{
	Transaction trans = new Transaction();
	char sQuery[256];

	FormatEx(sQuery, 256, "DELETE FROM %splayertimes WHERE auth = %d;", gS_MySQLPrefix, iSteamID);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, 256, "DELETE FROM %sstagetimes WHERE auth = %d;", gS_MySQLPrefix, iSteamID);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, 256, "DELETE FROM %scptimes WHERE auth = %d;", gS_MySQLPrefix, iSteamID);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, 256, "DELETE FROM %scpwrs WHERE auth = %d;", gS_MySQLPrefix, iSteamID);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, 256, "DELETE FROM %sstyleplaytime WHERE auth = %d;", gS_MySQLPrefix, iSteamID);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, 256, "DELETE FROM %sstartpositions WHERE auth = %d;", gS_MySQLPrefix, iSteamID);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, 256, "DELETE FROM %susers WHERE auth = %d;", gS_MySQLPrefix, iSteamID);
	AddQueryLog(trans, sQuery);

	gH_SQL.Execute(trans, Trans_DeleteRestOfUserSuccess, Trans_DeleteRestOfUserFailed, hPack);
}

void DeleteUserData(int client, const int iSteamID)
{
	DataPack hPack = new DataPack();
	hPack.WriteCell(client);
	hPack.WriteCell(iSteamID);
	char sQuery[512];

	FormatEx(sQuery, sizeof(sQuery),
		"SELECT id, style, track, 0 AS stage, map FROM %swrs WHERE auth = %d "...
		"UNION ALL SELECT id, style, track, stage, map FROM %sstagewrs WHERE auth = %d;",
		gS_MySQLPrefix, iSteamID, gS_MySQLPrefix, iSteamID);

	QueryLog(gH_SQL, SQL_DeleteUserData_GetRecords_Callback, sQuery, hPack, DBPrio_High);
}

public void SQL_DeleteUserData_GetRecords_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	hPack.Reset();
	hPack.ReadCell(); /*int client = */
	int iSteamID = hPack.ReadCell();

	if(results == null)
	{
		LogError("Timer error! Failed to wipe user data (wipe | get player records). Reason: %s", error);
		delete hPack;
		return;
	}

	char map[PLATFORM_MAX_PATH];

	while(results.FetchRow())
	{
		int id = results.FetchInt(0);
		int style = results.FetchInt(1);
		int track = results.FetchInt(2);
		int stage = results.FetchInt(3);
		results.FetchString(4, map, sizeof(map));

		if(stage == 0)
		{
			Shavit_DeleteWR(style, track, map, iSteamID, id, false, false);			
		}
		else
		{
			Shavit_DeleteStageWR(style, track, stage, map, iSteamID, id, false, false);
		}
	}

	DeleteRestOfUser(iSteamID, hPack);
}

public Action Command_AutoBhop(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gB_Auto[client] = !gB_Auto[client];

	if (gB_Auto[client])
	{
		Shavit_PrintToChat(client, "%T", "AutobhopEnabled", client, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);
	}
	else
	{
		Shavit_PrintToChat(client, "%T", "AutobhopDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	char sAutoBhop[4];
	IntToString(view_as<int>(gB_Auto[client]), sAutoBhop, 4);
	SetClientCookie(client, gH_AutoBhopCookie, sAutoBhop);

	UpdateStyleSettings(client);

	return Plugin_Handled;
}

public Action Command_Style(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	// allow !style <number>
	if (args > 0)
	{
		char sArgs[16];
		GetCmdArg(1, sArgs, sizeof(sArgs));
		int style = StringToInt(sArgs);

		if (style < 0 || style >= Shavit_GetStyleCount())
		{
			return Plugin_Handled;
		}

		if (GetStyleSettingBool(style, "inaccessible"))
		{
			return Plugin_Handled;
		}

		ChangeClientStyle(client, style, true);
		return Plugin_Handled;
	}

	Menu menu = new Menu(StyleMenu_Handler);
	menu.SetTitle("%T", "StyleMenuTitle", client);

	int iStyleCount = Shavit_GetStyleCount();
	int iOrderedStyles[STYLE_LIMIT];
	Shavit_GetOrderedStyles(iOrderedStyles, iStyleCount);

	for(int i = 0; i < iStyleCount; i++)
	{
		int iStyle = iOrderedStyles[i];

		// this logic will prevent the style from showing in !style menu if it's specifically inaccessible
		// or just completely disabled
		if((GetStyleSettingBool(iStyle, "inaccessible") && GetStyleSettingInt(iStyle, "enabled") == 1) ||
		GetStyleSettingInt(iStyle, "enabled") == -1)
		{
			continue;
		}

		char sInfo[8];
		IntToString(iStyle, sInfo, 8);

		char sDisplay[64];

		if(GetStyleSettingBool(iStyle, "unranked"))
		{
			char sName[64];
			GetStyleSetting(iStyle, "name", sName, sizeof(sName));
			FormatEx(sDisplay, 64, "%T %s", "StyleUnranked", client, sName);
		}
		else
		{
			float time = Shavit_GetWorldRecord(iStyle, gA_Timers[client].iTimerTrack);

			if(time > 0.0)
			{
				char sTime[32];
				FormatSeconds(time, sTime, 32, false);

				char sWR[8];
				strcopy(sWR, 8, "WR");

				if (gA_Timers[client].iTimerTrack >= Track_Bonus)
				{
					strcopy(sWR, 8, "BWR");
				}

				char sName[64];
				GetStyleSetting(iStyle, "name", sName, sizeof(sName));
				FormatEx(sDisplay, 64, "%s - %s: %s", sName, sWR, sTime);
			}
			else
			{
				GetStyleSetting(iStyle, "name", sDisplay, sizeof(sDisplay));
			}
		}

		menu.AddItem(sInfo, sDisplay, (gA_Timers[client].bsStyle == iStyle || !Shavit_HasStyleAccess(client, iStyle))? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	}

	// should NEVER happen
	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "Nothing");
	}
	else if(menu.ItemCount <= ((gEV_Type == Engine_CSS)? 9:8))
	{
		menu.Pagination = MENU_NO_PAGINATION;
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int StyleMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);

		int style = StringToInt(info);

		if(style == -1)
		{
			return 0;
		}

		ChangeClientStyle(param1, style, true);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void CallOnTrackChanged(int client, int oldtrack, int newtrack)
{
	gA_Timers[client].iTimerTrack = newtrack;

	Call_StartForward(gH_Forwards_OnTrackChanged);
	Call_PushCell(client);
	Call_PushCell(oldtrack);
	Call_PushCell(newtrack);
	Call_Finish();

	if(oldtrack != newtrack)
	{
		if(gB_PlayerRepeat[client])
		{
			char sTrack[32];
			if(newtrack != Track_Main)
			{
				GetTrackName(client, newtrack, sTrack, 32);
				Shavit_PrintToChat(client, "%T", "EnabledTimerRepeat", client, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);				
			}
			else if(Shavit_GetStageCount(newtrack) < 2)
			{
				GetTrackName(client, oldtrack, sTrack, 32);
				ChangeClientRepeat(client, false);
				Shavit_PrintToChat(client, "%T", "DisableTimerRepeat", client, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);	
			}
			else
			{
				FormatEx(sTrack, 32, "%T 1", "StageText", client);
				Shavit_PrintToChat(client, "%T", "EnabledTimerRepeat", client, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);	
			}
		}
		else if (oldtrack == Track_Main && !DoIHateMain(client))
		{
			Shavit_StopChatSound();
			Shavit_PrintToChat(client, "%T", "TrackChangeFromMain", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		}		
	}
}

public any Native_PrintSteamIDOnce(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int steamid = GetNativeCell(2);

	if (gI_LastPrintedSteamID[client] != steamid && GetSteamAccountID(client) != steamid)
	{
		gI_LastPrintedSteamID[client] = steamid;

		char targetname[32+1], steam2[40], steam64[40];

		GetNativeString(3, targetname, sizeof(targetname));
		AccountIDToSteamID2(steamid, steam2, sizeof(steam2));
		AccountIDToSteamID64(steamid, steam64, sizeof(steam64));

		Shavit_PrintToChat(client, "%s: %s%s %s[U:1:%u]%s %s", targetname, gS_ChatStrings.sVariable, steam2, gS_ChatStrings.sText, steamid, gS_ChatStrings.sVariable, steam64);
	}

	return 1;
}

public any Native_UpdateLaggedMovement(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	bool user_timescale = GetNativeCell(2) != 0;
	UpdateLaggedMovement(client, user_timescale);
	return 1;
}

void UpdateLaggedMovement(int client, bool user_timescale)
{
	float style_laggedmovement =
		  GetStyleSettingFloat(gA_Timers[client].bsStyle, "timescale")
		* GetStyleSettingFloat(gA_Timers[client].bsStyle, "speed");

	float laggedmovement =
		  (user_timescale ? gA_Timers[client].fTimescale : 1.0)
		* style_laggedmovement;

	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", laggedmovement * gA_Timers[client].fplayer_speedmod);

	if (gB_Eventqueuefix)
	{
		SetEventsTimescale(client, style_laggedmovement);
	}
}

void CallOnStyleChanged(int client, int oldstyle, int newstyle, bool manual, bool noforward=false)
{
	gA_Timers[client].bsStyle = newstyle;

	if (!noforward)
	{
		Call_StartForward(gH_Forwards_OnStyleChanged);
		Call_PushCell(client);
		Call_PushCell(oldstyle);
		Call_PushCell(newstyle);
		Call_PushCell(gA_Timers[client].iTimerTrack);
		Call_PushCell(manual);
		Call_Finish();
	}

	float style_ts = GetStyleSettingFloat(newstyle, "tas_timescale");

	if (style_ts >= 0.0)
	{
		float newts = (style_ts > 0.0) ? style_ts : 1.0; // 🦎🦎🦎
		Shavit_SetClientTimescale(client, newts);
	}

	UpdateLaggedMovement(client, true);

	UpdateStyleSettings(client);

	SetEntityGravity(client, GetStyleSettingFloat(newstyle, "gravity"));
}

void CallOnTimescaleChanged(int client, float oldtimescale, float newtimescale)
{
	gA_Timers[client].fTimescale = newtimescale;
	Call_StartForward(gH_Forwards_OnTimescaleChanged);
	Call_PushCell(client);
	Call_PushCell(oldtimescale);
	Call_PushCell(newtimescale);
	Call_Finish();
}

void ChangeClientStyle(int client, int style, bool manual)
{
	if(!IsValidClient(client))
	{
		return;
	}

	if(!Shavit_HasStyleAccess(client, style))
	{
		if(manual)
		{
			Shavit_PrintToChat(client, "%T", "StyleNoAccess", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		}

		return;
	}

	if(manual)
	{
		Action result = Plugin_Continue;
		Call_StartForward(gH_Forwards_OnStyleCommandPre);
		Call_PushCell(client);
		Call_PushCell(gA_Timers[client].bsStyle);
		Call_PushCell(style);
		Call_PushCell(gA_Timers[client].iTimerTrack);
		Call_Finish(result);

		if (result > Plugin_Continue)
		{
			return;
		}

		if(!Shavit_StopTimer(client, false))
		{
			return;
		}

		char sName[64];
		GetStyleSetting(style, "name", sName, sizeof(sName));

		Shavit_PrintToChat(client, "%T", "StyleSelection", client, gS_ChatStrings.sStyle, sName, gS_ChatStrings.sText);
	}

	if(GetStyleSettingBool(style, "unranked"))
	{
		Shavit_PrintToChat(client, "%T", "UnrankedWarning", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	int aa_old = RoundToZero(GetStyleSettingFloat(gA_Timers[client].bsStyle, "airaccelerate"));
	int aa_new = RoundToZero(GetStyleSettingFloat(style, "airaccelerate"));

	if(aa_old != aa_new)
	{
		Shavit_PrintToChat(client, "%T", "NewAiraccelerate", client, aa_old, gS_ChatStrings.sVariable, aa_new, gS_ChatStrings.sText);
	}

	CallOnStyleChanged(client, gA_Timers[client].bsStyle, style, manual);

	if (gB_Zones && (Shavit_ZoneExists(Zone_Start, gA_Timers[client].iTimerTrack) || gB_KZMap[gA_Timers[client].iTimerTrack]))
	{
		Shavit_RestartTimer(client, gA_Timers[client].iTimerTrack, false, true);
	}

	char sStyle[4];
	IntToString(style, sStyle, 4);

	SetClientCookie(client, gH_StyleCookie, sStyle);
}

public void Shavit_OnStageChanged(int client, int oldstage, int newstage)
{

}

// used as an alternative for games where player_jump isn't a thing, such as TF2
public void Shavit_Bhopstats_OnLeaveGround(int client, bool jumped, bool ladder)
{
	if(gB_HookedJump || !jumped || ladder)
	{
		return;
	}

	DoJump(client);
}

public void Player_Jump(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	DoJump(client);
}

void DoJump(int client)
{
	if (gA_Timers[client].bTimerEnabled && !gA_Timers[client].bClientPaused)
	{
		gA_Timers[client].iJumps++;
		gA_Timers[client].bJumped = true;
	}

	// TF2 doesn't use stamina
	if (gEV_Type != Engine_TF2 && (GetStyleSettingBool(gA_Timers[client].bsStyle, "easybhop")) || (gB_Zones && Shavit_InsideZone(client, Zone_Easybhop, gA_Timers[client].iTimerTrack)))
	{
		SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
	}

	RequestFrame(VelocityChanges, GetClientSerial(client));
}

void VelocityChanges(int data)
{
	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	int style = gA_Timers[client].bsStyle;

#if 0
	if(GetStyleSettingBool(style, "force_timescale"))
	{
		UpdateLaggedMovement(client, true);
	}
#endif

	float fAbsVelocity[3], fAbsOrig[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);
	fAbsOrig = fAbsVelocity;

	float fSpeed = (SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0)));

	if(fSpeed != 0.0)
	{
		float fVelocityMultiplier = GetStyleSettingFloat(style, "velocity");
		float fVelocityBonus = GetStyleSettingFloat(style, "bonus_velocity");
		float fMin = GetStyleSettingFloat(style, "min_velocity");

		if(fVelocityMultiplier != 0.0)
		{
			fAbsVelocity[0] *= fVelocityMultiplier;
			fAbsVelocity[1] *= fVelocityMultiplier;
		}

		if(fVelocityBonus != 0.0)
		{
			float x = fSpeed / (fSpeed + fVelocityBonus);
			fAbsVelocity[0] /= x;
			fAbsVelocity[1] /= x;
		}

		if(fMin != 0.0 && fSpeed < fMin)
		{
			float x = (fSpeed / fMin);
			fAbsVelocity[0] /= x;
			fAbsVelocity[1] /= x;
		}
	}

	float fJumpMultiplier = GetStyleSettingFloat(style, "jump_multiplier");
	float fJumpBonus = GetStyleSettingFloat(style, "jump_bonus");

	if(fJumpMultiplier != 0.0)
	{
		fAbsVelocity[2] *= fJumpMultiplier;
	}

	if(fJumpBonus != 0.0)
	{
		fAbsVelocity[2] += fJumpBonus;
	}

	float fSpeedLimit = GetStyleSettingFloat(gA_Timers[client].bsStyle, "velocity_limit");

	if (gB_Zones && Shavit_InsideZone(client, Zone_CustomSpeedLimit, -1))
	{
		fSpeedLimit = gF_ZoneSpeedLimit[client];
	}

	if (fSpeedLimit > 0.0)
	{
		float fSpeed_New = (SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0)));

		if (fSpeedLimit != 0.0 && fSpeed_New > 0.0)
		{
			float fScale = fSpeedLimit / fSpeed_New;

			if (fScale < 1.0)
			{
				fAbsVelocity[0] *= fScale;
				fAbsVelocity[1] *= fScale;
			}
		}
	}

	if (fAbsOrig[0] == fAbsVelocity[0] && fAbsOrig[1] == fAbsVelocity[1] && fAbsOrig[2] == fAbsVelocity[2])
	{
		return;		
	}


	if(!gCV_VelocityTeleport.BoolValue)
	{
		SetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);
	}
	else
	{
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fAbsVelocity);
	}
}

public void Player_Death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	ResumeTimer(client);
	StopTimer(client);
}

public int Native_GetDatabase(Handle handler, int numParams)
{
	if (numParams > 0)
		SetNativeCellRef(1, gI_Driver);
	return gH_SQL ? view_as<int>(CloneHandle(gH_SQL, handler)) : 0;
}

public int Native_GetClientTime(Handle handler, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].fCurrentTime);
}

public int Native_GetClientStageTime(Handle handler, int numParas)
{
	int client = GetNativeCell(1);

	return view_as<int>(gA_Timers[client].fCurrentTime - gA_Timers[client].aStageStartInfo.fStageStartTime);
}

public int Native_GetClientTrack(Handle handler, int numParams)
{
	return gA_Timers[GetNativeCell(1)].iTimerTrack;
}

public int Native_SetClientTrack(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	CallOnTrackChanged(client, gA_Timers[client].iTimerTrack, GetNativeCell(2));
	return 0;
}

public int Native_GetClientJumps(Handle handler, int numParams)
{
	return gA_Timers[GetNativeCell(1)].iJumps;
}

public int Native_GetBhopStyle(Handle handler, int numParams)
{
	return gA_Timers[GetNativeCell(1)].bsStyle;
}

public int Native_GetTimerStatus(Handle handler, int numParams)
{
	return view_as<int>(GetTimerStatus(GetNativeCell(1)));
}

public int Native_IsKZMap(Handle handler, int numParams)
{
	if (numParams < 1)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Missing track parameter.");
	}

	return gB_KZMap[GetNativeCell(1)];
}

public int Native_StartTimer(Handle handler, int numParams)
{
	StartTimer(GetNativeCell(1), GetNativeCell(2));
	return 0;
}

public int Native_StartStageTimer(Handle handler, int numParams)
{
	StartStageTimer(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3), false, false);
	return 0;
}

public int Native_StopTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	bool bBypass = (numParams < 2 || view_as<bool>(GetNativeCell(2)));

	if(!bBypass)
	{
		bool bResult = true;
		Call_StartForward(gH_Forwards_StopPre);
		Call_PushCell(client);
		Call_PushCell(gA_Timers[client].iTimerTrack);
		Call_Finish(bResult);

		if(!bResult)
		{
			return false;
		}
	}

	StopTimer(client);

	Call_StartForward(gH_Forwards_Stop);
	Call_PushCell(client);
	Call_PushCell(gA_Timers[client].iTimerTrack);
	Call_Finish();

	return true;
}

public int Native_CanPause(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int iFlags = 0;

	if(!gCV_Pause.BoolValue)
	{
		iFlags |= CPR_ByConVar;
	}

	if (!gA_Timers[client].bTimerEnabled)
	{
		iFlags |= CPR_NoTimer;
	}

	if (gB_Zones)
	{
		if (Shavit_InsideZone(client, Zone_Start, gA_Timers[client].iTimerTrack))
		{
			iFlags |= CPR_InStartZone;
		}

		if (Shavit_InsideZone(client, Zone_End, gA_Timers[client].iTimerTrack))
		{
			iFlags |= CPR_InEndZone;
		}
	}

	if(GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") == -1 && GetEntityMoveType(client) != MOVETYPE_LADDER)
	{
		iFlags |= CPR_NotOnGround;
	}

	float vel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
	if (vel[0] != 0.0 || vel[1] != 0.0 || vel[2] != 0.0)
	{
		iFlags |= CPR_Moving;
	}


	float CS_PLAYER_DUCK_SPEED_IDEAL = 8.0;
	bool bDucked, bDucking;
	float fDucktime, fDuckSpeed = CS_PLAYER_DUCK_SPEED_IDEAL;

	if(gEV_Type != Engine_TF2)
	{
		bDucked = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucked"));
		bDucking = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucking"));

		if(gEV_Type == Engine_CSS)
		{
			fDucktime = GetEntPropFloat(client, Prop_Send, "m_flDucktime");
		}
		else if(gEV_Type == Engine_CSGO)
		{
			fDucktime = GetEntPropFloat(client, Prop_Send, "m_flDuckAmount");
			fDuckSpeed = GetEntPropFloat(client, Prop_Send, "m_flDuckSpeed");
		}
	}

	if (bDucked || bDucking || fDucktime > 0.0 || fDuckSpeed < CS_PLAYER_DUCK_SPEED_IDEAL || GetClientButtons(client) & IN_DUCK)
	{
		iFlags |= CPR_Duck;
	}

	return iFlags;
}

public int Native_ChangeClientStyle(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int style = GetNativeCell(2);
	bool force = view_as<bool>(GetNativeCell(3));
	bool manual = view_as<bool>(GetNativeCell(4));
	bool noforward = view_as<bool>(GetNativeCell(5));

	if(force || Shavit_HasStyleAccess(client, style))
	{
		CallOnStyleChanged(client, gA_Timers[client].bsStyle, style, manual, noforward);

		return true;
	}

	return false;
}

public Action Shavit_OnFinishPre(int client, timer_snapshot_t snapshot)
{
	float minimum_time = GetStyleSettingFloat(snapshot.bsStyle, snapshot.iTimerTrack == Track_Main ? "minimum_time" : "minimum_time_bonus");

	if (snapshot.fCurrentTime < minimum_time)
	{
		Shavit_PrintToChat(client, "%T", "TimeUnderMinimumTime", client, minimum_time, snapshot.fCurrentTime, snapshot.iTimerTrack == Track_Main ? "minimum_time" : "minimum_time_bonus");
		Shavit_StopTimer(client);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Shavit_OnFinishStagePre(int client, timer_snapshot_t snapshot)
{
	float minimum_time = GetStyleSettingFloat(snapshot.bsStyle, "minimum_time_stage");

	if (snapshot.fCurrentTime < minimum_time)
	{
		Shavit_PrintToChat(client, "%T", "TimeUnderMinimumTime", client, minimum_time, snapshot.fCurrentTime, snapshot.iTimerTrack == Track_Main ? "minimum_time" : "minimum_time_bonus");
			
		if(Shavit_IsOnlyStageMode(client))
		{
			Shavit_StopTimer(client, false);
		}
		
		return Plugin_Stop;
	}

	if (!snapshot.bStageTimeValid)
	{
		if(Shavit_IsOnlyStageMode(client))
		{
			Shavit_StopTimer(client, false);
		}

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void CalculateRunTime(timer_snapshot_t s, bool stage, bool include_end_offset)
{
	float ticks = float(s.iFullTicks) + (s.iFractionalTicks / 10000.0);

	if (gCV_UseOffsets.BoolValue)
	{
		ticks += stage ? s.aStageStartInfo.fZoneOffset[Zone_Start]:s.fZoneOffset[Zone_Start];

		if (include_end_offset)
		{
			if(stage)
			{
				ticks -= (1.0 - s.aStageStartInfo.fZoneOffset[Zone_End]);
			}
			else
			{
				ticks -= (1.0 - s.fZoneOffset[Zone_End]);
			}
		}
	}

	s.fCurrentTime = ticks * GetTickInterval();
}

public int Native_FinishMap(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int timestamp = GetTime();

	if (!gA_Timers[client].iFullTicks)
	{
		return 0;
	}

	if(gCV_UseOffsets.BoolValue)
	{
		CalculateTickIntervalOffset(client, Zone_End, false);

		if(gCV_DebugOffsets.BoolValue)
		{
			char sOffsetMessage[100];
			char sOffsetDistance[8];
			FormatEx(sOffsetDistance, 8, "%.1f", gA_Timers[client].fDistanceOffset[Zone_End]);
			FormatEx(sOffsetMessage, sizeof(sOffsetMessage), "[END] %T %d", "DebugOffsets", client, gA_Timers[client].fZoneOffset[Zone_End], sOffsetDistance, gA_Timers[client].iZoneIncrement);
			PrintToConsole(client, "%s", sOffsetMessage);
			Shavit_StopChatSound();
			Shavit_PrintToChat(client, "%s", sOffsetMessage);
		}
	}

	float fSpeed[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);
	float fEndVelocity = GetVectorLength(fSpeed);

	CalculateRunTime(gA_Timers[client], false, true);

	if(gA_Timers[client].iTimerTrack == Track_Main && Shavit_GetStageCount(Track_Main) > 1)
	{
		gA_Timers[client].fCPTimes[gA_Timers[client].iLastStage] = gA_Timers[client].fCurrentTime;		
	}

	if (gA_Timers[client].fCurrentTime <= 0.11)
	{
		Shavit_StopTimer(client);
		return 0;
	}

	timer_snapshot_t snapshot;
	BuildSnapshot(client, snapshot);

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_FinishPre);
	Call_PushCell(client);
	Call_PushArrayEx(snapshot, sizeof(timer_snapshot_t), SM_PARAM_COPYBACK);
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return 0;
	} 

#if DEBUG
	PrintToServer("0x%X %f -- startoffset=%f endoffset=%f fullticks=%d fracticks=%d", snapshot.fCurrentTime, snapshot.fCurrentTime, snapshot.fZoneOffset[Zone_Start], snapshot.fZoneOffset[Zone_End], snapshot.iFullTicks, snapshot.iFractionalTicks);
#endif

	Call_StartForward(gH_Forwards_Finish);
	Call_PushCell(client);

	Call_PushCell(snapshot.bsStyle);
	Call_PushCell(snapshot.fCurrentTime);
	Call_PushCell(snapshot.iJumps);
	Call_PushCell(snapshot.iStrafes);
	Call_PushCell(CalcSync(snapshot));
	Call_PushCell(snapshot.iTimerTrack);
	Call_PushCell(Shavit_GetClientPB(client, snapshot.bsStyle, snapshot.iTimerTrack)); // oldtime
	Call_PushCell(CalcPerfs(snapshot));
	Call_PushCell(snapshot.fAvgVelocity);
	Call_PushCell(snapshot.fMaxVelocity);
	Call_PushCell(snapshot.fStartVelocity);
	Call_PushCell(fEndVelocity);

	Call_PushCell(timestamp);
	Call_Finish();

	StopTimer(client);

	if(gB_PlayerRepeat[client])
	{
		Shavit_TeleportToStartZone(client, snapshot.iTimerTrack, 1);
	}

	return 1;
}

public int Native_FinishStage(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);
	int stage = GetNativeCell(3);
	int timestamp = GetTime();

	if(gCV_UseOffsets.BoolValue)
	{
		CalculateTickIntervalOffset(client, Zone_End, !gA_Timers[client].bOnlyStageMode && stage > 1);

		if(gCV_DebugOffsets.BoolValue)
		{
			char sOffsetMessage[100];
			char sOffsetDistance[8];
			FormatEx(sOffsetDistance, 8, "%.1f", gA_Timers[client].aStageStartInfo.fDistanceOffset[Zone_End]);
			FormatEx(sOffsetMessage, sizeof(sOffsetMessage), "[END] %T %d", "DebugOffsets", client, gA_Timers[client].aStageStartInfo.fZoneOffset[Zone_End], sOffsetDistance, gA_Timers[client].aStageStartInfo.iZoneIncrement);
			PrintToConsole(client, "%s", sOffsetMessage);
			Shavit_StopChatSound();
			Shavit_PrintToChat(client, "%s", sOffsetMessage);
		}
	}

	float fSpeed[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);
	float fEndVelocity = GetVectorLength(fSpeed);

	timer_snapshot_t end;
	Shavit_SaveSnapshot(client, end, sizeof(end));

	if(!gA_Timers[client].bOnlyStageMode && stage > 1)
	{
		end.fCurrentTime -= end.aStageStartInfo.fStageStartTime;
		end.iFullTicks -= end.aStageStartInfo.iFullTicks;
		end.iFractionalTicks -= end.aStageStartInfo.iFractionalTicks;
		end.iJumps -= end.aStageStartInfo.iJumps;
		end.iStrafes -= end.aStageStartInfo.iStrafes;
		end.iGoodGains -= end.aStageStartInfo.iGoodGains;
		end.iTotalMeasures -= end.aStageStartInfo.iTotalMeasures;
		end.fMaxVelocity = end.aStageStartInfo.fMaxVelocity;
		end.fAvgVelocity = end.aStageStartInfo.fAvgVelocity;
	}

	CalculateRunTime(end, !end.bOnlyStageMode && stage > 1, true);

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_FinishStagePre);
	Call_PushCell(client);
	Call_PushArrayEx(end, sizeof(timer_snapshot_t), SM_PARAM_COPYBACK);
	Call_Finish(result);

	if(result != Plugin_Continue)
	{
		if(gB_PlayerRepeat[client])
		{
			Shavit_TeleportToStartZone(client, track, stage);
			return 0;
		}

		return 0;
	}

	Call_StartForward(gH_Forwards_FinishStage);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_PushCell(end.bsStyle);
	Call_PushCell(stage);
	Call_PushCell(end.fCurrentTime);
	Call_PushCell(Shavit_GetClientStagePB(client, end.bsStyle, stage));
	Call_PushCell(end.iJumps);
	Call_PushCell(end.iStrafes);
	Call_PushCell(CalcSync(end));
	Call_PushCell(CalcPerfs(end));
	Call_PushCell(end.fAvgVelocity);
	Call_PushCell(end.fMaxVelocity);
	Call_PushCell(end.aStageStartInfo.fStartVelocity);
	Call_PushCell(fEndVelocity);
	Call_PushCell(timestamp);	//13 total
	Call_Finish();

	if(gA_Timers[client].bOnlyStageMode)
	{
		Shavit_StopTimer(client);

		if(gB_PlayerRepeat[client])
		{
			Shavit_TeleportToStartZone(client, track, stage);
			return 0;
		}
	}
	else
	{
		gA_Timers[client].fStageFinishTimes[stage] = end.fCurrentTime;
	}

	return 1;
}

public int Native_PauseTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	GetClientAbsOrigin(client, gF_PauseOrigin[client]);
	GetClientEyeAngles(client, gF_PauseAngles[client]);
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", gF_PauseVelocity[client]);

	PauseTimer(client);
	return 1;
}

public any Native_GetZoneOffset(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int zonetype = GetNativeCell(2);

	if(zonetype > 1 || zonetype < 0)
	{
		return ThrowNativeError(32, "ZoneType is out of bounds");
	}

	return gA_Timers[client].fZoneOffset[zonetype];
}

public any Native_GetDistanceOffset(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int zonetype = GetNativeCell(2);

	if(zonetype > 1 || zonetype < 0)
	{
		return ThrowNativeError(32, "ZoneType is out of bounds");
	}

	return gA_Timers[client].fDistanceOffset[zonetype];
}

public int Native_ResumeTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	ResumeTimer(client);

	if(numParams >= 2 && view_as<bool>(GetNativeCell(2))) // teleport?
	{
		TeleportEntity(client, gF_PauseOrigin[client], gF_PauseAngles[client], gF_PauseVelocity[client]);
	}

	return 1;
}

public int Native_StopChatSound(Handle handler, int numParams)
{
	gB_StopChatSound = true;
	return 1;
}

public int Native_GetMessageSetting(Handle plugin, int numParams)
{
	return gI_MessageSettings[GetNativeCell(1)];
}

public int Native_PrintToChatAll(Handle plugin, int numParams)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			SetGlobalTransTarget(i);

			bool previousStopChatSound = gB_StopChatSound;
			SemiNative_PrintToChat(i, 1);
			gB_StopChatSound = previousStopChatSound;
		}
	}

	gB_StopChatSound = false;
	return 1;
}

public int Native_PrintToChat(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	return SemiNative_PrintToChat(client, 2);
}

public int SemiNative_PrintToChat(int client, int formatParam)
{
	bool stopChatSound = gB_StopChatSound;
	gB_StopChatSound = false;

	int iWritten;
	char sBuffer[256];
	char sInput[300];
	FormatNativeString(0, formatParam, formatParam+1, sizeof(sInput), iWritten, sInput);

	char sTime[50];

	if (gCV_TimeInMessages.BoolValue)
	{
		FormatTime(sTime, sizeof(sTime), gB_Protobuf ? "%H:%M:%S " : "\x01%H:%M:%S ");
	}

	// space before message needed show colors in cs:go
	// strlen(sBuffer)>252 is when the CSS server stops sending the messages
	// css user message size limit is 255. byte for client, byte for chatsound, 252 chars + 1 null terminator = 255
	FormatEx(sBuffer, (gB_Protobuf ? sizeof(sBuffer) : 253), "%s%s%s%s%s%s", (gB_Protobuf ? " ":""), sTime, gS_ChatStrings.sPrefix, (gS_ChatStrings.sPrefix[0] != 0 ? " " : ""), gS_ChatStrings.sText, sInput);

	if(client == 0)
	{
		PrintToServer("%s", sBuffer);
		return false;
	}

	if(!IsClientInGame(client))
	{
		return false;
	}

	Handle hSayText2 = StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);

	if(gB_Protobuf)
	{
		Protobuf pbmsg = UserMessageToProtobuf(hSayText2);
		pbmsg.SetInt("ent_idx", client);
		pbmsg.SetBool("chat", !(stopChatSound || gCV_NoChatSound.BoolValue));
		pbmsg.SetString("msg_name", sBuffer);

		// needed to not crash
		for(int i = 1; i <= 4; i++)
		{
			pbmsg.AddString("params", "");
		}
	}
	else
	{
		BfWrite bfmsg = UserMessageToBfWrite(hSayText2);
		bfmsg.WriteByte(client);
		bfmsg.WriteByte(!(stopChatSound || gCV_NoChatSound.BoolValue));
		bfmsg.WriteString(sBuffer);
	}

	EndMessage();
	return true;
}

public int Native_GotoEnd(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);

	Shavit_SetPracticeMode(client, true, false);
	Shavit_StopTimer(client, true);

	Call_StartForward(gH_Forwards_OnEnd);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_Finish();

	return 1;
}

public int Native_RestartTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);
	bool tostartzone = GetNativeCell(3);
	bool force = (numParams < 4) || GetNativeCell(4);

	if (!force)
	{
		Action result = Plugin_Continue;
		Call_StartForward(gH_Forwards_OnRestartPre);
		Call_PushCell(client);
		Call_PushCell(track);
		Call_Finish(result);

		if (result > Plugin_Continue)
		{
			return 0;
		}
	}

	if (gA_Timers[client].bTimerEnabled && !Shavit_StopTimer(client, force))
	{
		return 0;
	}

	if (gA_Timers[client].iTimerTrack != track)
	{
		CallOnTrackChanged(client, gA_Timers[client].iTimerTrack, track);
	}

	SetEntityMoveType(client, MOVETYPE_WALK);
	gI_LastNoclipTick[client] = 0;
	gA_Timers[client].bPracticeMode = false;

	Call_StartForward(gH_Forwards_OnRestart);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_PushCell(tostartzone);
	Call_Finish();

	return 1;
}

float CalcPerfs(timer_snapshot_t s)
{
	return (s.iMeasuredJumps == 0) ? 100.0 : (s.iPerfectJumps / float(s.iMeasuredJumps) * 100.0);
}

public int Native_GetPerfectJumps(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	return view_as<int>(CalcPerfs(gA_Timers[client]));
}

public int Native_GetStrafeCount(Handle handler, int numParams)
{
	return gA_Timers[GetNativeCell(1)].iStrafes;
}

float CalcSync(timer_snapshot_t s)
{
	return GetStyleSettingBool(s.bsStyle, "sync") ? ((s.iGoodGains == 0) ? 0.0 : (s.iGoodGains / float(s.iTotalMeasures) * 100.0)):-1.0;
}

public int Native_GetSync(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	return view_as<int>(CalcSync(gA_Timers[client]));
}

public int Native_GetChatStrings(Handle handler, int numParams)
{
	int type = GetNativeCell(1);
	int size = GetNativeCell(3);

	switch(type)
	{
		case sMessagePrefix: return SetNativeString(2, gS_ChatStrings.sPrefix, size);
		case sMessageText: return SetNativeString(2, gS_ChatStrings.sText, size);
		case sMessageWarning: return SetNativeString(2, gS_ChatStrings.sWarning, size);
		case sMessageVariable: return SetNativeString(2, gS_ChatStrings.sVariable, size);
		case sMessageVariable2: return SetNativeString(2, gS_ChatStrings.sVariable2, size);
		case sMessageStyle: return SetNativeString(2, gS_ChatStrings.sStyle, size);
	}

	return -1;
}

public int Native_GetChatStringsStruct(Handle plugin, int numParams)
{
	if (GetNativeCell(2) != sizeof(chatstrings_t))
	{
		return ThrowNativeError(200, "chatstrings_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins", GetNativeCell(2), sizeof(chatstrings_t));
	}

	return SetNativeArray(1, gS_ChatStrings, sizeof(gS_ChatStrings));
}

public int Native_SetTriggerDisable(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	bool status = view_as<bool>(GetNativeCell(2));
	bool bBypass = (numParams < 3 || view_as<bool>(GetNativeCell(3)));

	if(status == gB_DisableTriggers[client])
	{
		return 0;
	}

	if(!bBypass)
	{
		bool bResult = true;
		
		Call_StartForward(gH_Forwards_OnToggleTriggersPre);
		Call_PushCell(client);
		Call_PushCell(status);
		Call_Finish(bResult);

		if(!bResult)
		{
			return 0;
		}
	}

	StopTimer(client);
	gB_DisableTriggers[client] = status;
	Shavit_PrintToChat(client, "%T", gB_DisableTriggers[client] ? "TriggerDisabled" : "TriggerEnabled", client, gB_DisableTriggers[client] ? gS_ChatStrings.sWarning:gS_ChatStrings.sVariable, gS_ChatStrings.sText);

	Call_StartForward(gH_Forwards_OnToggleTriggers);
	Call_PushCell(client);
	Call_PushCell(status);
	Call_Finish();

	return 0;
}

public int Native_IsTriggerDisabled(Handle handler, int numParams)
{
	return gB_DisableTriggers[GetNativeCell(1)];
}

public int Native_SetPracticeMode(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	bool practice = view_as<bool>(GetNativeCell(2));
	bool alert = view_as<bool>(GetNativeCell(3));

	if(alert && practice && !gA_Timers[client].bPracticeMode && (gI_MessageSettings[client] & MSG_PRACALERT) == 0 && !(gCV_DisablePracticeModeOnStart.BoolValue && Shavit_InsideZone(client, Zone_Start, -1)))
	{
		Shavit_PrintToChat(client, "%T", "PracticeModeAlert", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		
		if(!gCV_DisablePracticeModeOnStart.BoolValue)
		{
			Shavit_PrintToChat(client, "%T", "PracticeModeTips", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);			
		}
	}

	gA_Timers[client].bPracticeMode = practice;

	return 1;
}

public int Native_SetOnlyStageMode(Handle handler, int numParams)
{
	gA_Timers[GetNativeCell(1)].bOnlyStageMode = GetNativeCell(2);

	return 1;
}

public int Native_SetClientRepeat(Handle handler, int numParams)
{
	ChangeClientRepeat(GetNativeCell(1), GetNativeCell(2));

	return 0;
}

public int Native_IsPaused(Handle handler, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].bClientPaused);
}

public int Native_IsPracticeMode(Handle handler, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].bPracticeMode);
}

public int Native_IsOnlyStageMode(Handle handler, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].bOnlyStageMode);
}

public int Native_IsClientRepeat(Handle handler, int numParams)
{
	return view_as<int>(gB_PlayerRepeat[GetNativeCell(1)]);
}

public int Native_SaveSnapshot(Handle handler, int numParams)
{
	if(GetNativeCell(3) != sizeof(timer_snapshot_t))
	{
		return ThrowNativeError(200, "timer_snapshot_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(3), sizeof(timer_snapshot_t));
	}

	int client = GetNativeCell(1);

	timer_snapshot_t snapshot;
	BuildSnapshot(client, snapshot);
	return SetNativeArray(2, snapshot, sizeof(timer_snapshot_t));
}

public int Native_LoadSnapshot(Handle handler, int numParams)
{
	if(GetNativeCell(3) != sizeof(timer_snapshot_t))
	{
		return ThrowNativeError(200, "timer_snapshot_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(3), sizeof(timer_snapshot_t));
	}

	int client = GetNativeCell(1);

	timer_snapshot_t snapshot;
	GetNativeArray(2, snapshot, sizeof(timer_snapshot_t));
	snapshot.fTimescale = (snapshot.fTimescale > 0.0) ? snapshot.fTimescale : 1.0;

	bool force = GetNativeCell(4);

	if (!Shavit_HasStyleAccess(client, snapshot.bsStyle) && !force)
	{
		return 0;
	}

	if (gA_Timers[client].iTimerTrack != snapshot.iTimerTrack)
	{
		CallOnTrackChanged(client, gA_Timers[client].iTimerTrack, snapshot.iTimerTrack);
	}

	if (snapshot.iTimerTrack == Track_Main && !snapshot.bOnlyStageMode)
	{
		ChangeClientRepeat(client, false);
	}

	if (gA_Timers[client].bsStyle != snapshot.bsStyle)
	{
		CallOnStyleChanged(client, gA_Timers[client].bsStyle, snapshot.bsStyle, false);
	}

	if (gA_Timers[client].iLastStage != snapshot.iLastStage)
	{
		ChangeClientLastStage(client, snapshot.iLastStage);
	}

	float oldts = gA_Timers[client].fTimescale;

	gA_Timers[client] = snapshot;
	gA_Timers[client].bClientPaused = snapshot.bClientPaused && snapshot.bTimerEnabled;

	if (GetStyleSettingFloat(snapshot.bsStyle, "tas_timescale") < 0.0)
	{
		Shavit_SetClientTimescale(client, oldts);
	}

	if (gB_DisableTriggers[client])
	{
		StopTimer(client);
	}

	return 1;
}


public int Native_LogMessage(Handle plugin, int numParams)
{
	char sPlugin[32];

	if(!GetPluginInfo(plugin, PlInfo_Name, sPlugin, 32))
	{
		GetPluginFilename(plugin, sPlugin, 32);
	}

	static int iWritten = 0;

	char sBuffer[300];
	FormatNativeString(0, 1, 2, 300, iWritten, sBuffer);

	LogToFileEx(gS_LogPath, "[%s] %s", sPlugin, sBuffer);
	return 1;
}

public int Native_MarkKZMap(Handle handler, int numParams)
{
	if (numParams < 1)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Missing track parameter.");
	}

	gB_KZMap[GetNativeCell(1)] = true;
	return 0;
}

public int Native_GetClientTimescale(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	return view_as<int>(gA_Timers[client].fTimescale);
}

public int Native_SetClientTimescale(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	float timescale = GetNativeCell(2);

	timescale = float(RoundFloat((timescale * 10000.0)))/10000.0;

	if (timescale != gA_Timers[client].fTimescale && timescale > 0.0)
	{
		CallOnTimescaleChanged(client, gA_Timers[client].fTimescale, timescale);
		UpdateLaggedMovement(client, true);
	}

	return 1;
}

public int Native_GetClientStageFinishTimes(Handle plugin, int numParams)
{
	return SetNativeArray(2, gA_Timers[GetNativeCell(1)].fStageFinishTimes, MAX_STAGES);
}

public int Native_SetClientStageFinishTimes(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	float times[MAX_STAGES];

	GetNativeArray(2, times, MAX_STAGES);
	gA_Timers[client].fStageFinishTimes = times;

	return 0;
}

public int Native_GetClientStageFinishTime(Handle plugin, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].fStageFinishTimes[GetNativeCell(2)]);
}

public int Native_SetClientStageFinishTime(Handle plugin, int numParams)
{
	gA_Timers[GetNativeCell(1)].fStageFinishTimes[GetNativeCell(2)] = GetNativeCell(3);

	return 0;
}

public int Native_GetClientStageAttempts(Handle plugin, int numParams)
{
	return SetNativeArray(2, gA_Timers[GetNativeCell(1)].iStageAttempts, MAX_STAGES);
}

public int Native_SetClientStageAttempts(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int attempts[MAX_STAGES];

	GetNativeArray(2, attempts, MAX_STAGES);
	gA_Timers[client].iStageAttempts = attempts;

	return 0;
}

public int Native_GetClientStageAttempt(Handle plugin, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].iStageAttempts[GetNativeCell(2)]);
}

public int Native_SetClientStageAttempt(Handle plugin, int numParams)
{
	int attempts = GetNativeCell(3);

	if(attempts <= 0)
	{
		gA_Timers[GetNativeCell(1)].iStageAttempts[GetNativeCell(2)]++;
	}
	else
	{
		gA_Timers[GetNativeCell(1)].iStageAttempts[GetNativeCell(2)] = attempts;
	}

	return 0;
}


public int Native_GetClientCPTimes(Handle plugin, int numParams)
{
	return SetNativeArray(2, gA_Timers[GetNativeCell(1)].fCPTimes, MAX_STAGES);
}

public int Native_SetClientCPTimes(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	float times[MAX_STAGES];

	GetNativeArray(2, times, MAX_STAGES);
	gA_Timers[client].fCPTimes = times;

	return 0;
}

public int Native_GetClientCPTime(Handle plugin, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].fCPTimes[GetNativeCell(2)]);
}

public int Native_SetClientCPTime(Handle plugin, int numParams)
{
	gA_Timers[GetNativeCell(1)].fCPTimes[GetNativeCell(2)] = GetNativeCell(3);

	return 0;
}

public int Native_StageTimeValid(Handle plugin, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].bStageTimeValid);
}

public int Native_SetStageTimeValid(Handle plugin, int numParams)
{
	gA_Timers[GetNativeCell(1)].bStageTimeValid = GetNativeCell(2);
	
	return 1;
}

public any Native_GetAvgVelocity(Handle plugin, int numParams)
{
	return gA_Timers[GetNativeCell(1)].fAvgVelocity;
}

public any Native_GetMaxVelocity(Handle plugin, int numParams)
{
	return gA_Timers[GetNativeCell(1)].fMaxVelocity;
}

public any Native_SetAvgVelocity(Handle plugin, int numParams)
{
	gA_Timers[GetNativeCell(1)].fAvgVelocity = GetNativeCell(2);
	return 1;
}

public any Native_SetMaxVelocity(Handle plugin, int numParams)
{
	gA_Timers[GetNativeCell(1)].fMaxVelocity = GetNativeCell(2);
	return 1;
}

public any Native_GetStartVelocity(Handle plugin, int numParams)
{
	return gA_Timers[GetNativeCell(1)].fStartVelocity;
}

public any Native_GetStageStartVelocity(Handle plugin, int numParams)
{
	return gA_Timers[GetNativeCell(1)].aStageStartInfo.fStartVelocity;
}

public any Native_SetStartVelocity(Handle plugin, int numParams)
{
	gA_Timers[GetNativeCell(1)].fStartVelocity = GetNativeCell(2);
	return 1;
}

public any Native_SetStageStartVelocity(Handle plugin, int numParams)
{
	gA_Timers[GetNativeCell(1)].aStageStartInfo.fStartVelocity = GetNativeCell(2);
	return 1;
}

public int Native_GetClientLastStage(Handle plugin, int numParams)
{
	return gA_Timers[GetNativeCell(1)].iLastStage;
}

public int Native_SetClientLastStage(Handle handler, int numParams)
{
	ChangeClientLastStage(GetNativeCell(1), GetNativeCell(2));
	return 1;
}

public void ChangeClientLastStage(int client, int stage)
{
	if(gA_Timers[client].iLastStage == stage)
	{
		return;
	}
	
	if(gA_Timers[client].iTimerTrack >= Track_Bonus && stage > 1)
	{
		gA_Timers[client].iTimerTrack = Track_Main;
	}

	int oldstage = gA_Timers[client].iLastStage;
	gA_Timers[client].iLastStage = stage;

	if(gB_PlayerRepeat[client] && gA_Timers[client].iTimerTrack == Track_Main)
	{
		char sStage[32];
		FormatEx(sStage, 32, "%T %d", "StageText", client, stage);
		Shavit_PrintToChat(client, "%T", "EnabledTimerRepeat", client, gS_ChatStrings.sVariable, sStage, gS_ChatStrings.sText);
	}

	Call_StartForward(gH_Forwards_OnStageChanged);
	Call_PushCell(client);
	Call_PushCell(oldstage);
	Call_PushCell(stage);
	Call_Finish();
}

public any Native_ShouldProcessFrame(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return gA_Timers[client].fTimescale == 1.0
	    || gA_Timers[client].fNextFrameTime <= 0.0;
}

public Action Shavit_OnStartPre(int client, int track)
{
	if(gB_DisableTriggers[client])
	{
		return Plugin_Stop;
	}

	if (GetTimerStatus(client) == Timer_Paused)
	{
		return Plugin_Stop;
	}

	if(gB_Zones && (!Shavit_ZoneExists(Zone_End, track) || !Shavit_ZoneExists(Zone_Start, track)))
	{
		return Plugin_Stop;
	}

	if(gI_LastNoclipTick[client] > gA_Timers[client].iLandingTick)
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

TimerStatus GetTimerStatus(int client)
{
	if (!gA_Timers[client].bTimerEnabled)
	{
		return Timer_Stopped;
	}
	else if (gA_Timers[client].bClientPaused)
	{
		return Timer_Paused;
	}

	return Timer_Running;
}

// TODO: surfacefriction
float MaxPrestrafe(float runspeed, float accelerate, float friction, float tickinterval)
{
	if (friction < 0.0) return 9999999.0; // hello ~~mario~~ bhop_ins_mariooo
	if (accelerate < 0.0) accelerate = -accelerate;
	float something = runspeed * SquareRoot(
		(accelerate / friction) *
		((2.0 - accelerate * tickinterval) / (2.0 - friction * tickinterval))
	);
	return something < 0.0 ? -something : something;
}

float ClientMaxPrestrafe(int client)
{
	float runspeed = GetStyleSettingFloat(gA_Timers[client].bsStyle, "runspeed");
	return MaxPrestrafe(runspeed, sv_accelerate.FloatValue, sv_friction.FloatValue, GetTickInterval());
}

void StartTimer(int client, int track)
{
	if(!IsValidClient(client, true) || GetClientTeam(client) < 2 || IsFakeClient(client) || !gB_CookiesRetrieved[client])
	{
		return;
	}

	float fSpeed[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);
	float curVel = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));
	float fLimit = (Shavit_GetStyleSettingFloat(gA_Timers[client].bsStyle, "runspeed") + gCV_PrestrafeLimit.FloatValue);

	int iZoneStage;
	bool bNoVerticalSpeed;
	if(gA_Timers[client].bOnlyStageMode && track == Track_Main)
	{
		int iSpeedLimitFlags;
		Shavit_InsideZoneStage(client, iZoneStage, iSpeedLimitFlags);
		bNoVerticalSpeed = (iSpeedLimitFlags & ZSLF_NoVerticalSpeed) > 0;
	}
	else
	{
		bNoVerticalSpeed = (Shavit_GetTrackSpeedLimitFlags(track) & ZSLF_NoVerticalSpeed) > 0;
	}
	
	if (!bNoVerticalSpeed || (fSpeed[2] == 0.0 && curVel <= fLimit) || ((curVel <= ClientMaxPrestrafe(client) && gA_Timers[client].bOnGround &&
			  (gI_LastTickcount[client]-gI_FirstTouchedGround[client] > RoundFloat(0.5/GetTickInterval()))))) // beautiful
	{
		Action result = Plugin_Continue;
		Call_StartForward(gH_Forwards_StartPre);
		Call_PushCell(client);
		Call_PushCell(track);
		Call_Finish(result);

		if(result == Plugin_Continue)
		{
			Call_StartForward(gH_Forwards_Start);
			Call_PushCell(client);
			Call_PushCell(track);
			Call_Finish(result);

			gA_Timers[client].iZoneIncrement = 0;
			gA_Timers[client].iFullTicks = 0;
			gA_Timers[client].iFractionalTicks = 0;
			gA_Timers[client].bClientPaused = false;
			gA_Timers[client].iStrafes = 0;
			gA_Timers[client].iJumps = 0;
			gA_Timers[client].iTotalMeasures = 0;
			gA_Timers[client].iGoodGains = 0;
			
			if (gA_Timers[client].iTimerTrack != track)
			{
				CallOnTrackChanged(client, gA_Timers[client].iTimerTrack, track);
			}

			if (gA_Timers[client].bOnlyStageMode)
			{
				gA_Timers[client].iLastStage = iZoneStage;
			}
			else
			{
				if(Shavit_GetStageCount(track) > 1)
				{
					if(gA_Timers[client].fCPTimes[1] != -1.0)	
					{
						gA_Timers[client].fCPTimes = empty_times;//set it -1.0 to make cptime dont need to reset every tick
						gA_Timers[client].fStageFinishTimes = empty_times;
						gA_Timers[client].iStageAttempts = empty_attempts;
					}

					gA_Timers[client].iStageAttempts[1] = 1;

					//reset stage start stuffs
					ChangeClientLastStage(client, 1);
					gA_Timers[client].aStageStartInfo.fStageStartTime = 0.0;
					gA_Timers[client].aStageStartInfo.iFullTicks = 0;
					gA_Timers[client].aStageStartInfo.iFractionalTicks = 0;
					gA_Timers[client].aStageStartInfo.iJumps = 0;
					gA_Timers[client].aStageStartInfo.iStrafes = 0;
					gA_Timers[client].aStageStartInfo.iTotalMeasures = 0;
					gA_Timers[client].aStageStartInfo.iZoneIncrement = 0;
					gA_Timers[client].aStageStartInfo.fZoneOffset[Zone_Start] = 0.0;
					gA_Timers[client].aStageStartInfo.fDistanceOffset[Zone_End] = 0.0;
					gA_Timers[client].aStageStartInfo.iGoodGains = gA_Timers[client].iGoodGains;
					gA_Timers[client].aStageStartInfo.fMaxVelocity = curVel;	
					gA_Timers[client].aStageStartInfo.fAvgVelocity = curVel;
					gA_Timers[client].bStageTimeValid = true;
				}
				else
				{
					gA_Timers[client].iLastStage = 0; // i use it as last checkpoint number when the map is linear.
					if(gA_Timers[client].fCPTimes[1] != -1.0)	//kinda duplicated, but i really dont want to reset 3 of them in linear map.
					{
						gA_Timers[client].fCPTimes = empty_times;
					}
				}
			}

			gA_Timers[client].iTimerTrack = track;
			gA_Timers[client].bTimerEnabled = true;
			gA_Timers[client].iKeyCombo = -1;
			gA_Timers[client].fCurrentTime = 0.0;

			gA_Timers[client].iMeasuredJumps = 0;
			gA_Timers[client].iPerfectJumps = 0;
			gA_Timers[client].bCanUseAllKeys = false;
			gA_Timers[client].fZoneOffset[Zone_Start] = 0.0;
			gA_Timers[client].fZoneOffset[Zone_End] = 0.0;
			gA_Timers[client].fDistanceOffset[Zone_Start] = 0.0;
			gA_Timers[client].fDistanceOffset[Zone_End] = 0.0;
			gA_Timers[client].fAvgVelocity = curVel;
			gA_Timers[client].fMaxVelocity = curVel;

			if(gCV_DisablePracticeModeOnStart.BoolValue)
			{
				gA_Timers[client].bPracticeMode = false;
			}

			// TODO: Look into when this should be reset (since resetting it here disables timescale while in startzone).
			//gA_Timers[client].fNextFrameTime = 0.0;

			gA_Timers[client].fplayer_speedmod = 1.0;
			UpdateLaggedMovement(client, true);

			SetEntityGravity(client, GetStyleSettingFloat(gA_Timers[client].bsStyle, "gravity"));
		}
#if 0
		else if(result == Plugin_Handled || result == Plugin_Stop)
		{
			gA_Timers[client].bTimerEnabled = false;
		}
#endif
	}
}

void StartStageTimer(int client, int track, int stage, bool force, bool first)
{
	if(GetTimerStatus(client) == Timer_Stopped && gA_Timers[client].bOnlyStageMode)
	{
		ChangeClientLastStage(client, stage);	// i dont know why but i need this here to make sure the stage number is right
		StartTimer(client, track);
	}
	else if(GetTimerStatus(client) == Timer_Running)
	{
		if (gA_Timers[client].bOnlyStageMode)
		{
			if(stage <= gA_Timers[client].iLastStage)
			{
				StartTimer(client, track);
			}
		}
		else if(gA_Timers[client].iLastStage == stage)
		{
			if(!IsValidClient(client, true) || GetClientTeam(client) < 2 || IsFakeClient(client) || !gB_CookiesRetrieved[client])
			{
				return;
			}

			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);
			float curVel = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));
			float fLimit = (Shavit_GetStyleSettingFloat(gA_Timers[client].bsStyle, "runspeed") + gCV_PrestrafeLimit.FloatValue);

			int iSpeedLimitFlags;
			int iZoneStage;
			Shavit_InsideZoneStage(client, iZoneStage, iSpeedLimitFlags);
			bool bNoVerticalSpeed = (iSpeedLimitFlags & ZSLF_NoVerticalSpeed) > 0;

			if (force || !bNoVerticalSpeed || (fSpeed[2] == 0.0 && curVel <= fLimit) || ((curVel <= ClientMaxPrestrafe(client) && gA_Timers[client].bOnGround &&
			  	(gI_LastTickcount[client]-gI_FirstTouchedGround[client] > RoundFloat(0.5/GetTickInterval()))))) // beautiful
			{
				bool restart = first || gA_Timers[client].aStageStartInfo.iZoneIncrement > 1;

				Call_StartForward(gH_Forwards_StageStart);
				Call_PushCell(client);
				Call_PushCell(stage);
				Call_PushCell(restart);
				Call_PushCell(first);
				Call_Finish();

				if(restart)
				{
					if(first)
					{
						gA_Timers[client].iStageAttempts[stage] = 1;
					}
					else if(gA_Timers[client].fCurrentTime - gA_Timers[client].aStageStartInfo.fStageStartTime > 0.8)
					{
						gA_Timers[client].iStageAttempts[stage]++;
					}
				}

				gA_Timers[client].aStageStartInfo.fStageStartTime = gA_Timers[client].fCurrentTime;
				gA_Timers[client].aStageStartInfo.iFractionalTicks = gA_Timers[client].iFractionalTicks;
				gA_Timers[client].aStageStartInfo.iFullTicks = gA_Timers[client].iFullTicks;
				gA_Timers[client].aStageStartInfo.iJumps = gA_Timers[client].iJumps;
				gA_Timers[client].aStageStartInfo.iStrafes = gA_Timers[client].iStrafes;
				gA_Timers[client].aStageStartInfo.iGoodGains = gA_Timers[client].iGoodGains;
				gA_Timers[client].aStageStartInfo.iTotalMeasures = gA_Timers[client].iTotalMeasures;
				gA_Timers[client].aStageStartInfo.iZoneIncrement = 0;
				gA_Timers[client].aStageStartInfo.fMaxVelocity = curVel;	
				gA_Timers[client].aStageStartInfo.fAvgVelocity = curVel;
			}
		}
	}
}

void StopTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	if (gA_Timers[client].bClientPaused)
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}

	gA_Timers[client].bTimerEnabled = false;
	gA_Timers[client].iJumps = 0;
	gA_Timers[client].fCurrentTime = 0.0;
	gA_Timers[client].iFullTicks = 0;
	gA_Timers[client].iFractionalTicks = 0;
	gA_Timers[client].bClientPaused = false;
	gA_Timers[client].iStrafes = 0;
	gA_Timers[client].iTotalMeasures = 0;
	gA_Timers[client].iGoodGains = 0;
}

void PauseTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	Call_StartForward(gH_Forwards_OnPause);
	Call_PushCell(client);
	Call_PushCell(gA_Timers[client].iTimerTrack);
	Call_Finish();

	gA_Timers[client].bClientPaused = true;
}

void ResumeTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	Call_StartForward(gH_Forwards_OnResume);
	Call_PushCell(client);
	Call_PushCell(gA_Timers[client].iTimerTrack);
	Call_Finish();

	gA_Timers[client].bClientPaused = false;
	// setting is handled in usercmd
	SetEntityMoveType(client, MOVETYPE_WALK);
	gI_LastNoclipTick[client] = 0;
}

public void OnClientDisconnect(int client)
{
	RequestFrame(StopTimer, client);
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client) || !IsClientInGame(client))
	{
		return;
	}

	char sCookie[4];

	if(gH_AutoBhopCookie != null)
	{
		GetClientCookie(client, gH_AutoBhopCookie, sCookie, 4);
	}

	gB_Auto[client] = (strlen(sCookie) > 0)? view_as<bool>(StringToInt(sCookie)):true;

	char sMsgSettings[12];
	GetClientCookie(client, gH_MessageCookie, sMsgSettings, sizeof(sMsgSettings));

	if(strlen(sMsgSettings) == 0)
	{
		IntToString(MSG_DEFAULT, sMsgSettings, sizeof(sMsgSettings));
		SetClientCookie(client, gH_MessageCookie, sMsgSettings);
	}

	gI_MessageSettings[client] = StringToInt(sMsgSettings);

	int style = gI_DefaultStyle;

	if(gB_StyleCookies && gH_StyleCookie != null)
	{
		GetClientCookie(client, gH_StyleCookie, sCookie, 4);
		int newstyle = StringToInt(sCookie);

		if (0 <= newstyle < Shavit_GetStyleCount())
		{
			style = newstyle;
		}
	}

	if(Shavit_HasStyleAccess(client, style))
	{
		CallOnStyleChanged(client, gA_Timers[client].bsStyle, style, false);
	}

	gB_CookiesRetrieved[client] = true;
}

public void OnClientPutInServer(int client)
{
	StopTimer(client);
	Bhopstats_OnClientPutInServer(client);

	if(!IsClientConnected(client) || IsFakeClient(client))
	{
		return;
	}

	gH_TeleportDhook.HookEntity(Hook_Post, client, DHooks_OnTeleport);

	gB_Auto[client] = true;
	gB_DisableTriggers[client] = false;
	gA_Timers[client].fStrafeWarning = 0.0;
	gA_Timers[client].bPracticeMode = false;
	gA_Timers[client].bOnlyStageMode = false;
	gA_Timers[client].iKeyCombo = -1;
	gA_Timers[client].iTimerTrack = 0;
	gA_Timers[client].bsStyle = 0;
	gA_Timers[client].fTimescale = 1.0;
	gA_Timers[client].iFullTicks = 0;
	gA_Timers[client].iFractionalTicks = 0;
	gA_Timers[client].iZoneIncrement = 0;
	gA_Timers[client].fNextFrameTime = 0.0;
	gA_Timers[client].fplayer_speedmod = 1.0;
	gA_Timers[client].iLastStage = 0;
	gA_Timers[client].aStageStartInfo.fStageStartTime = 0.0;
	gA_Timers[client].aStageStartInfo.iFullTicks = 0;
	gA_Timers[client].aStageStartInfo.iFractionalTicks = 0;
	gA_Timers[client].aStageStartInfo.iZoneIncrement = 0;
	gA_Timers[client].fCPTimes = empty_times;
	gA_Timers[client].fStageFinishTimes = empty_times;
	gA_Timers[client].iStageAttempts = empty_attempts;
	gS_DeleteMap[client][0] = 0;
	gI_FirstTouchedGround[client] = 0;
	gI_LastNoclipTick[client] = 0;
	gI_LastTickcount[client] = 0;
	gI_HijackFrames[client] = 0;
	gI_LastPrintedSteamID[client] = 0;

	gF_NoclipSpeed[client] = sv_noclipspeed.FloatValue;
	gB_PlayerRepeat[client] = false;

	gB_CookiesRetrieved[client] = false;

	if(AreClientCookiesCached(client))
	{
		OnClientCookiesCached(client);
	}
	else  // not adding style permission check here for obvious reasons
	{
		CallOnStyleChanged(client, 0, gI_DefaultStyle, false);
	}

	SDKHook(client, SDKHook_PreThinkPost, PreThinkPost);
	SDKHook(client, SDKHook_PostThinkPost, PostThinkPost);
}

public void OnClientAuthorized(int client, const char[] auth)
{
	int iSteamID = GetSteamAccountID(client);

	if(iSteamID == 0)
	{
		return;
	}

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));
	ReplaceString(sName, MAX_NAME_LENGTH, "#", "?"); // to avoid this: https://user-images.githubusercontent.com/3672466/28637962-0d324952-724c-11e7-8b27-15ff021f0a59.png

	int iLength = ((strlen(sName) * 2) + 1);
	char[] sEscapedName = new char[iLength];
	gH_SQL.Escape(sName, sEscapedName, iLength);

	int iIPAddress = 0;

	if (gCV_SaveIps.BoolValue)
	{
		char sIPAddress[64];
		GetClientIP(client, sIPAddress, 64);
		iIPAddress = IPStringToAddress(sIPAddress);
	}

	int iTime = GetTime();

	char sQuery[512];

	if (gI_Driver == Driver_mysql)
	{
		FormatEx(sQuery, 512,
			"INSERT INTO %susers (auth, name, ip, lastlogin, firstlogin) VALUES (%d, '%s', %d, %d, %d) ON DUPLICATE KEY UPDATE name = '%s', ip = %d, lastlogin = %d;",
			gS_MySQLPrefix, iSteamID, sEscapedName, iIPAddress, iTime, iTime, sEscapedName, iIPAddress, iTime);
	}
	else // postgresql & sqlite
	{
		FormatEx(sQuery, 512,
			"INSERT INTO %susers (auth, name, ip, lastlogin, firstlogin) VALUES (%d, '%s', %d, %d, %d) ON CONFLICT(auth) DO UPDATE SET name = '%s', ip = %d, lastlogin = %d;",
			gS_MySQLPrefix, iSteamID, sEscapedName, iIPAddress, iTime, iTime, sEscapedName, iIPAddress, iTime);
	}

	QueryLog(gH_SQL, SQL_InsertUser_Callback, sQuery, GetClientSerial(client));
}

public void SQL_InsertUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		int client = GetClientFromSerial(data);

		if(client == 0)
		{
			LogError("Timer error! Failed to insert a disconnected player's data to the table. Reason: %s", error);
		}
		else
		{
			LogError("Timer error! Failed to insert \"%N\"'s data to the table. Reason: %s", client, error);
		}

		return;
	}
}

// alternatively, SnapEyeAngles &| SetLocalAngles should work...
// but we have easy gamedata for Teleport so whatever...
public MRESReturn DHooks_OnTeleport(int pThis, DHookParam hParams)
{
	if (gCV_HijackTeleportAngles.BoolValue && !hParams.IsNull(2) && IsPlayerAlive(pThis))
	{
		float latency = GetClientLatency(pThis, NetFlow_Both);

		if (latency > 0.0)
		{
			gI_HijackFrames[pThis] = RoundToCeil(latency / GetTickInterval()) + 1;

			float angles[3];
			hParams.GetVector(2, angles);
			gF_HijackedAngles[pThis][0] = angles[0];
			gF_HijackedAngles[pThis][1] = angles[1];
		}
	}

	return MRES_Ignored;
}

void ReplaceColors(char[] string, int size)
{
	for(int x = 0; x < sizeof(gS_GlobalColorNames); x++)
	{
		ReplaceString(string, size, gS_GlobalColorNames[x], gS_GlobalColors[x]);
	}

	for(int x = 0; x < sizeof(gS_CSGOColorNames); x++)
	{
		ReplaceString(string, size, gS_CSGOColorNames[x], gS_CSGOColors[x]);
	}

	ReplaceString(string, size, "{RGB}", "\x07");
	ReplaceString(string, size, "{RGBA}", "\x08");
}

bool LoadMessages()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-messages.cfg");

	KeyValues kv = new KeyValues("shavit-messages");

	if(!kv.ImportFromFile(sPath))
	{
		delete kv;

		return false;
	}

	kv.JumpToKey((IsSource2013(gEV_Type))? "CS:S":"CS:GO");

	kv.GetString("prefix", gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix), "\x07ffffff[ \x077dd3d4Timer \x07ffffff] -");
	kv.GetString("text", gS_ChatStrings.sText, sizeof(chatstrings_t::sText), "\x07ffffff");
	kv.GetString("warning", gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning), "\x07ff5253");
	kv.GetString("improving", gS_ChatStrings.sImproving, sizeof(chatstrings_t::sImproving), "\x0700f55e");
	kv.GetString("variable", gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable), "\x07fffb00");
	kv.GetString("variable2", gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2), "\x077dd3d4");
	kv.GetString("style", gS_ChatStrings.sStyle, sizeof(chatstrings_t::sStyle), "\x07eaa9e5");

	delete kv;

	ReplaceColors(gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix));
	ReplaceColors(gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	ReplaceColors(gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning));
	ReplaceColors(gS_ChatStrings.sImproving, sizeof(chatstrings_t::sImproving));
	ReplaceColors(gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
	ReplaceColors(gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2));
	ReplaceColors(gS_ChatStrings.sStyle, sizeof(chatstrings_t::sStyle));

	Call_StartForward(gH_Forwards_OnChatConfigLoaded);
	Call_Finish();

	return true;
}

void SQL_DBConnect()
{
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = GetTimerDatabaseHandle();
	gI_Driver = GetDatabaseDriver(gH_SQL);

	SQL_CreateTables(gH_SQL, gS_MySQLPrefix, gI_Driver);
}

public void Shavit_OnReachNextStage(int client, int track, int startStage, int endStage)
{
	RequestFrame(Frame_StartStageTimer, GetClientSerial(client));
}

void Frame_StartStageTimer(int serial)
{
	int client = GetClientFromSerial(serial);
	StartStageTimer(client, Track_Main, gA_Timers[client].iLastStage, true, true);
}

public void Shavit_OnEnterZone(int client, int type, int track, int id, int entity, int data)
{
	if(type == Zone_Airaccelerate && track == gA_Timers[client].iTimerTrack)
	{
		gF_ZoneAiraccelerate[client] = float(data);
	}
	else if (type == Zone_CustomSpeedLimit && track == gA_Timers[client].iTimerTrack)
	{
		gF_ZoneSpeedLimit[client] = float(data);
	}
	else if (type != Zone_Autobhop)
	{
		return;
	}

	UpdateStyleSettings(client);
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity)
{
	if (track != gA_Timers[client].iTimerTrack)
	{
		return;		
	}

	if (type != Zone_Airaccelerate && type != Zone_CustomSpeedLimit && type != Zone_Autobhop)
	{
		return;		
	}

	UpdateStyleSettings(client);
}

public void PreThinkPost(int client)
{
	if(IsPlayerAlive(client))
	{
		if (!gB_Zones || !Shavit_InsideZone(client, Zone_Airaccelerate, gA_Timers[client].iTimerTrack))
		{
			sv_airaccelerate.FloatValue = GetStyleSettingFloat(gA_Timers[client].bsStyle, "airaccelerate");
		}
		else
		{
			sv_airaccelerate.FloatValue = gF_ZoneAiraccelerate[client];
		}

		if(sv_enablebunnyhopping != null)
		{
			if (gB_Zones && Shavit_InsideZone(client, Zone_CustomSpeedLimit, gA_Timers[client].iTimerTrack))
			{
				sv_enablebunnyhopping.BoolValue = true;
			}
			else
			{
				sv_enablebunnyhopping.BoolValue = GetStyleSettingBool(gA_Timers[client].bsStyle, "bunnyhopping");
			}
		}

		sv_noclipspeed.FloatValue = gF_NoclipSpeed[client];

		MoveType mtMoveType = GetEntityMoveType(client);
		MoveType mtLast = gA_Timers[client].iLastMoveType;
		gA_Timers[client].iLastMoveType = mtMoveType;

		if (mtMoveType == MOVETYPE_WALK || mtMoveType == MOVETYPE_ISOMETRIC)
		{
			float g = 0.0;
			float styleg = GetStyleSettingFloat(gA_Timers[client].bsStyle, "gravity");

			if (gB_Zones)
			{
				if (Shavit_InsideZone(client, Zone_NoTimerGravity, gA_Timers[client].iTimerTrack))
				{
					return;
				}

				int id;

				if (Shavit_InsideZoneGetID(client, Zone_Gravity, gA_Timers[client].iTimerTrack, id))
				{
					g = view_as<float>(Shavit_GetZoneData(id));
				}
			}

			float clientg = GetEntityGravity(client);

			if (g == 0.0 && styleg != 1.0 && ((mtLast == MOVETYPE_LADDER || clientg == 1.0 || clientg == 0.0)))
			{
				g = styleg;
			}

			if (g != 0.0)
			{
				SetEntityGravity(client, g);
			}
		}
	}
}

public void PostThinkPost(int client)
{
	if(GetTimerStatus(client) == Timer_Running) // i dont know if someone can actually pause timer when zone increment is 1, just in case.
	{
		gF_Origin[client][1] = gF_Origin[client][0];
		GetEntPropVector(client, Prop_Data, "m_vecOrigin", gF_Origin[client][0]);

		bool bNormalStart = gA_Timers[client].iZoneIncrement == 1;
		bool bMainTimerStageStart = !bNormalStart && !gA_Timers[client].bOnlyStageMode && gA_Timers[client].aStageStartInfo.iZoneIncrement == 1;

		if((bNormalStart || bMainTimerStageStart))
		{
			if(gCV_UseOffsets.BoolValue)
			{
				CalculateTickIntervalOffset(client, Zone_Start, bMainTimerStageStart);			
			}

			CallOnTimerStarted(client, bMainTimerStageStart);

			if(gCV_DebugOffsets.BoolValue)
			{
				char sOffsetMessage[100];
				char sOffsetDistance[8];
				FormatEx(sOffsetDistance, 8, "%.1f", gA_Timers[client].fDistanceOffset[Zone_Start]);
				FormatEx(sOffsetMessage, sizeof(sOffsetMessage), "[START] %T", "DebugOffsets", client, gA_Timers[client].fZoneOffset[Zone_Start], sOffsetDistance);
				PrintToConsole(client, "%s", sOffsetMessage);
				Shavit_StopChatSound();
				Shavit_PrintToChat(client, "%s", sOffsetMessage);
			}
		}		
	}
}

public void CallOnTimerStarted(int client, bool bMainStageTimer)
{
	int track = gA_Timers[client].iTimerTrack;	
	int stage = gA_Timers[client].iLastStage; 
	int style = gA_Timers[client].bsStyle;

	Call_StartForward(gH_Forawrds_Started);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_PushCell(stage);
	Call_PushCell(style);
	Call_PushCell(bMainStageTimer);
	Call_Finish();

	bool bStageTimer = bMainStageTimer || (gA_Timers[client].bOnlyStageMode && gA_Timers[client].iTimerTrack == Track_Main);
	CheckClientStartVelocity(client, track, stage, style, bStageTimer);
}

public void CheckClientStartVelocity(int client, int track, int stage, int style, bool bStageTimer)
{
	float fSpeed[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);
	float speed = GetVectorLength(fSpeed);
	float curVel = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));
	float fMaxPrespeed = Shavit_GetStyleSettingFloat(style, "runspeed") + gCV_PrestrafeLimit.FloatValue;
	int iSpeedLimitFlags;

	if(bStageTimer && stage > 0)
	{
		gA_Timers[client].aStageStartInfo.fStartVelocity = speed;

		int iZoneStage;
		Shavit_InsideZoneStage(client, iZoneStage, iSpeedLimitFlags);

		bool bZoneLimited;
		if(gCV_PrestrafeZone.IntValue == 2)
		{
			bZoneLimited = gA_Timers[client].bOnlyStageMode || !((iSpeedLimitFlags & ZSLF_LimitSpeed) > 0 || (iSpeedLimitFlags & ZSLF_ReduceSpeed) > 0);
		}
		else if(gCV_PrestrafeZone.IntValue == 3)
		{
			bZoneLimited = ((iSpeedLimitFlags & ZSLF_NoVerticalSpeed) == 0 || ((iSpeedLimitFlags & ZSLF_LimitSpeed) == 0 && (iSpeedLimitFlags & ZSLF_ReduceSpeed) == 0));
		}
		else
		{
			bZoneLimited = true;
		}
		
		gA_Timers[client].bStageTimeValid = bZoneLimited ? true:curVel < fMaxPrespeed;

		if(curVel > 20)
		{
			float fStartVelWR = Shavit_GetStageWRStartVelocity(style, stage);
			char sVelDiff[64];

			if(fStartVelWR > 0.0)
			{
				float fStartVelDiffWR = speed - fStartVelWR;

				FormatEx(sVelDiff, sizeof(sVelDiff), "(SR: %s%s%.f", 
					fStartVelDiffWR > 0 ? gS_ChatStrings.sImproving : gS_ChatStrings.sWarning, fStartVelDiffWR > 0 ? "+":"", fStartVelDiffWR);	

				float fStartVelPB = Shavit_GetClientStageStartVelocity(client, style, stage);

				if(fStartVelPB > 0.0)
				{
					float fStartVelDiffPB = speed - fStartVelPB;

					FormatEx(sVelDiff, sizeof(sVelDiff), "%s%s u/s | PB: %s%s%.f", sVelDiff, gS_ChatStrings.sText,
						fStartVelDiffPB > 0 ? gS_ChatStrings.sImproving : gS_ChatStrings.sWarning, fStartVelDiffPB > 0 ? "+":"", fStartVelDiffPB);	
				}

				FormatEx(sVelDiff, sizeof(sVelDiff), "%s%s u/s)", sVelDiff, gS_ChatStrings.sText);
			}

			if((gI_MessageSettings[client] & MSG_SPEEDTRAP) == 0)
			{
				Shavit_StopChatSound();							
				Shavit_PrintToChat(client, "%T %s", "StageStartZonePrespeed", client,
					gS_ChatStrings.sVariable2, stage, gS_ChatStrings.sText,
					gA_Timers[client].bStageTimeValid ? gS_ChatStrings.sVariable : gS_ChatStrings.sWarning, speed, gS_ChatStrings.sText, sVelDiff);
			}

			if(!gA_Timers[client].bStageTimeValid)
			{
				Shavit_PrintToChat(client, "%T", "PrespeedLimitExcceded", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
			}

			for(int i = 1; i <= MaxClients; i++)
			{
				if(IsValidClient(i) && GetSpectatorTarget(i) == client && (gI_MessageSettings[i] & MSG_SPEEDTRAP) == 0)
				{
					Shavit_StopChatSound();
					Shavit_PrintToChat(i, "%s*%N*%s %T %s", gS_ChatStrings.sImproving, client, gS_ChatStrings.sText, "StageStartZonePrespeed", i,
						gS_ChatStrings.sVariable2, stage, gS_ChatStrings.sText,
						gA_Timers[client].bStageTimeValid ? gS_ChatStrings.sVariable : gS_ChatStrings.sWarning, speed, gS_ChatStrings.sText, sVelDiff);
				}
			}
		}
	}
	else
	{
		gA_Timers[client].fStartVelocity = speed;
		gA_Timers[client].aStageStartInfo.fStartVelocity = speed;
		gA_Timers[client].bStageTimeValid = true;

		if(curVel > 20)
		{
			float fStartVelWR = Shavit_GetWRStartVelocity(style, track);
			char sVelDiff[64];

			if(fStartVelWR > 0.0)
			{
				float fStartVelDiffWR = speed - fStartVelWR;

				FormatEx(sVelDiff, sizeof(sVelDiff), "(SR: %s%s%.f", 
					fStartVelDiffWR > 0 ? gS_ChatStrings.sImproving : gS_ChatStrings.sWarning, fStartVelDiffWR > 0 ? "+":"", fStartVelDiffWR);	

				float fStartVelPB = Shavit_GetClientStartVelocity(client, style, track);

				if(fStartVelPB > 0.0)
				{
					float fStartVelDiffPB = speed - fStartVelPB;

					FormatEx(sVelDiff, sizeof(sVelDiff), "%s%s u/s | PB: %s%s%.f", sVelDiff, gS_ChatStrings.sText,
						fStartVelDiffPB > 0 ? gS_ChatStrings.sImproving : gS_ChatStrings.sWarning, fStartVelDiffPB > 0 ? "+":"", fStartVelDiffPB);	
				}

				FormatEx(sVelDiff, sizeof(sVelDiff), "%s%s u/s)", sVelDiff, gS_ChatStrings.sText);
			}

			if((Shavit_GetMessageSetting(client) & MSG_SPEEDTRAP) == 0)
			{
				Shavit_StopChatSound();							
				Shavit_PrintToChat(client, "%T %s", "TrackStartZonePrespeed", client, gS_ChatStrings.sVariable, speed, gS_ChatStrings.sText, sVelDiff);
			}

			for(int i = 1; i <= MaxClients; i++)
			{
				if(IsValidClient(i) && GetSpectatorTarget(i) == client && (Shavit_GetMessageSetting(i) & MSG_SPEEDTRAP) == 0)
				{
					Shavit_StopChatSound();							
					Shavit_PrintToChat(i, "%s*%N*%s %T %s", gS_ChatStrings.sImproving, client, gS_ChatStrings.sText, "TrackStartZonePrespeed", i, gS_ChatStrings.sVariable, speed, gS_ChatStrings.sText, sVelDiff);
				}
			}	
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "player_speedmod"))
	{
		gH_AcceptInput.HookEntity(Hook_Post, entity, DHook_AcceptInput_player_speedmod_Post);
	}

	if(StrEqual(classname, "trigger_multiple") || StrEqual(classname, "trigger_once") || StrEqual(classname, "trigger_push") || StrEqual(classname, "trigger_teleport") || StrEqual(classname, "trigger_gravity"))
	{
		SDKHook(entity, SDKHook_StartTouch, HookTrigger);
		SDKHook(entity, SDKHook_EndTouch, HookTrigger);
		SDKHook(entity, SDKHook_Touch, HookTrigger);
	}
}

// bool CBaseEntity::AcceptInput(char  const*, CBaseEntity*, CBaseEntity*, variant_t, int)
public MRESReturn DHook_AcceptInput_player_speedmod_Post(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	char buf[128];
	hParams.GetString(1, buf, sizeof(buf));

	if (!StrEqual(buf, "ModifySpeed", false) || hParams.IsNull(2))
	{
		return MRES_Ignored;
	}

	int activator = hParams.Get(2);

	if (!IsValidClient(activator, true))
	{
		return MRES_Ignored;
	}

	float speed;

	int variant_type = hParams.GetObjectVar(4, 16, ObjectValueType_Int);

	if (variant_type == 2 /* FIELD_STRING */)
	{
		hParams.GetObjectVarString(4, 0, ObjectValueType_String, buf, sizeof(buf));
		speed = StringToFloat(buf);
	}
	else // should be FIELD_FLOAT but don't check who cares
	{
		speed = hParams.GetObjectVar(4, 0, ObjectValueType_Float);
	}

	gA_Timers[activator].fplayer_speedmod = speed;
	UpdateLaggedMovement(activator, true);

	#if DEBUG
	int caller = hParams.Get(3);
	PrintToServer("ModifySpeed activator = %d(%N), caller = %d, old_speed = %s, new_speed = %f", activator, activator, caller, buf, speed);
	#endif

	return MRES_Ignored;
}

public MRESReturn DHook_ProcessMovementPre(Handle hParams)
{
	int client = DHookGetParam(hParams, 1);

	// Causes client to do zone touching in movement instead of server frames.
	// From https://github.com/rumourA/End-Touch-Fix
	MaybeDoPhysicsUntouch(client);

	Call_StartForward(gH_Forwards_OnProcessMovement);
	Call_PushCell(client);
	Call_Finish();

	if (IsFakeClient(client) || !IsPlayerAlive(client))
	{
		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0); // otherwise you get slow spec noclip
		return MRES_Ignored;
	}

	MoveType mt = GetEntityMoveType(client);

	if (gA_Timers[client].fTimescale == 1.0 || mt == MOVETYPE_NOCLIP)
	{
		if (gB_Eventqueuefix)
		{
			SetClientEventsPaused(client, gA_Timers[client].bClientPaused);
		}

		return MRES_Ignored;
	}

	// i got this code from kid-tas by kid fearless
	if (gA_Timers[client].fNextFrameTime <= 0.0)
	{
		gA_Timers[client].fNextFrameTime += (1.0 - gA_Timers[client].fTimescale);

		if (mt != MOVETYPE_NONE)
		{
			gA_Timers[client].iLastMoveTypeTAS = mt;
		}

		UpdateLaggedMovement(client, false);
	}
	else
	{
		gA_Timers[client].fNextFrameTime -= gA_Timers[client].fTimescale;
		SetEntityMoveType(client, MOVETYPE_NONE);
	}

	if (gB_Eventqueuefix)
	{
		SetClientEventsPaused(client, (!Shavit_ShouldProcessFrame(client) || gA_Timers[client].bClientPaused));
	}

	return MRES_Ignored;
}

public MRESReturn DHook_ProcessMovementPost(Handle hParams)
{
	int client = DHookGetParam(hParams, 1);

	Call_StartForward(gH_Forwards_OnProcessMovementPost);
	Call_PushCell(client);
	Call_Finish();

	if (IsFakeClient(client) || !IsPlayerAlive(client))
	{
		return MRES_Ignored;
	}

	if (gA_Timers[client].fTimescale != 1.0 && GetEntityMoveType(client) != MOVETYPE_NOCLIP)
	{
		SetEntityMoveType(client, gA_Timers[client].iLastMoveTypeTAS);
		UpdateLaggedMovement(client, true);
	}

	if (gA_Timers[client].bClientPaused || !gA_Timers[client].bTimerEnabled)
	{
		return MRES_Ignored;
	}

	float interval = GetTickInterval();
	float ts = GetStyleSettingFloat(gA_Timers[client].bsStyle, "timescale") * gA_Timers[client].fTimescale; // true tick interval is here
	float time = interval * ts;

	gA_Timers[client].iZoneIncrement++;
	gA_Timers[client].aStageStartInfo.iZoneIncrement++;

	timer_snapshot_t snapshot;
	BuildSnapshot(client, snapshot);

	Call_StartForward(gH_Forwards_OnTimeIncrement);
	Call_PushCell(client);
	Call_PushArray(snapshot, sizeof(timer_snapshot_t));
	Call_PushCellRef(time);
	Call_Finish();

	gA_Timers[client].iFractionalTicks += RoundFloat(ts * 10000.0);
	int whole_tick = gA_Timers[client].iFractionalTicks / 10000;
	gA_Timers[client].iFractionalTicks -= whole_tick * 10000;
	gA_Timers[client].iFullTicks       += whole_tick;

	CalculateRunTime(gA_Timers[client], false, false);

	Call_StartForward(gH_Forwards_OnTimeIncrementPost);
	Call_PushCell(client);
	Call_PushCell(time);
	Call_Finish();

	MaybeDoPhysicsUntouch(client);

	return MRES_Ignored;
}


// reference: https://github.com/momentum-mod/game/blob/5e2d1995ca7c599907980ee5b5da04d7b5474c61/mp/src/game/server/momentum/mom_timer.cpp#L388
void CalculateTickIntervalOffset(int client, int zonetype, bool stage)
{
	float localOrigin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", localOrigin);
	float maxs[3];
	float mins[3];
	float vel[3];
	GetEntPropVector(client, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(client, Prop_Send, "m_vecMaxs", maxs);
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);

	gF_SmallestDist[client] = 0.0;

	if (zonetype == Zone_Start)
	{
									//now			before
		TR_EnumerateEntitiesHull(localOrigin, gF_Origin[client][1], mins, maxs, PARTITION_TRIGGER_EDICTS, TREnumTrigger, client);
	}
	else
	{
		TR_EnumerateEntitiesHull(gF_Origin[client][0], localOrigin, mins, maxs, PARTITION_TRIGGER_EDICTS, TREnumTrigger, client);
	}

	float offset = gF_Fraction[client] * GetTickInterval();

	if(stage)
	{
		gA_Timers[client].aStageStartInfo.fZoneOffset[zonetype] = gF_Fraction[client];
		gA_Timers[client].aStageStartInfo.fDistanceOffset[zonetype] = gF_SmallestDist[client];	
	}
	else
	{
		gA_Timers[client].fZoneOffset[zonetype] = gF_Fraction[client];
		gA_Timers[client].fDistanceOffset[zonetype] = gF_SmallestDist[client];		
	}

	Call_StartForward(gH_Forwards_OnTimeOffsetCalculated);
	Call_PushCell(client);
	Call_PushCell(zonetype);
	Call_PushCell(offset);
	Call_PushCell(gF_SmallestDist[client]);
	Call_Finish();

	gF_SmallestDist[client] = 0.0;
}

bool TREnumTrigger(int entity, int client) 
{
	if (entity <= MaxClients) {
		return true;
	}

	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));

	//the entity is a zone
	if(StrContains(classname, "trigger_multiple") > -1)
	{
		TR_ClipCurrentRayToEntity(MASK_ALL, entity);

		float start[3];
		TR_GetStartPosition(INVALID_HANDLE, start);

		float end[3];
		TR_GetEndPosition(end);

		float distance = GetVectorDistance(start, end);
		gF_SmallestDist[client] = distance;
		gF_Fraction[client] = TR_GetFraction();

		return false;
	}
	return true;
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

void BuildSnapshot(int client, timer_snapshot_t snapshot)
{
	snapshot = gA_Timers[client];
	snapshot.fServerTime = GetEngineTime();
	snapshot.fTimescale = (gA_Timers[client].fTimescale > 0.0) ? gA_Timers[client].fTimescale : 1.0;
	//snapshot.iLandingTick = ?????; // TODO: Think about handling segmented scroll? /shrug
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

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	Remove_sv_cheat_Impluses(client, impulse);

	int flags = GetEntityFlags(client);

	SetEntityFlags(client, (flags & ~FL_ATCONTROLS));

	if (gA_Timers[client].bClientPaused && IsPlayerAlive(client) && !gCV_PauseMovement.BoolValue)
	{
		buttons = 0;
		vel = view_as<float>({0.0, 0.0, 0.0});

		SetEntityFlags(client, (flags | FL_ATCONTROLS));

		return Plugin_Changed;
	}

	if (gI_HijackFrames[client])
	{
		--gI_HijackFrames[client];
		angles[0] = gF_HijackedAngles[client][0];
		angles[1] = gF_HijackedAngles[client][1];
	}

	// Wait till now to return so spectators can free-cam while paused...
	if(!IsPlayerAlive(client))
	{
		return Plugin_Changed;
	}

	bool bNoclip = (GetEntityMoveType(client) == MOVETYPE_NOCLIP);

	int iLastButtons = gI_LastButtons[client]; // buttons without effected by code.
	gI_LastButtons[client] = buttons;

	bool bShouldApplyLimit, bLimitSpeed, bBlockBhop, bBlockJump, bReduceSpeed, bNoVerticalSpeed;

	int iZoneStage, iStageZoneSpeedLimitFlags;
	int iTrackStartLimitFlags = Shavit_GetTrackSpeedLimitFlags(gA_Timers[client].iTimerTrack);
	
	bool bInsideStageZone = gA_Timers[client].iTimerTrack == Track_Main ? gB_Zones && Shavit_InsideZoneStage(client, iZoneStage, iStageZoneSpeedLimitFlags):false;
	bool bInsideTrackStartZone = gB_Zones && Shavit_InsideZone(client, Zone_Start, gA_Timers[client].iTimerTrack);
	bool bInsideStageStartZone = (bInsideStageZone && iZoneStage == gA_Timers[client].iLastStage);

	bool bInStart = bInsideTrackStartZone || bInsideStageStartZone;
	
	float fSpeed[3];
	float fCurrentTime;
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);
	float fSpeedXY = (SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)));
	float fLimit = (Shavit_GetStyleSettingFloat(gA_Timers[client].bsStyle, "runspeed") + gCV_PrestrafeLimit.FloatValue);

	if (bInStart && gCV_PrestrafeZone.IntValue > 0)
	{
		if(GetEntityFlags(client) & FL_BASEVELOCITY) // they are on booster, dont limit their speed
		{
			gA_Timers[client].bStageTimeValid = true;
			bBlockBhop   = ((iTrackStartLimitFlags & ZSLF_BlockBhop) > 0);
			bBlockJump   = ((iTrackStartLimitFlags & ZSLF_BlockJump) > 0);
			bNoVerticalSpeed = ((iTrackStartLimitFlags & ZSLF_NoVerticalSpeed) > 0);
		}
		else if(bInsideTrackStartZone)
		{
			fCurrentTime = gA_Timers[client].fCurrentTime;
			bLimitSpeed  = ((iTrackStartLimitFlags & ZSLF_LimitSpeed) > 0);
			bBlockBhop   = ( (iTrackStartLimitFlags & ZSLF_BlockBhop) > 0);
			bBlockJump   = ( (iTrackStartLimitFlags & ZSLF_BlockJump) > 0);
			bReduceSpeed = (  (iTrackStartLimitFlags & ZSLF_ReduceSpeed) > 0);
			bNoVerticalSpeed = (  (iTrackStartLimitFlags & ZSLF_NoVerticalSpeed) > 0);
		}
		else if(gCV_PrestrafeZone.IntValue > 1 && bInsideStageStartZone)
		{
			if(gA_Timers[client].bOnlyStageMode || gCV_PrestrafeZone.IntValue > 2)
			{
				fCurrentTime = gA_Timers[client].bOnlyStageMode ? gA_Timers[client].fCurrentTime:gA_Timers[client].fCurrentTime-gA_Timers[client].aStageStartInfo.fStageStartTime;
				bLimitSpeed  = ((iStageZoneSpeedLimitFlags & ZSLF_LimitSpeed) > 0);
				bBlockBhop   = ( (iStageZoneSpeedLimitFlags & ZSLF_BlockBhop) > 0);
				bBlockJump   = ( (iStageZoneSpeedLimitFlags & ZSLF_BlockJump) > 0);
				bReduceSpeed = (  (iStageZoneSpeedLimitFlags & ZSLF_ReduceSpeed) > 0);
				bNoVerticalSpeed = ((iStageZoneSpeedLimitFlags & ZSLF_NoVerticalSpeed) > 0);
			}
		}

		bShouldApplyLimit = !bNoVerticalSpeed || (fCurrentTime < 1.0 && fSpeedXY <= fLimit);
	}

	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");

	if(!bNoclip && bShouldApplyLimit && GetTimerStatus(client) == Timer_Running)
	{
		int iPrevGroundEntity = (gI_GroundEntity[client] != -1) ? EntRefToEntIndex(gI_GroundEntity[client]) : -1;
		if (bBlockBhop && !bBlockJump && iPrevGroundEntity == -1 && iGroundEntity != -1 && (buttons & IN_JUMP) > 0)
		{	// block bhop
			DumbSetVelocity(client, view_as<float>({0.0, 0.0, 0.0}));
		}
		else if (bLimitSpeed || bReduceSpeed)
		{
			float fScale = (fLimit / fSpeedXY);

			if(fScale < 1.0)
			{
				// add a very low limit to stop prespeeding in an elegant way
				// otherwise, make sure nothing weird is happening (such as sliding at ridiculous speeds, at zone enter)
				if (bReduceSpeed)
				{
					fScale /= 3.0;
				}

				float zSpeed = fSpeed[2];
				fSpeed[2] = 0.0;

				ScaleVector(fSpeed, fScale);
				fSpeed[2] = zSpeed;

				DumbSetVelocity(client, fSpeed);
			}
		}
	}

	gI_GroundEntity[client] = (iGroundEntity != -1) ? EntIndexToEntRef(iGroundEntity) : -1;

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnUserCmdPre);
	Call_PushCell(client);
	Call_PushCellRef(buttons);
	Call_PushCellRef(impulse);
	Call_PushArrayEx(vel, 3, SM_PARAM_COPYBACK);
	Call_PushArrayEx(angles, 3, SM_PARAM_COPYBACK);
	Call_PushCell(GetTimerStatus(client));
	Call_PushCell(gA_Timers[client].iTimerTrack);
	Call_PushCell(gA_Timers[client].bsStyle);
	Call_PushArrayEx(mouse, 2, SM_PARAM_COPYBACK);
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return result;
	}

	if (gA_Timers[client].bTimerEnabled && !gA_Timers[client].bClientPaused)
	{
		// +left/right block
		if(!gB_Zones || (!bInStart && ((GetStyleSettingInt(gA_Timers[client].bsStyle, "block_pleft") > 0 &&
			(buttons & IN_LEFT) > 0) || (GetStyleSettingInt(gA_Timers[client].bsStyle, "block_pright") > 0 && (buttons & IN_RIGHT) > 0))))
		{
			vel[0] = 0.0;
			vel[1] = 0.0;

			if(GetStyleSettingInt(gA_Timers[client].bsStyle, "block_pright") >= 2)
			{
				char sCheatDetected[64];
				FormatEx(sCheatDetected, 64, "%T", "LeftRightCheat", client);
				StopTimer_Cheat(client, sCheatDetected);
			}
		}

		// +strafe block
		if (GetStyleSettingInt(gA_Timers[client].bsStyle, "block_pstrafe") > 0 &&
			!GetStyleSettingBool(gA_Timers[client].bsStyle, "autostrafe") &&
			((vel[0] > 0.0 && (buttons & IN_FORWARD) == 0) || (vel[0] < 0.0 && (buttons & IN_BACK) == 0) ||
			(vel[1] > 0.0 && (buttons & IN_MOVERIGHT) == 0) || (vel[1] < 0.0 && (buttons & IN_MOVELEFT) == 0)))
		{
			if (gA_Timers[client].fStrafeWarning < gA_Timers[client].fCurrentTime)
			{
				if (GetStyleSettingInt(gA_Timers[client].bsStyle, "block_pstrafe") >= 2)
				{
					char sCheatDetected[64];
					FormatEx(sCheatDetected, 64, "%T", "Inconsistencies", client);
					StopTimer_Cheat(client, sCheatDetected);
				}

				vel[0] = 0.0;
				vel[1] = 0.0;

				return Plugin_Changed;
			}

			gA_Timers[client].fStrafeWarning = gA_Timers[client].fCurrentTime + 0.3;
		}
	}

	#if DEBUG
	static int cycle = 0;

	if(++cycle % 50 == 0)
	{
		Shavit_StopChatSound();
		Shavit_PrintToChat(client, "vel[0]: %.01f | vel[1]: %.01f", vel[0], vel[1]);
	}
	#endif

	MoveType mtMoveType = GetEntityMoveType(client);

	if(mtMoveType == MOVETYPE_LADDER && gCV_SimplerLadders.BoolValue)
	{
		gA_Timers[client].bCanUseAllKeys = true;
	}
	else if(iGroundEntity != -1)
	{
		gA_Timers[client].bCanUseAllKeys = false;
	}

	// key blocking
	if(!gA_Timers[client].bCanUseAllKeys && mtMoveType != MOVETYPE_NOCLIP && mtMoveType != MOVETYPE_LADDER && !(gB_Zones && Shavit_InsideZone(client, Zone_Freestyle, -1)))
	{
		// block E
		if (GetStyleSettingBool(gA_Timers[client].bsStyle, "block_use") && (buttons & IN_USE) > 0)
		{
			buttons &= ~IN_USE;
		}

		if (iGroundEntity == -1 || GetStyleSettingBool(gA_Timers[client].bsStyle, "force_groundkeys"))
		{
			if (GetStyleSettingBool(gA_Timers[client].bsStyle, "block_w") && ((buttons & IN_FORWARD) > 0 || vel[0] > 0.0))
			{
				vel[0] = 0.0;
				buttons &= ~IN_FORWARD;
			}

			if (GetStyleSettingBool(gA_Timers[client].bsStyle, "block_a") && ((buttons & IN_MOVELEFT) > 0 || vel[1] < 0.0))
			{
				vel[1] = 0.0;
				buttons &= ~IN_MOVELEFT;
			}

			if (GetStyleSettingBool(gA_Timers[client].bsStyle, "block_s") && ((buttons & IN_BACK) > 0 || vel[0] < 0.0))
			{
				vel[0] = 0.0;
				buttons &= ~IN_BACK;
			}

			if (GetStyleSettingBool(gA_Timers[client].bsStyle, "block_d") && ((buttons & IN_MOVERIGHT) > 0 || vel[1] > 0.0))
			{
				vel[1] = 0.0;
				buttons &= ~IN_MOVERIGHT;
			}

			if (GetStyleSettingBool(gA_Timers[client].bsStyle, "a_or_d_only"))
			{
				int iCombination = -1;
				bool bMoveLeft = ((buttons & IN_MOVELEFT) > 0 && vel[1] < 0.0);
				bool bMoveRight = ((buttons & IN_MOVERIGHT) > 0 && vel[1] > 0.0);

				if (bMoveLeft)
				{
					iCombination = 0;
				}
				else if (bMoveRight)
				{
					iCombination = 1;
				}

				if (iCombination != -1)
				{
					if (gA_Timers[client].iKeyCombo == -1)
					{
						gA_Timers[client].iKeyCombo = iCombination;
					}

					if (iCombination != gA_Timers[client].iKeyCombo)
					{
						vel[1] = 0.0;
						buttons &= ~(IN_MOVELEFT|IN_MOVERIGHT);
					}
				}
			}

			// HSW
			// Theory about blocking non-HSW strafes while playing HSW:
			// Block S and W without A or D.
			// Block A and D without S or W.
			if (GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") > 0)
			{
				bool bSHSW = (GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") == 2) && !bInStart; // don't decide on the first valid input until out of start zone!
				int iCombination = -1;

				bool bForward = ((buttons & IN_FORWARD) > 0 && vel[0] > 0.0);
				bool bMoveLeft = ((buttons & IN_MOVELEFT) > 0 && vel[1] < 0.0);
				bool bBack = ((buttons & IN_BACK) > 0 && vel[0] < 0.0);
				bool bMoveRight = ((buttons & IN_MOVERIGHT) > 0 && vel[1] > 0.0);

				if(bSHSW)
				{
					if((bForward && bMoveLeft) || (bBack && bMoveRight))
					{
						iCombination = 0;
					}
					else if((bForward && bMoveRight || bBack && bMoveLeft))
					{
						iCombination = 1;
					}

					// int gI_SHSW_FirstCombination[MAXPLAYERS+1]; // 0 - W/A S/D | 1 - W/D S/A
					if(gA_Timers[client].iKeyCombo == -1 && iCombination != -1)
					{
						Shavit_PrintToChat(client, "%T", (iCombination == 0)? "SHSWCombination0":"SHSWCombination1", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
						gA_Timers[client].iKeyCombo = iCombination;
					}

					// W/A S/D
					if((gA_Timers[client].iKeyCombo == 0 && iCombination != 0) ||
					// W/D S/A
						(gA_Timers[client].iKeyCombo == 1 && iCombination != 1) ||
					// no valid combination & no valid input
						(gA_Timers[client].iKeyCombo == -1 && iCombination == -1))
					{
						vel[0] = 0.0;
						vel[1] = 0.0;

						buttons &= ~IN_FORWARD;
						buttons &= ~IN_MOVELEFT;
						buttons &= ~IN_MOVERIGHT;
						buttons &= ~IN_BACK;
					}
				}
				else
				{
					if(bBack && (bMoveLeft || bMoveRight))
					{
						vel[0] = 0.0;

						buttons &= ~IN_FORWARD;
						buttons &= ~IN_BACK;
					}

					if(bForward && !(bMoveLeft || bMoveRight))
					{
						vel[0] = 0.0;

						buttons &= ~IN_FORWARD;
						buttons &= ~IN_BACK;
					}

					if((bMoveLeft || bMoveRight) && !bForward)
					{
						vel[1] = 0.0;

						buttons &= ~IN_MOVELEFT;
						buttons &= ~IN_MOVERIGHT;
					}
				}
			}
		}
	}

	bool bInWater = (GetEntProp(client, Prop_Send, "m_nWaterLevel") >= 2);
	int iOldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");

	// enable duck-jumping/bhop in tf2
	if (gEV_Type == Engine_TF2 && GetStyleSettingBool(gA_Timers[client].bsStyle, "bunnyhopping") && (buttons & IN_JUMP) > 0 && iGroundEntity != -1)
	{
		float fAbsSpeed[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsSpeed);

		fAbsSpeed[2] = 289.0;
		SetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsSpeed);
	}

	// perf jump measuring
	bool bOnGround = (!bInWater && mtMoveType == MOVETYPE_WALK && iGroundEntity != -1);

	gI_LastTickcount[client] = tickcount;

	if(gB_Zones && Shavit_InsideZone(client, Zone_NoJump, gA_Timers[client].iTimerTrack))
	{
		bBlockJump = true;
	}

	if (bBlockJump && (vel[2] > 0 || (buttons & IN_JUMP) > 0) && !bInWater)
	{
		if((iLastButtons & IN_JUMP) == 0 && (buttons & IN_JUMP) > 0 && bOnGround)
		{
			Shavit_PrintToChat(client, "%T", "NotAllowJump", client);
		}

		sv_autobunnyhopping.ReplicateToClient(client, "0");
		
		vel[2] = 0.0;
		buttons &= ~IN_JUMP;
	}
	else if ((buttons & IN_JUMP) > 0 && mtMoveType == MOVETYPE_WALK && !bInWater)
	{
		if ((gB_Auto[client] && GetStyleSettingBool(gA_Timers[client].bsStyle, "autobhop")) 
		|| (gB_Zones && Shavit_InsideZone(client, Zone_Autobhop, gA_Timers[client].iTimerTrack)))
		{	// just force autobhop enabled in autobhop zone whatever situation
			sv_autobunnyhopping.ReplicateToClient(client, "1");
			SetEntProp(client, Prop_Data, "m_nOldButtons", (iOldButtons &= ~IN_JUMP));	
		}
		else
		{
			sv_autobunnyhopping.ReplicateToClient(client, "0");
		}
	}
	else
	{
		sv_autobunnyhopping.ReplicateToClient(client, "0");
	}

	if(mtMoveType == MOVETYPE_NOCLIP)
	{
		gI_LastNoclipTick[client] = tickcount;
	}

	if(bOnGround && !gA_Timers[client].bOnGround)
	{
		gA_Timers[client].iLandingTick = tickcount;
		gI_FirstTouchedGround[client] = tickcount;

		if (gEV_Type != Engine_TF2 && GetStyleSettingBool(gA_Timers[client].bsStyle, "easybhop"))
		{
			SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
		}
	}
	else if (!bOnGround && gA_Timers[client].bOnGround && gA_Timers[client].bJumped && !gA_Timers[client].bClientPaused)
	{
		int iDifference = (tickcount - gA_Timers[client].iLandingTick);

		if (iDifference < 10)
		{
			gA_Timers[client].iMeasuredJumps++;

			if (iDifference == 1)
			{
				gA_Timers[client].iPerfectJumps++;
			}
		}
	}

	// This can be bypassed by spamming +duck on CSS which causes `iGroundEntity` to be `-1` here...
	//   (e.g. an autobhop + velocity_limit style...)
	// m_hGroundEntity changes from 0 -> -1 same tick which causes problems and I'm not sure what the best way / place to handle that is...
	// There's not really many things using m_hGroundEntity that "matter" in this function
	// so I'm just going to move this `velocity_limit` logic somewhere else instead of trying to "fix" it.
	// Now happens in `VelocityChanges()` which comes from `player_jump->RequestFrame(VelocityChanges)`.
	//   (that is also the same thing btimes does)
#if 0
	// velocity limit
	if (iGroundEntity != -1 && GetStyleSettingFloat(gA_Timers[client].bsStyle, "velocity_limit") > 0.0)
	{
		float fSpeedLimit = GetStyleSettingFloat(gA_Timers[client].bsStyle, "velocity_limit");

		if(gB_Zones && Shavit_InsideZone(client, Zone_CustomSpeedLimit, -1))
		{
			fSpeedLimit = gF_ZoneSpeedLimit[client];
		}

		float fSpeed[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);

		float fSpeed_New = (SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)));

		if(fSpeedLimit != 0.0 && fSpeed_New > 0.0)
		{
			float fScale = fSpeedLimit / fSpeed_New;

			if(fScale < 1.0)
			{
				fSpeed[0] *= fScale;
				fSpeed[1] *= fScale;
				TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed); // maybe change this to SetEntPropVector some time?
			}
		}
	}
#endif


	gA_Timers[client].bJumped = false;
	gA_Timers[client].bOnGround = bOnGround;

	return Plugin_Continue;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (IsFakeClient(client))
	{
		return;
	}

	if (!IsPlayerAlive(client) || GetTimerStatus(client) != Timer_Running)
	{
		return;
	}

	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");

	if (iGroundEntity == -1
	&& GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_w")
	&& !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_w")
	&& (gA_Timers[client].fLastInputVel[0] <= 0.0) && (vel[0] > 0.0)
	&& GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") != 1
	)
	{
		gA_Timers[client].iStrafes++;
	}

	if (iGroundEntity == -1
	&& GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_s")
	&& !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_s")
	&& (gA_Timers[client].fLastInputVel[0] >= 0.0) && (vel[0] < 0.0)
	)
	{
		gA_Timers[client].iStrafes++;
	}

	if (iGroundEntity == -1
	&& GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_a")
	&& !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_a")
	&& (gA_Timers[client].fLastInputVel[1] >= 0.0) && (vel[1] < 0.0)
	&& (GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") > 0 || vel[0] == 0.0)
	)
	{
		gA_Timers[client].iStrafes++;
	}

	if (iGroundEntity == -1
	&& GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_d")
	&& !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_d")
	&& (gA_Timers[client].fLastInputVel[1] <= 0.0) && (vel[1] > 0.0)
	&& (GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") > 0 || vel[0] == 0.0)
	)
	{
		gA_Timers[client].iStrafes++;
	}

	float fAngle = GetAngleDiff(angles[1], gA_Timers[client].fLastAngle);

	float fAbsVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);
	float curVel = SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0));

	bool bIsSurfing = Shavit_Bhopstats_IsSurfing(client);

	if (iGroundEntity == -1 && !bIsSurfing && GetEntityMoveType(client) != MOVETYPE_LADDER && (GetEntityFlags(client) & FL_INWATER) == 0 && fAngle != 0.0 && curVel > 0.0)
	{
		float fTempAngle = angles[1];

		float fAngles[3];
		GetVectorAngles(fAbsVelocity, fAngles);

		if (fTempAngle < 0.0)
		{
			fTempAngle += 360.0;
		}

		TestAngles(client, (fTempAngle - fAngles[1]), fAngle, vel);
	}

	if (gA_Timers[client].fCurrentTime != 0.0)
	{
		float frameCount = float(gA_Timers[client].iZoneIncrement);
		float maxVel = gA_Timers[client].fMaxVelocity;
		gA_Timers[client].fMaxVelocity = (curVel > maxVel) ? curVel : maxVel;
		// STOLEN from Epic/Disrevoid. Thx :)
		gA_Timers[client].fAvgVelocity += (curVel - gA_Timers[client].fAvgVelocity) / frameCount;

		if(gA_Timers[client].iLastStage > 1 && !gA_Timers[client].bOnlyStageMode && gA_Timers[client].fCurrentTime != gA_Timers[client].aStageStartInfo.fStageStartTime)
		{
			frameCount = float(gA_Timers[client].aStageStartInfo.iZoneIncrement);
			maxVel = gA_Timers[client].aStageStartInfo.fMaxVelocity;
			gA_Timers[client].aStageStartInfo.fMaxVelocity = (curVel > maxVel) ? curVel : maxVel;	
			gA_Timers[client].aStageStartInfo.fAvgVelocity += (curVel - gA_Timers[client].aStageStartInfo.fAvgVelocity) / frameCount;
		}
	}

	gA_Timers[client].iLastButtons = buttons;
	gA_Timers[client].fLastAngle = angles[1];
	gA_Timers[client].fLastInputVel[0] = vel[0];
	gA_Timers[client].fLastInputVel[1] = vel[1];
}

void TestAngles(int client, float dirangle, float yawdelta, const float vel[3])
{
	if(dirangle < 0.0)
	{
		dirangle = -dirangle;
	}

	// normal
	if(dirangle < 22.5 || dirangle > 337.5)
	{
		gA_Timers[client].iTotalMeasures++;

		if((yawdelta > 0.0 && vel[1] <= -100.0) || (yawdelta < 0.0 && vel[1] >= 100.0))
		{
			gA_Timers[client].iGoodGains++;
		}
	}

	// hsw (thanks nairda!)
	else if((dirangle > 22.5 && dirangle < 67.5))
	{
		gA_Timers[client].iTotalMeasures++;

		if((yawdelta != 0.0) && (vel[0] >= 100.0 || vel[1] >= 100.0) && (vel[0] >= -100.0 || vel[1] >= -100.0))
		{
			gA_Timers[client].iGoodGains++;
		}
	}

	// backwards hsw
	else if((dirangle > 112.5 && dirangle < 157.5) || (dirangle > 202.5 && dirangle < 247.5))
	{
		gA_Timers[client].iTotalMeasures++;

		if((yawdelta != 0.0) && (vel[0] >= 100.0 || vel[1] >= 100.0) && (vel[0] >= -100.0 || vel[1] >= -100.0))
		{
			gA_Timers[client].iGoodGains++;
		}
	}

	// sw
	else if((dirangle > 67.5 && dirangle < 112.5) || (dirangle > 247.5 && dirangle < 292.5))
	{
		gA_Timers[client].iTotalMeasures++;

		if(vel[0] <= -100.0 || vel[0] >= 100.0)
		{
			gA_Timers[client].iGoodGains++;
		}
	}
}

void StopTimer_Cheat(int client, const char[] message)
{
	Shavit_StopTimer(client);
	Shavit_PrintToChat(client, "%T", "CheatTimerStop", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, message);
}

void UpdateAiraccelerate(int client, float airaccelerate)
{
	char sAiraccelerate[8];
	FloatToString(airaccelerate, sAiraccelerate, 8);
	sv_airaccelerate.ReplicateToClient(client, sAiraccelerate);
}

void UpdateStyleSettings(int client)
{
	if (IsFakeClient(client)) return;

	if(sv_enablebunnyhopping != null)
	{
		if (gB_Zones && Shavit_InsideZone(client, Zone_CustomSpeedLimit, gA_Timers[client].iTimerTrack))
		{
			sv_enablebunnyhopping.ReplicateToClient(client, "1");
		}
		else
		{
			sv_enablebunnyhopping.ReplicateToClient(client, (GetStyleSettingBool(gA_Timers[client].bsStyle, "bunnyhopping"))? "1":"0");
		}
	}

	if (gB_Zones && Shavit_InsideZone(client, Zone_Airaccelerate, gA_Timers[client].iTimerTrack))
	{
		UpdateAiraccelerate(client, gF_ZoneAiraccelerate[client]);
	}
	else
	{
		UpdateAiraccelerate(client, GetStyleSettingFloat(gA_Timers[client].bsStyle, "airaccelerate"));
	}
}

public void ShowMessageSettingMenu(int client, int item)
{
	Menu menu = new Menu(MenuHandler_MessageSetting, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);

	SetMenuTitle(menu, "%T\n ", "MessageMenuTitle", client);

	char sInfo[16];
	char sItem[64];

	FormatEx(sInfo, 16, "%d", MSG_FINISHMAP);
	FormatEx(sItem, 64, "%T", "MsgFinishMap", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", MSG_FINISHSTAGE);
	FormatEx(sItem, 64, "%T", "MsgFinishStage", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", MSG_OTHER);
	FormatEx(sItem, 64, "%T", "MsgOther", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", MSG_WORLDRECORD);
	FormatEx(sItem, 64, "%T", "MsgWorldRecord", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", MSG_CHECKPOINT);
	FormatEx(sItem, 64, "%T", "MsgCheckpoint", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", MSG_SPEEDTRAP);
	FormatEx(sItem, 64, "%T", "MsgSpeedTrap", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", MSG_EXTRAFINISHINFO);
	FormatEx(sItem, 64, "%T", "MsgExtraFinishInfo", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", MSG_PRACALERT);
	FormatEx(sItem, 64, "%T", "MsgPracticeModeAlert", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", MSG_POINTINFO);
	FormatEx(sItem, 64, "%T", "MsgPointInfo", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", MSG_ADVERTISEMENT);
	FormatEx(sItem, 64, "%T", "MsgAdvertisement", client);
	menu.AddItem(sInfo, sItem);

	menu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int MenuHandler_MessageSetting(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sCookie[16];
		menu.GetItem(param2, sCookie, 16);

		int iSelection = StringToInt(sCookie);

		gI_MessageSettings[param1] ^= iSelection;
		IntToString(gI_MessageSettings[param1], sCookie, 16);
		SetClientCookie(param1, gH_MessageCookie, sCookie);

		ShowMessageSettingMenu(param1, GetMenuSelectionPosition());
	}
	else if(action == MenuAction_DisplayItem)
	{
		char sInfo[16];
		char sDisplay[64];
		int style = 0;
		
		menu.GetItem(param2, sInfo, 16, style, sDisplay, 64);
		int iSelection = StringToInt(sInfo);

		Format(sDisplay, 64, "[%T] %s", ((gI_MessageSettings[param1] & iSelection) == 0) ? "ItemEnabled":"ItemDisabled", param1, sDisplay);

		return RedrawMenuItem(sDisplay);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}
