/*
 * shavit's Timer - Replay Recorder
 * by: shavit, rtldg, KiD Fearless, Ciallo-Ani, BoomShotKapow
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
#include <convar_class>

#include <shavit/replay-recorder>

#include <shavit/core>

#undef REQUIRE_PLUGIN
#include <shavit/replay-playback>
#include <shavit/zones>

#include <shavit/replay-file>
#include <shavit/replay-stocks.sp>

public Plugin myinfo =
{
	name = "[shavit-surf] Replay Recorder",
	author = "shavit, rtldg, KiD Fearless, Ciallo-Ani, BoomShotKapow, *Surf integration version modified by KikI",
	description = "A replay recorder for shavit surf timer. (This plugin is base on shavit's bhop timer)",
	version = SHAVIT_SURF_VERSION,
	url = "https://github.com/shavitush/bhoptimer  https://github.com/bhopppp/Shavit-Surf-Timer"
}

enum struct finished_run_info
{
	int iSteamID;
	int style;
	float time;
	int jumps;
	int strafes;
	float sync;
	int track;
	int stage;
	float oldtime;
	float perfs;
	float avgvel;
	float maxvel;
	int timestamp;
	float fZoneOffset[2];
}

bool gB_Late = false;
char gS_Map[PLATFORM_MAX_PATH];
char gS_PreviousMap[PLATFORM_MAX_PATH];
float gF_Tickrate = 0.0;
int gI_FailureThresholdTick;

int gI_AFKTickCount[MAXPLAYERS+1];
int gI_AFKThresholdTick;

int gI_Styles = 0;
char gS_ReplayFolder[PLATFORM_MAX_PATH];

Convar gCV_Enabled = null;
Convar gCV_PlaybackPostRunTime = null;
Convar gCV_PlaybackPreRunTime = null;
Convar gCV_PreRunAlways = null;
Convar gCV_TimeLimit = null;
Convar gCV_ClearFrameDelay = null;
Convar gCV_TrimFrames = null;
Convar gCV_FailureThreshold = null;
Convar gCV_AFKThreshold = null;

Handle gH_ShouldSaveReplayCopy = null;
Handle gH_OnReplaySaved = null;

bool gB_RecordingEnabled[MAXPLAYERS+1]; // just a simple thing to prevent plugin reloads from recording half-replays
bool gB_TrimFailureFrames; // this is used to trim the failure frames of stages
bool gB_TrimAFKFrames; // this is used to trim the afk frames while player in stage start zone

// stuff related to postframes
finished_run_info gA_FinishedRunInfo[MAXPLAYERS+1][2];
int gI_StageReachFrame[MAXPLAYERS+1];
int gI_LastStageReachFrame[MAXPLAYERS+1];
bool gB_GrabbingPostFrames[MAXPLAYERS+1][2];
bool gB_DelayClearFrame[MAXPLAYERS+1];
Handle gH_PostFramesTimer[MAXPLAYERS+1][2];
Handle gH_ClearFramesDelay[MAXPLAYERS+1]; // We have 2 replay to save if player finish the last stage and the map at the same time, so we need to wait for 0.1s to avoid resize array to -1.
int gI_PlayerFinishFrame[MAXPLAYERS+1];

// we use gI_PlayerFrames instead of grabbing gA_PlayerFrames.Length because the ArrayList is resized to handle 2s worth of extra frames to reduce how often we have to resize it
int gI_PlayerFrames[MAXPLAYERS+1];
int gI_PlayerPrerunFrames[MAXPLAYERS+1];
int gI_PlayerStageStartFrames[MAXPLAYERS+1];
int gI_LastPlayerStageStartFrames[MAXPLAYERS+1];
int gI_RealFrameCount[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];
ArrayList gA_FrameOffsets[MAXPLAYERS+1];

int gI_HijackFrames[MAXPLAYERS+1];
float gF_HijackedAngles[MAXPLAYERS+1][2];
bool gB_HijackFramesKeepOnStart[MAXPLAYERS+1];

bool gB_ReplayPlayback = false;

//#include <TickRateControl>
forward void TickRate_OnTickRateChanged(float fOld, float fNew);

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetClientFrameCount", Native_GetClientFrameCount);
	CreateNative("Shavit_GetPlayerPreFrames", Native_GetPlayerPreFrames);
	CreateNative("Shavit_GetReplayData", Native_GetReplayData);
	CreateNative("Shavit_GetStageStartFrames", Native_GetStageStartFrames);
	CreateNative("Shavit_GetStageReachFrames", Native_GetStageReachFrames);
	CreateNative("Shavit_GetPlayerFrameOffsets", Native_GetPlayerFrameOffsets);	
	CreateNative("Shavit_SetPlayerFrameOffsets", Native_SetPlayerFrameOffsets);
	CreateNative("Shavit_HijackAngles", Native_HijackAngles);
	CreateNative("Shavit_SetReplayData", Native_SetReplayData);
	CreateNative("Shavit_SetPlayerPreFrames", Native_SetPlayerPreFrames);
	CreateNative("Shavit_SetStageStartFrames", Native_SetStageStartFrames);
	CreateNative("Shavit_SetStageReachFrames", Native_SetStageReachFrames);
	CreateNative("Shavit_EditReplayFrames", Native_EditReplayFrames);

	if (!FileExists("cfg/sourcemod/plugin.shavit-replay-recorder.cfg") && FileExists("cfg/sourcemod/plugin.shavit-replay.cfg"))
	{
		File source = OpenFile("cfg/sourcemod/plugin.shavit-replay.cfg", "r");
		File destination = OpenFile("cfg/sourcemod/plugin.shavit-replay-recorder.cfg", "w");

		if (source && destination)
		{
			char line[512];

			while (!source.EndOfFile() && source.ReadLine(line, sizeof(line)))
			{
				destination.WriteLine("%s", line);
			}
		}

		delete destination;
		delete source;
	}

	RegPluginLibrary("shavit-replay-recorder");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	gH_ShouldSaveReplayCopy = CreateGlobalForward("Shavit_ShouldSaveReplayCopy", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnReplaySaved = CreateGlobalForward("Shavit_OnReplaySaved", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_String);

	gCV_Enabled = new Convar("shavit_replay_recording_enabled", "1", "Enable replay bot functionality?", 0, true, 0.0, true, 1.0);
	gCV_PlaybackPostRunTime = new Convar("shavit_replay_postruntime", "0.2", "Time (in seconds) to record after a player enters the end zone.", 0, true, 0.0, true, 2.0);
	gCV_PreRunAlways = new Convar("shavit_replay_prerun_always", "1", "Record prerun frames outside the start zone?", 0, true, 0.0, true, 1.0);
	gCV_PlaybackPreRunTime = new Convar("shavit_replay_preruntime", "1.7", "Time (in seconds) to record before a player leaves start zone.", 0, true, 0.0, true, 3.0);
	gCV_TimeLimit = new Convar("shavit_replay_timelimit", "7200.0", "Maximum amount of time (in seconds) to allow saving to disk.\nDefault is 7200 (2 hours)\n0 - Disabled", 0, true, 0.0);
	gCV_ClearFrameDelay = new Convar("shavit_replay_clearframedelay", "0.2", "Time of delay before call ClearFrames(),\nin order to avoid cleaning frame before replay edit finish.", 0, true, 0.1, true, 0.5);
	gCV_TrimFrames = new Convar("shavit_replay_trimframes", "2", "Trim all useless frames?\n(You need to use shavit-mapfixes.cfg or config file to TOGGLE this feature)\n0 - Disable\n1 - Trim stage failure frames\n2 - Trim stage failure frames and afk frames while in stage start zone", 0, true, 0.0, true, 2.0);
	gCV_FailureThreshold = new Convar("shavit_replay_trim_failureframe_threshold", "0.5", "How many seconds after leaving start zone should count as a failure attempt if player returns to stage start", 0, true, 0.0, true, 0.8);
	gCV_AFKThreshold = new Convar("shavit_replay_trim_afkframe_threshold", "10.0", "How many seconds after player AFKs should recorder trim frames during afk in stage start", 0, true, 5.0, false);

	Convar.AutoExecConfig();

	gCV_TrimFrames.AddChangeHook(OnConVarChanged);
	gCV_FailureThreshold.AddChangeHook(OnConVarChanged);
	gCV_AFKThreshold.AddChangeHook(OnConVarChanged);

	gF_Tickrate = (1.0 / GetTickInterval());

	gB_ReplayPlayback = LibraryExists("shavit-replay-playback");

	if (gB_Late)
	{
		Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount());

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if( StrEqual(name, "shavit-replay-playback"))
	{
		gB_ReplayPlayback = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "shavit-replay-playback"))
	{
		gB_ReplayPlayback = false;
	}
}

public void OnConfigsExecuted()
{
	if(!StrEqual(gS_Map, gS_PreviousMap))
	{
		gB_TrimFailureFrames = gCV_TrimFrames.IntValue > 0;
		gB_TrimAFKFrames = gCV_TrimFrames.IntValue > 1;
	}
	
	gI_FailureThresholdTick = RoundToFloor(gCV_FailureThreshold.FloatValue * gF_Tickrate);
	gI_AFKThresholdTick = RoundToFloor(gCV_AFKThreshold.FloatValue * gF_Tickrate);
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == gCV_TrimFrames)
	{
		int iOldValue = StringToInt(oldValue);
		int iNewValue = gCV_TrimFrames.IntValue;

		if((iOldValue == 0 && iNewValue > 0) || (iOldValue >= 1 && iNewValue == 0))
		{	// this has bug, but i dont think i need to fix it
			PrintToServer("Toggle this feature from changing this convar while in a map will not take effect, Please modify in the config file or shavit-mapfixes.cfg");			
		}
		else
		{
			gB_TrimFailureFrames = iNewValue > 0;
			gB_TrimAFKFrames = iNewValue > 1;
		}
	}
	else if(convar == gCV_FailureThreshold)
	{
		gI_FailureThresholdTick = RoundToFloor(gCV_FailureThreshold.FloatValue * gF_Tickrate);
	}
	else if(convar == gCV_AFKThreshold)
	{
		gI_AFKThresholdTick = RoundToFloor(gCV_AFKThreshold.FloatValue * gF_Tickrate);
	}
}

public void OnMapStart()
{
	GetLowercaseMapName(gS_Map);
}

public void OnMapEnd()
{
	gS_PreviousMap = gS_Map;
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if (!Shavit_GetReplayFolderPath_Stock(gS_ReplayFolder))
	{
		SetFailState("Could not load the replay bots' configuration file. Make sure it exists (addons/sourcemod/configs/shavit-replay.cfg) and follows the proper syntax!");
	}

	gI_Styles = styles;

	Shavit_Replay_CreateDirectories(gS_ReplayFolder, gI_Styles);
}

public void OnClientPutInServer(int client)
{
	ClearFrames(client);
}

public void OnClientDisconnect(int client)
{
	gB_RecordingEnabled[client] = false;

	if (gB_GrabbingPostFrames[client][1])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][1], 1, true);
	}

	if (gB_GrabbingPostFrames[client][0])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][0], 0, true);
	}
}

public void OnClientDisconnect_Post(int client)
{
	// This runs after shavit-misc has cloned the handle
	delete gA_PlayerFrames[client];
	delete gA_FrameOffsets[client];
}

public void TickRate_OnTickRateChanged(float fOld, float fNew)
{
	gF_Tickrate = fNew;
	gI_FailureThresholdTick = RoundToFloor(gCV_FailureThreshold.FloatValue * gF_Tickrate);
	gI_AFKThresholdTick = RoundToFloor(gCV_AFKThreshold.FloatValue * gF_Tickrate);
}

void ClearFrames(int client)
{
	delete gA_PlayerFrames[client];
	delete gA_FrameOffsets[client];
	gA_PlayerFrames[client] = new ArrayList(sizeof(frame_t));
	gA_FrameOffsets[client] = new ArrayList(sizeof(offset_info_t), 2);
	gI_RealFrameCount[client] = 0;
	gI_PlayerFrames[client] = 0;
	gI_PlayerPrerunFrames[client] = 0;
	gI_PlayerFinishFrame[client] = 0;
	gI_HijackFrames[client] = 0;
	gB_HijackFramesKeepOnStart[client] = false;
}

public Action Shavit_OnFinishStagePre(int client, timer_snapshot_t snapshot)
{
	if(snapshot.bPracticeMode || snapshot.bOnlyStageMode)
	{
		return Plugin_Continue;
	}

	offset_info_t offsets;

	if(snapshot.iLastStage > 1)
	{
		gI_LastPlayerStageStartFrames[client] = gI_PlayerStageStartFrames[client];
		gI_LastStageReachFrame[client] = gI_StageReachFrame[client];

		if(gB_TrimFailureFrames)
		{
			gA_FrameOffsets[client].GetArray(snapshot.iLastStage, offsets, sizeof(offset_info_t));
			offsets.iFailureAttempts = snapshot.iStageAttempts[snapshot.iLastStage] - 1;				
		}
	}

	if(gB_TrimFailureFrames)
	{
		gA_FrameOffsets[client].SetArray(snapshot.iLastStage, offsets, sizeof(offset_info_t));			
	}

	return Plugin_Continue;
}

public Action Shavit_OnStart(int client)
{
	gB_RecordingEnabled[client] = true;

	if (!gB_HijackFramesKeepOnStart[client])
	{
		gI_HijackFrames[client] = 0;
	}

	if (gB_GrabbingPostFrames[client][1])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][1], 1, true);
	}

	if (gB_GrabbingPostFrames[client][0])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][0], 0, true);
	}

	if(gB_DelayClearFrame[client])
	{
		EndClearFrameDelay(client);
	}

	int iMaxPreFrames = RoundToFloor(gCV_PlaybackPreRunTime.FloatValue * gF_Tickrate / Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(client), "speed"));
	int iZoneStage;
	int track = Shavit_GetClientTrack(client);
	bool bInsideStageZone = track == Track_Main ? Shavit_InsideZoneStage(client, iZoneStage):false;
	
	bool bInStart = Shavit_InsideZone(client, Zone_Start, track) || 
					(Shavit_IsOnlyStageMode(client) && bInsideStageZone && iZoneStage == Shavit_GetClientLastStage(client));

	if (bInStart)
	{
		if(gB_TrimFailureFrames && (gA_FrameOffsets[client].Length > 2 || gA_FrameOffsets[client].Get(1) != 0))
		{
			gA_FrameOffsets[client].Resize(2);
		}

		int iFrameDifference = gI_PlayerFrames[client] - iMaxPreFrames;

		if (iFrameDifference > 0)
		{
			// For too many extra frames, we'll just shift the preframes to the start of the array.
			if (iFrameDifference > 100)
			{
				for (int i = iFrameDifference; i < gI_PlayerFrames[client]; i++)
				{
					gA_PlayerFrames[client].SwapAt(i, i-iFrameDifference);
				}

				gI_PlayerFrames[client] = iMaxPreFrames;
			}
			else // iFrameDifference isn't that bad, just loop through and erase.
			{
				while (iFrameDifference--)
				{
					gA_PlayerFrames[client].Erase(0);
					gI_PlayerFrames[client]--;
				}
			}

			gI_RealFrameCount[client] = gI_PlayerFrames[client];
		}
	}
	else
	{
		if (!gCV_PreRunAlways.BoolValue)
		{
			ClearFrames(client);
		}
	}

	gI_PlayerPrerunFrames[client] = gI_PlayerFrames[client];

	return Plugin_Continue;
}

public Action Shavit_OnStageStart(int client, int stage, bool restart, bool first)
{
	if (Shavit_IsPracticeMode(client))
	{
		return Plugin_Continue;
	}

	if(gB_TrimFailureFrames && restart && !first) // keeps the frame original if player one shots this stage
	{
		if(gI_StageReachFrame[client] != gI_PlayerFrames[client] 
		&& gI_PlayerFrames[client] - gI_PlayerStageStartFrames[client] > gI_FailureThresholdTick) // do not cut the frame if player reentered start while prespeeding
		{	
			gI_PlayerFrames[client] = gI_StageReachFrame[client];

			int offset = gI_RealFrameCount[client] - gI_PlayerFrames[client];
			gA_FrameOffsets[client].Set(stage, offset);
		}
	}

	gI_PlayerStageStartFrames[client] = gI_PlayerFrames[client];

	if(gB_TrimAFKFrames && !restart && gI_AFKTickCount[client] > gI_AFKThresholdTick)
	{
		gI_PlayerFrames[client] = gI_StageReachFrame[client];

		int offset = gI_RealFrameCount[client] - gI_PlayerFrames[client];
		gA_FrameOffsets[client].Set(stage, offset);
	}

	return Plugin_Continue;
}

public void Shavit_OnStop(int client)
{
	if(gB_GrabbingPostFrames[client][1])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][1], 1, true);
	}

	if (gB_GrabbingPostFrames[client][0])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][0], 0, true);
	}

	ClearFrames(client);
}

public void Shavit_OnReachNextStage(int client, int track, int startStage, int endStage)
{
	if(Shavit_IsPracticeMode(client))
	{
		return;
	}

	if(!Shavit_IsOnlyStageMode(client) && track == Track_Main)
	{
		gI_StageReachFrame[client] = gI_PlayerFrames[client];

		if(gB_TrimFailureFrames)
		{
			offset_info_t offsets;
			offsets.iFrameOffset = gI_RealFrameCount[client] - gI_PlayerFrames[client]; 
			offsets.fReachTime = Shavit_GetClientTime(client);

			// set offsets to new stage
			gA_FrameOffsets[client].Resize(endStage + 1);
			gA_FrameOffsets[client].SetArray(endStage, offsets, sizeof(offset_info_t));
		}
	}
}

public Action Timer_PostFrames(Handle timer, int client)
{
	if (gB_GrabbingPostFrames[client][1])
	{
		gH_PostFramesTimer[client][1] = null;
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][1], 1, true);
	}

	gH_PostFramesTimer[client][0] = null;
	FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][0], 0, false);

	return Plugin_Stop;
}

public Action Timer_StagePostFrames(Handle timer, int client)
{
	gH_PostFramesTimer[client][1] = null;

	if (gB_GrabbingPostFrames[client][1])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][1], 1, false);
	}

	return Plugin_Stop;
}

public Action Timer_ClearFrames(Handle timer, int client)
{
	gH_ClearFramesDelay[client] = null;

	if(gB_DelayClearFrame[client])
	{
		gB_DelayClearFrame[client] = false;
		ClearFrames(client);
	}

	return Plugin_Stop;
}

void EndClearFrameDelay(int client)
{
	gB_DelayClearFrame[client] = false;

	ClearFrames(client);
}

void FinishGrabbingPostFrames(int client, finished_run_info info, int index, bool force)
{
	gB_GrabbingPostFrames[client][index] = false;
	
	if(force)
	{
		delete gH_PostFramesTimer[client][index];		
	}

	DoReplaySaverCallbacks(info.iSteamID, client, info.style, info.time, info.jumps, info.strafes, info.sync, info.track, info.oldtime, info.perfs, info.avgvel, info.maxvel, info.timestamp, info.fZoneOffset, info.stage);
}

float ExistingWrReplayLength(int style, int track, int stage)
{
	if (gB_ReplayPlayback)
	{
		return Shavit_GetReplayLength(style, track, stage);
	}

	char sPath[PLATFORM_MAX_PATH];
	Shavit_GetReplayFilePath(style, track, stage, gS_Map, gS_ReplayFolder, sPath);

	replay_header_t header;
	File f = ReadReplayHeader(sPath, header, style, track);

	if (f != null)
	{
		delete f;
		return header.fTime;
	}

	return 0.0;
}

void DoReplaySaverCallbacks(int iSteamID, int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, float fZoneOffset[2], int stage = 0)
{
	gA_PlayerFrames[client].Resize(gI_PlayerFrames[client]);

	bool bShouldEdit = (stage > 1 && !Shavit_IsOnlyStageMode(client));
	float fReplayTime = bShouldEdit ? time : float(gI_PlayerFrames[client]) / gF_Tickrate;

	bool isTooLong = (gCV_TimeLimit.FloatValue > 0.0 && fReplayTime > gCV_TimeLimit.FloatValue);

	float length = ExistingWrReplayLength(style, track, stage);
	bool isBestReplay = (length == 0.0 || time < length);

	Action action = Plugin_Continue;
	Call_StartForward(gH_ShouldSaveReplayCopy);
	Call_PushCell(client);
	Call_PushCell(style);
	Call_PushCell(time);
	Call_PushCell(jumps);
	Call_PushCell(strafes);
	Call_PushCell(sync);
	Call_PushCell(track);
	Call_PushCell(stage);
	Call_PushCell(oldtime);
	Call_PushCell(perfs);
	Call_PushCell(avgvel);
	Call_PushCell(maxvel);
	Call_PushCell(timestamp);
	Call_PushCell(isBestReplay);
	Call_PushCell(isTooLong);
	Call_Finish(action);

	bool makeCopy = (action != Plugin_Continue);
	bool makeReplay = (isBestReplay && !isTooLong);

	if (!makeCopy && !makeReplay)
	{
		return;
	}

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));
	ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");

	int postframes = gI_PlayerFrames[client] - gI_PlayerFinishFrame[client];

	char sPath[PLATFORM_MAX_PATH];
	bool saved;

	ArrayList aSaveFrames = null;
	ArrayList aFrameOffsets = null;
	int iPreFrames;
	int iStartFrame;
	int iEndFrame;
	int iFrameCount;

	if (bShouldEdit) // need edit replay
	{
		ArrayList aOriginalFrames = view_as<ArrayList>(CloneHandle(gA_PlayerFrames[client]));
		aFrameOffsets = new ArrayList();

		iPreFrames = CaculateStagePreFrames(client, gI_LastPlayerStageStartFrames[client]);
		iStartFrame = gI_LastPlayerStageStartFrames[client] - iPreFrames;
		iEndFrame = gI_PlayerFrames[client];
		iFrameCount = iEndFrame - iStartFrame;
		aSaveFrames = EditReplayFrames(iStartFrame, iEndFrame, aOriginalFrames, false);
		saved = SaveReplay(style, track, stage, time, iSteamID, iPreFrames, aSaveFrames, aFrameOffsets, iFrameCount, postframes, timestamp, fZoneOffset, makeCopy, makeReplay, sPath, sizeof(sPath));
	}
	else
	{
		aSaveFrames = view_as<ArrayList>(CloneHandle(gA_PlayerFrames[client]))
		iPreFrames = gI_PlayerPrerunFrames[client];
		iFrameCount = gI_PlayerFrames[client];

		if(gB_TrimFailureFrames && track == Track_Main && stage == 0)
			aFrameOffsets = view_as<ArrayList>(CloneHandle(gA_FrameOffsets[client]));

		saved = SaveReplay(style, track, stage, time, iSteamID, iPreFrames, aSaveFrames, aFrameOffsets, iFrameCount, postframes, timestamp, fZoneOffset, makeCopy, makeReplay, sPath, sizeof(sPath));		
	}

	if (!saved)
	{
		LogError("SaveReplay() failed. Skipping OnReplaySaved")
		ClearFrames(client);
		return;
	}

	Call_StartForward(gH_OnReplaySaved);
	Call_PushCell(client);
	Call_PushCell(style);
	Call_PushCell(time);
	Call_PushCell(jumps);
	Call_PushCell(strafes);
	Call_PushCell(sync);
	Call_PushCell(track);
	Call_PushCell(stage);
	Call_PushCell(oldtime);
	Call_PushCell(perfs);
	Call_PushCell(avgvel);
	Call_PushCell(maxvel);
	Call_PushCell(timestamp);
	Call_PushCell(isBestReplay);
	Call_PushCell(isTooLong);
	Call_PushCell(makeCopy);
	Call_PushString(sPath);
	Call_PushCell(aSaveFrames);
	Call_PushCell(aFrameOffsets);
	Call_PushCell(iPreFrames);
	Call_PushCell(postframes);	
	Call_PushString(sName);
	Call_Finish();

	delete aFrameOffsets;
	delete aSaveFrames;

	if (Shavit_IsOnlyStageMode(client))
	{
		ClearFrames(client);		
	}
	else if(stage == 0)
	{
		gB_DelayClearFrame[client] = true;
		
		if (IsValidHandle(gH_ClearFramesDelay[client]))
		{
			delete gH_ClearFramesDelay[client];			
		}

		gH_ClearFramesDelay[client] = CreateTimer(gCV_ClearFrameDelay.FloatValue, Timer_ClearFrames, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, float startvel, float endvel, int timestamp)
{
	if (Shavit_IsPracticeMode(client) || !gCV_Enabled.BoolValue || (gI_PlayerFrames[client]-gI_PlayerPrerunFrames[client] <= 10))
	{
		return;
	}

	// Someone using checkpoints presumably
	if (gB_GrabbingPostFrames[client][0])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][0], 0, true);
	}

	gI_PlayerFinishFrame[client] = gI_PlayerFrames[client];

	float fZoneOffset[2];
	fZoneOffset[0] = Shavit_GetZoneOffset(client, 0);
	fZoneOffset[1] = Shavit_GetZoneOffset(client, 1);

	if (gCV_PlaybackPostRunTime.FloatValue > 0.0)
	{
		finished_run_info info;
		info.iSteamID = GetSteamAccountID(client);
		info.style = style;
		info.time = time;
		info.jumps = jumps;
		info.strafes = strafes;
		info.sync = sync;
		info.track = track;
		info.stage = 0;
		info.oldtime = oldtime;
		info.perfs = perfs;
		info.avgvel = avgvel;
		info.maxvel = maxvel;
		info.timestamp = timestamp;
		info.fZoneOffset = fZoneOffset;

		gA_FinishedRunInfo[client][0] = info;
		gB_GrabbingPostFrames[client][0] = true;
		
		if(gH_PostFramesTimer[client][0] != null)
		{
			delete gH_PostFramesTimer[client][0];			
		}

		gH_PostFramesTimer[client][0] = CreateTimer(gCV_PlaybackPostRunTime.FloatValue, Timer_PostFrames, client, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		DoReplaySaverCallbacks(GetSteamAccountID(client), client, style, time, jumps, strafes, sync, track, oldtime, perfs, avgvel, maxvel, timestamp, fZoneOffset);
	}
}

public void Shavit_OnFinishStage(int client, int track, int style, int stage, float time, float oldtime, int jumps, int strafes, float sync, float perfs, float avgvel, float maxvel, float startvel, float endvel, int timestamp)
{
	if (Shavit_IsPracticeMode(client) || !gCV_Enabled.BoolValue || (gI_PlayerFrames[client]-gI_PlayerPrerunFrames[client] <= 10))
	{
		return;
	}

	if (gB_GrabbingPostFrames[client][1])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][1], 1, true);
	}

	gI_PlayerFinishFrame[client] = gI_PlayerFrames[client];

	float fZoneOffset[2];
	fZoneOffset[0] = Shavit_GetZoneOffset(client, 0);
	fZoneOffset[1] = Shavit_GetZoneOffset(client, 1);

	if (gCV_PlaybackPostRunTime.FloatValue > 0.0 && !Shavit_IsOnlyStageMode(client))
	{
		finished_run_info info;
		info.iSteamID = GetSteamAccountID(client);
		info.style = style;
		info.time = time;
		info.jumps = jumps;
		info.strafes = strafes;
		info.sync = sync;
		info.track = track;
		info.stage = stage;
		info.oldtime = oldtime;
		info.perfs = perfs;
		info.avgvel = avgvel;
		info.maxvel = maxvel;
		info.timestamp = timestamp;
		info.fZoneOffset = fZoneOffset;

		gA_FinishedRunInfo[client][1] = info;
		gB_GrabbingPostFrames[client][1] = true;

		if(gH_PostFramesTimer[client][1] != null)
		{
			delete gH_PostFramesTimer[client][1];			
		}

		delete gH_PostFramesTimer[client][1];

		gH_PostFramesTimer[client][1] = CreateTimer(gCV_PlaybackPostRunTime.FloatValue, Timer_StagePostFrames, client, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		DoReplaySaverCallbacks(GetSteamAccountID(client), client, style, time, jumps, strafes, sync, track, oldtime, perfs, avgvel, maxvel, timestamp, fZoneOffset, stage);
	}
}

bool SaveReplay(int style, int track, int stage, float time, int steamid, int preframes, ArrayList playerrecording, ArrayList frameoffsets, int iSize, int postframes, int timestamp, float fZoneOffset[2], bool saveCopy, bool saveWR, char[] sPath, int sPathLen)
{
	char sTrack[8];
	FormatEx(sTrack, 8, "_%d", track);

	char sStage[8];
	FormatEx(sStage, 8, "_s%d", stage);

	File fWR = null;
	File fCopy = null;

	if (saveWR)
	{
		FormatEx(sPath, sPathLen, "%s/%d/%s%s%s.replay", gS_ReplayFolder, style, gS_Map, (track > 0)? sTrack:"", (stage > 0)? sStage:"");

		if (!(fWR = OpenFile(sPath, "wb+")))
		{
			LogError("Failed to open WR replay file for writing. ('%s')", sPath);
		}
	}

	if (saveCopy)
	{
		FormatEx(sPath, sPathLen, "%s/copy/%d_%d_%s.replay", gS_ReplayFolder, timestamp, steamid, gS_Map);
	
		if (!(fCopy = OpenFile(sPath, "wb+")))
		{
			LogError("Failed to open 'copy' replay file for writing. ('%s')", sPath);
		}
	}

	if (!fWR && !fCopy)
	{
		// I want to try and salvage the replay file so let's write it out to a random
		//  file and hope people read the error log to figure out what happened...
		// I'm not really sure how we could reach this though as
		//  `Shavit_Replay_CreateDirectories` should have failed if it couldn't create
		//  a test file.
		FormatEx(sPath, sPathLen, "%s/%d_%d_%s%s.replay", gS_ReplayFolder, style, GetURandomInt() % 99, gS_Map, (track > 0)? sTrack:"");

		if (!(fWR = OpenFile(sPath, "wb+")))
		{
			LogError("Couldn't open a WR, 'copy', or 'salvage' replay file....");
			return false;
		}

		LogError("Couldn't open a WR or 'copy' replay file. Writing 'salvage' replay @ (style %d) '%s'", style, sPath);
	}

	if (fWR)
	{
		WriteReplayHeader(fWR, style, track, stage, time, steamid, preframes, postframes, fZoneOffset, iSize, gF_Tickrate, gS_Map, frameoffsets);
	}

	if (fCopy)
	{
		WriteReplayHeader(fCopy, style, track, stage, time, steamid, preframes, postframes, fZoneOffset, iSize, gF_Tickrate, gS_Map, frameoffsets);
	}

	WriteReplayFrames(playerrecording, iSize, fWR, fCopy);

	delete fWR;
	delete fCopy;
	return true;
}

public ArrayList EditReplayFrames(int start, int end, ArrayList frames, bool preserve)
{
	ArrayList copy = new ArrayList(0x09, 0);
	int iFrameCount = end - start;
	int iTicks;
	frame_t aFrame;	

	copy.Resize(iFrameCount);

	for(int i = 0; i < iFrameCount; i++)
	{
		iTicks = start + i;

		if(iTicks >= end)
		{
			break;
		}

		frames.GetArray(iTicks, aFrame, sizeof(frame_t));
		copy.SetArray(i, aFrame, sizeof(frame_t));
	}

	if(!preserve)
	{
		delete frames;
	}

	return copy;
}

public int CaculateStagePreFrames(int client, int start)
{
	int iMaxPreFrames = RoundToFloor(gCV_PlaybackPreRunTime.FloatValue * (1.0 / GetTickInterval()));

	if (iMaxPreFrames > gI_PlayerFrames[client])
	{
		return gI_PlayerFrames[client];
	}

	int iStartFrame = start - iMaxPreFrames;

	if(iStartFrame <= 0)
	{
		return start;
	}

	if(iStartFrame < gI_LastStageReachFrame[client])
	{
		return start - gI_LastStageReachFrame[client];
	}

	return iMaxPreFrames;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	gI_AFKTickCount[client] = 0;

	return Plugin_Continue;
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style, int mouse[2])
{
	if (IsFakeClient(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	if(status != Timer_Running)
	{
		gI_AFKTickCount[client] = 0;
		return Plugin_Continue;
	}

	int iOldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");

	if (iOldButtons != buttons)
	{
		gI_AFKTickCount[client] = 0;
	}

	gI_AFKTickCount[client]++;

	return Plugin_Continue;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (IsFakeClient(client) || !IsPlayerAlive(client))
	{
		return;
	}

	if (!gA_PlayerFrames[client] || !gB_RecordingEnabled[client])
	{
		return;
	}

	if (!gB_GrabbingPostFrames[client][0] && !(Shavit_ReplayEnabledStyle(Shavit_GetBhopStyle(client)) && Shavit_GetTimerStatus(client) == Timer_Running))
	{
		return;
	}

	if ((gI_PlayerFrames[client] / gF_Tickrate) > gCV_TimeLimit.FloatValue)
	{
		if (gI_HijackFrames[client])
		{
			gI_HijackFrames[client] = 0;
		}

		return;
	}

	if (!Shavit_ShouldProcessFrame(client))
	{
		return;
	}

	if (gA_PlayerFrames[client].Length <= gI_PlayerFrames[client])
	{
		// Add about two seconds worth of frames so we don't have to resize so often
		gA_PlayerFrames[client].Resize(gI_PlayerFrames[client] + (RoundToCeil(gF_Tickrate) * 2));
	}

	frame_t aFrame;
	GetClientAbsOrigin(client, aFrame.pos);

	if (!gI_HijackFrames[client])
	{
		float vecEyes[3];
		GetClientEyeAngles(client, vecEyes);
		aFrame.ang[0] = vecEyes[0];
		aFrame.ang[1] = vecEyes[1];
	}
	else
	{
		aFrame.ang = gF_HijackedAngles[client];
		--gI_HijackFrames[client];
	}

	aFrame.buttons = buttons;
	aFrame.flags = GetEntityFlags(client);
	aFrame.mt = GetEntityMoveType(client);

	aFrame.mousexy = (mouse[0] & 0xFFFF) | ((mouse[1] & 0xFFFF) << 16);
	aFrame.vel = LimitMoveVelFloat(vel[0]) | (LimitMoveVelFloat(vel[1]) << 16);

	aFrame.stage = Shavit_GetClientLastStage(client);

	gA_PlayerFrames[client].SetArray(gI_PlayerFrames[client]++, aFrame, sizeof(frame_t));
	gI_RealFrameCount[client]++;
}

stock int LimitMoveVelFloat(float vel)
{
	int x = RoundToCeil(vel);
	return ((x < -666) ? -666 : ((x > 666) ? 666 : x)) & 0xFFFF;
}

public int Native_GetClientFrameCount(Handle handler, int numParams)
{
	return gI_PlayerFrames[GetNativeCell(1)];
}

public int Native_GetPlayerPreFrames(Handle handler, int numParams)
{
	return gI_PlayerPrerunFrames[GetNativeCell(1)];
}

public int Native_GetStageStartFrames(Handle handler, int numParams)
{
	return gI_PlayerStageStartFrames[GetNativeCell(1)];
}

public int Native_GetStageReachFrames(Handle handler, int numParams)
{
	return gI_StageReachFrame[GetNativeCell(1)];
}

public int Native_SetPlayerPreFrames(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int preframes = GetNativeCell(2);

	gI_PlayerPrerunFrames[client] = preframes;
	return 1;
}

public int Native_SetStageStartFrames(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int frames = GetNativeCell(2);

	gI_PlayerStageStartFrames[client] = frames;
	return 1;
}

public int Native_SetStageReachFrames(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int frames = GetNativeCell(2);

	gI_StageReachFrame[client] = frames;
	return 1;
}

public int Native_SetPlayerFrameOffsets(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	ArrayList data = view_as<ArrayList>(GetNativeCell(2));
	bool cheapCloneHandle = view_as<bool>(GetNativeCell(3));

	if (cheapCloneHandle)
	{
		data = view_as<ArrayList>(CloneHandle(data));
	}
	else
	{
		data = data.Clone();
	}

	delete gA_FrameOffsets[client];
	gA_FrameOffsets[client] = data;

	if(gB_TrimFailureFrames)
	{
		offset_info_t offset;
		gA_FrameOffsets[client].GetArray(0, offset, sizeof(offset_info_t));
		gI_RealFrameCount[client] = offset.iFrameOffset;		
	}
	else
	{
		gI_RealFrameCount[client] = gI_PlayerFrames[client];
	}

	return 1;
}

public int Native_GetPlayerFrameOffsets(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool cheapCloneHandle = view_as<bool>(GetNativeCell(2));
	Handle cloned = null;

	if(gA_FrameOffsets[client] != null)
	{
		offset_info_t offset;
		offset.iFrameOffset = gI_RealFrameCount[client];
		gA_FrameOffsets[client].SetArray(0, offset, sizeof(offset_info_t));

		ArrayList offsets = cheapCloneHandle ? gA_FrameOffsets[client] : gA_FrameOffsets[client].Clone();
		cloned = CloneHandle(offsets, plugin); // set the calling plugin as the handle owner

		if (!cheapCloneHandle)
		{
			// Only hit for .Clone()'d handles. .Clone() != CloneHandle()
			CloseHandle(offsets);
		}
	}

	return view_as<int>(cloned);
}

public int Native_GetReplayData(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool cheapCloneHandle = view_as<bool>(GetNativeCell(2));
	Handle cloned = null;

	if(gA_PlayerFrames[client] != null)
	{
		ArrayList frames = cheapCloneHandle ? gA_PlayerFrames[client] : gA_PlayerFrames[client].Clone();
		frames.Resize(gI_PlayerFrames[client]);
		cloned = CloneHandle(frames, plugin); // set the calling plugin as the handle owner

		if (!cheapCloneHandle)
		{
			// Only hit for .Clone()'d handles. .Clone() != CloneHandle()
			CloseHandle(frames);
		}
	}

	return view_as<int>(cloned);
}

public int Native_SetReplayData(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	ArrayList data = view_as<ArrayList>(GetNativeCell(2));
	bool cheapCloneHandle = view_as<bool>(GetNativeCell(3));

	if (gB_GrabbingPostFrames[client][1])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][1], 1, true);
	}

	if (gB_GrabbingPostFrames[client][0])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client][0], 0, true);
	}

	gB_RecordingEnabled[client] = true;

	if (cheapCloneHandle)
	{
		data = view_as<ArrayList>(CloneHandle(data));
	}
	else
	{
		data = data.Clone();
	}

	delete gA_PlayerFrames[client];
	gA_PlayerFrames[client] = data;
	gI_PlayerFrames[client] = data.Length;
	return 1;
}

public int Native_HijackAngles(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	gF_HijackedAngles[client][0] = view_as<float>(GetNativeCell(2));
	gF_HijackedAngles[client][1] = view_as<float>(GetNativeCell(3));

	int ticks = GetNativeCell(4);

	if (ticks == -1)
	{
		float latency = GetClientLatency(client, NetFlow_Both);

		if (latency > 0.0)
		{
			ticks = RoundToCeil(latency / GetTickInterval()) + 1;
			gI_HijackFrames[client] = ticks;
		}
	}
	else
	{
		gI_HijackFrames[client] = ticks;
	}

	gB_HijackFramesKeepOnStart[client] = (numParams < 5) ? false : view_as<bool>(GetNativeCell(5));
	return ticks;
}

public int Native_EditReplayFrames(Handle handler, int numParams)
{
	return view_as<int>(EditReplayFrames(GetNativeCell(1), GetNativeCell(2), view_as<ArrayList>(GetNativeCell(3)), numParams > 3 ? true:GetNativeCell(4)));
}
