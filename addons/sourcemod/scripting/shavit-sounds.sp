/*
 * shavit's Timer - Sounds
 * by: shavit, KiD Fearless
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
#include <dhooks>
#include <clientprefs>

#include <shavit/core>
#include <shavit/wr>

#undef REQUIRE_PLUGIN
#include <shavit/hud>

#pragma newdecls required
#pragma semicolon 1

#define SND_NONE                	0
#define SND_FIRSTCOMPLETION         (1 << 0) // First completion
#define SND_TRACKWORLDRECORD        (1 << 1) // NEW WR
#define SND_STAGEWORLDRECORD       	(1 << 2) // NEW WRCP
#define SND_PERSONALBEST    		(1 << 3) // NEW PB
#define SND_NOIMPROVEMENT          	(1 << 4) // WORSE OR PRACTICE
#define SND_CHECKPOINT_WR         	(1 << 5) // Checkpoint compares to wr
#define SND_CHECKPOINT_PB        	(1 << 6) // Checkpoint compares to pb
#define SND_COMPLETIONANNOUNCE 		(1 << 7) // Completions from other players
#define SND_TIMERSTART				(1 << 8) // Timer start


#define SND_DEFAULT (SND_FIRSTCOMPLETION|SND_TRACKWORLDRECORD|SND_STAGEWORLDRECORD|SND_PERSONALBEST|SND_NOIMPROVEMENT|SND_CHECKPOINT_WR|SND_COMPLETIONANNOUNCE)

bool gB_Late = false;

ArrayList gA_FirstSounds = null;
ArrayList gA_PersonalSounds = null;
ArrayList gA_WorldSounds = null;
ArrayList gA_WRCPSounds = null;
ArrayList gA_WorstSounds = null;
ArrayList gA_NoImprovementSounds = null;
ArrayList gA_CPTimeAhead = null;
ArrayList gA_CPTimeBehind = null;
ArrayList gA_TimerStart = null;
StringMap gSM_RankSounds = null;

int gI_SoundSettings[MAXPLAYERS + 1];
Handle gH_SoundCookie = null;

// cvars
Convar gCV_MinimumWorst = null;
Convar gCV_Enabled = null;

Handle gH_OnPlaySound = null;

public Plugin myinfo =
{
	name = "[shavit-surf] Sounds",
	author = "shavit, KiD Fearless, *Surf integration version modified by KikI",
	description = "Play custom sounds when timer-related events happen for shavit surf timer.  (This plugin is base on shavit's bhop timer)",
	version = SHAVIT_SURF_VERSION,
	url = "https://github.com/shavitush/bhoptimer  https://github.com/bhopppp/Shavit-Surf-Timer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-sounds");
	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-sounds.phrases");

	// cache
	int cells = ByteCountToCells(PLATFORM_MAX_PATH);
	gA_FirstSounds = new ArrayList(cells);
	gA_PersonalSounds = new ArrayList(cells);
	gA_WorldSounds = new ArrayList(cells);
	gA_WRCPSounds = new ArrayList(cells);
	gA_WorstSounds = new ArrayList(cells);
	gA_NoImprovementSounds = new ArrayList(cells);
	gA_CPTimeAhead = new ArrayList(cells);
	gA_CPTimeBehind = new ArrayList(cells);
	gA_TimerStart = new ArrayList(cells);
	gSM_RankSounds = new StringMap();

	gH_SoundCookie = RegClientCookie("shavit_sound", "Sound setting cookie", CookieAccess_Protected);

	RegConsoleCmd("sm_tsnd", Command_Sound, "Open sound setting menu.");
	RegConsoleCmd("sm_timersound", Command_Sound, "Open sound setting menu.");

	// cvars
	gCV_MinimumWorst = new Convar("shavit_sounds_minimumworst", "10", "Minimum amount of records to be saved for a \"worst\" sound to play.", 0, true, 1.0);
	gCV_Enabled = new Convar("shavit_sounds_enabled", "1", "Enables/Disables functionality of the plugin", 0, true, 0.0, true, 1.0);

	Convar.AutoExecConfig();

	gH_OnPlaySound = CreateGlobalForward("Shavit_OnPlaySound", ET_Event, Param_Cell, Param_String, Param_Cell, Param_Array, Param_CellByRef);

	if (gB_Late)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i))
			{
				continue;
			}

			OnClientPutInServer(i);
		}
	}
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client) || !IsClientInGame(client))
	{
		return;
	}

	char sSoundSettings[12];
	GetClientCookie(client, gH_SoundCookie, sSoundSettings, sizeof(sSoundSettings));

	if(strlen(sSoundSettings) == 0)
	{
		IntToString(SND_DEFAULT, sSoundSettings, sizeof(sSoundSettings));
		SetClientCookie(client, gH_SoundCookie, sSoundSettings);
	}

	gI_SoundSettings[client] = StringToInt(sSoundSettings);
}

public void OnClientPutInServer(int client)
{
	if(AreClientCookiesCached(client))
	{
		OnClientCookiesCached(client);
	}
}

public void OnMapStart()
{
	gA_FirstSounds.Clear();
	gA_PersonalSounds.Clear();
	gA_WorldSounds.Clear();
	gA_WRCPSounds.Clear();
	gA_WorstSounds.Clear();
	gA_NoImprovementSounds.Clear();
	gA_CPTimeAhead.Clear();
	gA_CPTimeBehind.Clear();
	gA_TimerStart.Clear();
	gSM_RankSounds.Clear();

	char sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-sounds.cfg");

	File fFile = OpenFile(sFile, "r"); // readonly, unless i implement in-game editing

	if(fFile == null && gCV_Enabled.BoolValue)
	{
		SetFailState("Cannot open \"configs/shavit-sounds.cfg\". Make sure this file exists and that the server has read permissions to it.");
	}
	else
	{
		char sLine[PLATFORM_MAX_PATH*2];
		char sDownloadString[PLATFORM_MAX_PATH];

		while(fFile.ReadLine(sLine, PLATFORM_MAX_PATH*2))
		{
			TrimString(sLine);

			if(sLine[0] != '\"')
			{
				continue;
			}

			ReplaceString(sLine, PLATFORM_MAX_PATH*2, "\"", "");

			char sExploded[2][PLATFORM_MAX_PATH];
			ExplodeString(sLine, " ", sExploded, 2, PLATFORM_MAX_PATH);

			if(StrEqual(sExploded[0], "first"))
			{
				gA_FirstSounds.PushString(sExploded[1]);
			}
			else if(StrEqual(sExploded[0], "personal"))
			{
				gA_PersonalSounds.PushString(sExploded[1]);
			}
			else if(StrEqual(sExploded[0], "world"))
			{
				gA_WorldSounds.PushString(sExploded[1]);
			}
			else if(StrEqual(sExploded[0], "wrcp"))
			{
				gA_WRCPSounds.PushString(sExploded[1]);
			}
			else if(StrEqual(sExploded[0], "worst"))
			{
				gA_WorstSounds.PushString(sExploded[1]);
			}
			else if(StrEqual(sExploded[0], "cpahead"))
			{
				gA_CPTimeAhead.PushString(sExploded[1]);
			}
			else if(StrEqual(sExploded[0], "cpbehind"))
			{
				gA_CPTimeBehind.PushString(sExploded[1]);
			}
			else if(StrEqual(sExploded[0], "timerstart"))
			{
				gA_TimerStart.PushString(sExploded[1]);
			}
			else if(StrEqual(sExploded[0], "worse") || StrEqual(sExploded[0], "noimprovement"))
			{
				gA_NoImprovementSounds.PushString(sExploded[1]);
			}
			else
			{
				gSM_RankSounds.SetString(sExploded[0], sExploded[1]);
			}

			if(PrecacheSound(sExploded[1], true))
			{
				FormatEx(sDownloadString, PLATFORM_MAX_PATH, "sound/%s", sExploded[1]);
				AddFileToDownloadsTable(sDownloadString);
			}
			else
			{
				LogError("\"sound/%s\" could not be accessed.", sExploded[1]);
			}
		}
	}

	delete fFile;
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs)
{
	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	if(Shavit_IsPracticeMode(client) || (oldtime != 0.0 && time >= oldtime && gA_NoImprovementSounds.Length != 0))
	{
		char sSound[PLATFORM_MAX_PATH];
		gA_NoImprovementSounds.GetString(GetRandomInt(0, gA_NoImprovementSounds.Length - 1), sSound, PLATFORM_MAX_PATH);

		PlayEventSound(client, false, sSound, SND_NOIMPROVEMENT);
	}
}

public void Shavit_OnFinish_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int track, float fOldTime)
{
	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	char sSound[PLATFORM_MAX_PATH];
	bool bEveryone = false;

	char sRank[8];
	IntToString(rank, sRank, 8);

	int event;

	if((time < fOldTime || fOldTime == 0.0) && gSM_RankSounds.GetString(sRank, sSound, PLATFORM_MAX_PATH))
	{
		event = SND_FIRSTCOMPLETION;
		bEveryone = true;
	}
	else if(gA_WorldSounds.Length != 0 && rank == 1)
	{
		event = SND_TRACKWORLDRECORD;
		bEveryone = true;

		gA_WorldSounds.GetString(GetRandomInt(0, gA_WorldSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
	}
	else if(gA_PersonalSounds.Length != 0 && time < fOldTime)
	{
		event = SND_PERSONALBEST;
		gA_PersonalSounds.GetString(GetRandomInt(0, gA_PersonalSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
	}
	else if(gA_FirstSounds.Length != 0 && overwrite == 1)
	{
		event = SND_FIRSTCOMPLETION;
		gA_FirstSounds.GetString(GetRandomInt(0, gA_FirstSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
	}

	if(StrContains(sSound, ".") != -1) // file has an extension?
	{
		PlayEventSound(client, bEveryone, sSound, event);
	}
}

public void Shavit_OnFinishStage(int client, int track, int style, int stage, float time, float oldtime, int jumps, int strafes, float sync, float perfs)
{
	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	if(!Shavit_IsOnlyStageMode(client))
	{
		return;
	}

	if(Shavit_IsPracticeMode(client) || (oldtime != 0.0 && time >= oldtime && gA_NoImprovementSounds.Length != 0))
	{
		char sSound[PLATFORM_MAX_PATH];
		gA_NoImprovementSounds.GetString(GetRandomInt(0, gA_NoImprovementSounds.Length - 1), sSound, PLATFORM_MAX_PATH);

		PlayEventSound(client, false, sSound, SND_NOIMPROVEMENT);
	}
}

public void Shavit_OnFinishStage_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int stage, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	char sSound[PLATFORM_MAX_PATH];
	bool bEveryone = false;
	int event;

	char sRank[8];
	IntToString(rank, sRank, 8);

	if((time < oldtime || oldtime == 0.0) && gSM_RankSounds.GetString(sRank, sSound, PLATFORM_MAX_PATH))
	{
		event = SND_COMPLETIONANNOUNCE;
		bEveryone = true;
	}
	else if(gA_WRCPSounds.Length != 0 && rank == 1)
	{
		event = SND_STAGEWORLDRECORD;
		bEveryone = true;

		gA_WRCPSounds.GetString(GetRandomInt(0, gA_WRCPSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
	}
	else if(gA_PersonalSounds.Length != 0 && time < oldtime)
	{
		event = SND_PERSONALBEST;
		gA_PersonalSounds.GetString(GetRandomInt(0, gA_PersonalSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
	}
	else if(gA_FirstSounds.Length != 0 && overwrite == 1)
	{
		event = SND_FIRSTCOMPLETION;
		gA_FirstSounds.GetString(GetRandomInt(0, gA_FirstSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
	}

	if(StrContains(sSound, ".") != -1) // file has an extension?
	{
		PlayEventSound(client, bEveryone, sSound, event);
	}
}

public void Shavit_OnReachNextCP(int client, int track, int checkpoint, float time)
{
	int style = Shavit_GetBhopStyle(client);
	float fCPWR = Shavit_GetStageCPWR(track, style, checkpoint);
	float fCPPB = Shavit_GetStageCPPB(client, track, style, checkpoint);
	char sSound[PLATFORM_MAX_PATH];

	if (fCPWR == 0.0) 
	{
		gA_CPTimeAhead.GetString(GetRandomInt(0, gA_CPTimeAhead.Length - 1), sSound, PLATFORM_MAX_PATH);
	}
	else
	{
		float fDifference; float fComparison;
		if ((gI_SoundSettings[client] & SND_CHECKPOINT_WR) > 0)
			fComparison = fCPWR;
		else
			fComparison = fCPPB;

		fDifference = time - fComparison;

		if (fDifference > 0.0 && (fComparison > 0.0))
		{
			gA_CPTimeBehind.GetString(GetRandomInt(0, gA_CPTimeBehind.Length - 1), sSound, PLATFORM_MAX_PATH);
		}
		else
		{
			gA_CPTimeAhead.GetString(GetRandomInt(0, gA_CPTimeAhead.Length - 1), sSound, PLATFORM_MAX_PATH);
		}
	}

	if(StrContains(sSound, ".") != -1) // file has an extension?
	{
		PlayEventSound(client, false, sSound, (SND_CHECKPOINT_PB|SND_CHECKPOINT_WR));
	}
}

public void Shavit_OnWorstRecord(int client, int style, float time, int jumps, int strafes, float sync, int track)
{
	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	if(gA_WorstSounds.Length != 0 && Shavit_GetRecordAmount(style, track) >= gCV_MinimumWorst.IntValue)
	{
		char sSound[PLATFORM_MAX_PATH];
		gA_WorstSounds.GetString(GetRandomInt(0, gA_WorstSounds.Length - 1), sSound, PLATFORM_MAX_PATH);

		if(StrContains(sSound, ".") != -1)
		{
			PlayEventSound(client, false, sSound, SND_COMPLETIONANNOUNCE);
		}
	}
}

public void Shavit_OnStarted(int client, int track, int stage, int style, bool bMainStageTimer)
{
	if(!bMainStageTimer)
	{
		char sSound[PLATFORM_MAX_PATH];
		gA_TimerStart.GetString(GetRandomInt(0, gA_TimerStart.Length - 1), sSound, PLATFORM_MAX_PATH);

		if(StrContains(sSound, ".") != -1)
		{
			PlayEventSound(client, false, sSound, SND_TIMERSTART);
		}
	}
}

void PlayEventSound(int client, bool everyone, char sound[PLATFORM_MAX_PATH], int event)
{
	int clients[MAXPLAYERS+1];
	int count = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i))
		{
			continue;
		}

		if ((gI_SoundSettings[i] & event) == 0)
		{
			if (!(i == client && event == SND_COMPLETIONANNOUNCE && (gI_SoundSettings[i] & SND_PERSONALBEST) > 0))
			{
				continue;
			}
		}

		if (everyone || i == client || GetSpectatorTarget(i) == client)
		{
			clients[count++] = i;
		}
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_OnPlaySound);
	Call_PushCell(client);
	Call_PushStringEx(sound, PLATFORM_MAX_PATH, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(PLATFORM_MAX_PATH);
	Call_PushArrayEx(clients, MaxClients, SM_PARAM_COPYBACK);
	Call_PushCellRef(count);
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}

	if(count > 0)
	{
		EmitSound(clients, count, sound);
	}
}

public void Shavit_OnTimerMenuMade(int client, Menu menu)
{
	char sMenu[32];
	FormatEx(sMenu, 32, "%T", "SoundOptions", client);
	menu.AddItem("snd", sMenu);
}

public Action Shavit_OnTimerMenuSelect(int client, int position, char[] info, int maxlength)
{
	if(StrEqual(info, "snd"))
	{
		ShowSoundSettingMenu(client, 0);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Command_Sound(int client, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	ShowSoundSettingMenu(client, 0);

	return Plugin_Handled;
}

public void ShowSoundSettingMenu(int client, int item)
{
	Menu menu = new Menu(MenuHandler_SoundSetting, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);

	SetMenuTitle(menu, "%T\n ", "SoundMenuTitle", client);

	char sInfo[16];
	char sItem[64];

	FormatEx(sInfo, 16, "%d", SND_FIRSTCOMPLETION);
	FormatEx(sItem, 64, "%T", "SndFirstCompletion", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", SND_TRACKWORLDRECORD);
	FormatEx(sItem, 64, "%T", "SndTrackRecord", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", SND_STAGEWORLDRECORD);
	FormatEx(sItem, 64, "%T", "SndStageRecord", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", SND_PERSONALBEST);
	FormatEx(sItem, 64, "%T", "SndPersonalBest", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", SND_NOIMPROVEMENT);
	FormatEx(sItem, 64, "%T", "SndNoImprovement", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "#%d", SND_CHECKPOINT_WR);
	FormatEx(sItem, 64, "%T", "SndCheckpoint", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", SND_COMPLETIONANNOUNCE);
	FormatEx(sItem, 64, "%T", "SndOtherCompletions", client);
	menu.AddItem(sInfo, sItem);

	FormatEx(sInfo, 16, "%d", SND_TIMERSTART);
	FormatEx(sItem, 64, "%s", "SndTimerStart", client);
	menu.AddItem(sInfo, sItem);
	
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int MenuHandler_SoundSetting(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sCookie[16];
		menu.GetItem(param2, sCookie, 16);

		int iSelection;

		if (StrContains(sCookie, "#") != -1)
		{
			ReplaceString(sCookie, 16, "#", "");
			iSelection = StringToInt(sCookie);

			int mask = (iSelection | (iSelection << 1));

			if (!(gI_SoundSettings[param1] & mask))
			{
				gI_SoundSettings[param1] |= iSelection;
			}
			else if (gI_SoundSettings[param1] & iSelection)
			{
				gI_SoundSettings[param1] ^= mask;
			}
			else
			{
				gI_SoundSettings[param1] &= ~mask;
			}

			IntToString(gI_SoundSettings[param1], sCookie, 16);
			SetClientCookie(param1, gH_SoundCookie, sCookie);
		}
		else
		{
			iSelection = StringToInt(sCookie);
			gI_SoundSettings[param1] ^= iSelection;
			IntToString(gI_SoundSettings[param1], sCookie, 16);
			SetClientCookie(param1, gH_SoundCookie, sCookie);
		}

		ShowSoundSettingMenu(param1, GetMenuSelectionPosition());
	}
	else if(action == MenuAction_DisplayItem)
	{
		char sInfo[16];
		char sDisplay[64];
		int style = 0;

		menu.GetItem(param2, sInfo, 16, style, sDisplay, 64);
		int iSelection;

		if (StrContains(sInfo, "#") != -1) // special trinary ones :)
		{
			ReplaceString(sInfo, 16, "#", "");
			iSelection = StringToInt(sInfo);

			bool first = 0 != (gI_SoundSettings[param1] & iSelection);
			bool second = 0 != (gI_SoundSettings[param1] & (iSelection << 1));
			Format(sDisplay, 64, "[%s] %s", first ? "１" : (second ? "２" : "０"), sDisplay);
		}
		else
		{
			iSelection = StringToInt(sInfo);
			Format(sDisplay, 64, "[%T] %s", ((gI_SoundSettings[param1] & iSelection) > 0) ? "ItemEnabled":"ItemDisabled", param1, sDisplay);
		}

		return RedrawMenuItem(sDisplay);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}