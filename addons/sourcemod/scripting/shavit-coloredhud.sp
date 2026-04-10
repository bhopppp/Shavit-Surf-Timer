#include <sourcemod>
#include <clientprefs>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <shavit/core>
#include <shavit/coloredhud>
#include <shavit/replay-playback>
#include <shavit/wr>
#include <shavit/zones>
#include <DynamicChannels>

#define BHOP_INTERVAL 3
#define PLAYER_MASS 1.0

#pragma newdecls required
#pragma semicolon 1

bool gB_ReplayPlayback = false;
bool gB_Zones = false;
bool gB_DynamicChannels = false;

bool gB_Late = false;

float gF_Tickrate = 0.0;
int gI_UpdateFrequency[3];

Handle gH_ElementHUDSynchronizer[MAX_ELEMENTS];

// Client Preference
bool gB_HUDEnabled[MAXPLAYERS + 1][MAX_ELEMENTS];
int gI_HUDColors[MAXPLAYERS + 1][MAX_COLORS][3];
int gI_HUDColorLogic[MAXPLAYERS + 1][MAX_ELEMENTS];
int gI_HUDDisplayLogic[MAXPLAYERS + 1][MAX_ELEMENTS];
float gF_HUDPosition[MAXPLAYERS + 1][MAX_ELEMENTS][2];
bool gB_HUDConfigChanged[MAXPLAYERS + 1];

// Client Data
float gF_Velocity[MAXPLAYERS + 1][3];
float gF_LastVelocity[MAXPLAYERS + 1][3];

float gF_Energy[MAXPLAYERS + 1][3];	// 0 - Kinetic, 2 - Potential, 3 - Initial Potential
float gF_LastEnergy[MAXPLAYERS + 1][3];

float gF_TimeDifference[MAXPLAYERS + 1];
float gF_LastTimeDifference[MAXPLAYERS + 1];

float gF_LastFinishedTime[MAXPLAYERS + 1];
int gI_LastFinishState[MAXPLAYERS + 1]; // 0 - Worse, 1 - PB, 2 - WR

float gF_VelocityDifference[MAXPLAYERS + 1];
bool gB_RecalcEnergy[MAXPLAYERS + 1];

int gI_LastEntityFlags[MAXPLAYERS + 1]; // For replay jump detection
int gI_LastTickOnGround[MAXPLAYERS + 1];
bool gB_OnGround[MAXPLAYERS + 1];

bool gB_InStartZone[MAXPLAYERS + 1];

// HUD Editing
int gI_LastEditElement[MAXPLAYERS + 1];
int gI_LastEditColorIndex[MAXPLAYERS + 1];

int gI_ColorEditCache[MAXPLAYERS + 1][3];
float gF_PositionEditCache[MAXPLAYERS + 1][2];

int gI_EditPositionAxis[MAXPLAYERS + 1];
int gI_PositonStepSize[MAXPLAYERS + 1];

int gI_LastMenuPos[MAXPLAYERS + 1];

int gI_EditPrimaryColor[MAXPLAYERS + 1];
int gI_ColorEditStepSize[MAXPLAYERS + 1];

// Element Strings
char gS_ElementColorTranslations[][64] = 
{
	"Color_Speed_Default", 
	"Color_SpeedGradient_Gain", 
	"Color_SpeedGradient_Lose", 
	"Color_SpeedDifference_Default", 
	"Color_SpeedDifference_Higher", 
	"Color_SpeedDifference_Lower",
	"Color_Energy_Default", 
	"Color_EnergyGradient_Gain", 
	"Color_EnergyGradient_Lose", 
	"Color_Energy_Higher", 
	"Color_Energy_Lower",
	"Color_Timer_Default", 
	"Color_Timer_Start", 
	"Color_Timer_Running", 
	"Color_Timer_Paused", 
	"Color_Timer_Practice",
	"Color_Timer_Finished_Worse", 	
	"Color_Timer_Finished_PB", 
	"Color_Timer_Finished_WR", 
	"Color_Timer_Stopped", 
	"Color_TimeDifference_Defualt", 
	"Color_TimeDifference_Faster", 
	"Color_TimeDifference_Slower",
	"Color_TimeDifference_Gain", 
	"Color_TimeDifference_Lose", 
};

char gS_ElementTranslations[][64] = 
{
	"Element_Speedometer", 
	"Element_SpeedDifference", 
	"Element_Energymeter", 
	"Element_Timer", 
	"Element_TimeDifference",
};

char gS_ElementEditStrings[][64] = 
{
	"Speed", "SpeedDiff", "Energy", "Timer", "TimeDiff",
};

int gI_ElementColorIndexRange[][2] = 
{
	{Color_Speed_Default, Color_SpeedGradient_Lose}, 
	{Color_SpeedDifference_Default, Color_SpeedDifference_Lower}, 
	{Color_Energy_Default, Color_Energy_Lower}, 
	{Color_Timer_Default, Color_Timer_Stopped}, 
	{Color_TimeDifference_Defualt, Color_TimeDifference_Lose},
};


public void OnPluginStart()
{
	gF_Tickrate = (1.0 / GetTickInterval());
	gI_UpdateFrequency[0] = RoundToFloor(gF_Tickrate / 33.0);	// Normal update
	gI_UpdateFrequency[1] = RoundToFloor(gF_Tickrate / 10.0);	// Low update
	gI_UpdateFrequency[2] = RoundToFloor(gF_Tickrate / 6.0);	// Super low update

	HookEventEx("player_jump", Player_Jump);
	HookEvent("player_spawn", Player_Spawn);

	RegConsoleCmd("sm_chud", Command_ColoredHUD, "Open colored HUD menu.");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/coloredhud-config");

	if(!DirExists(sPath) && !CreateDirectory(sPath, 511))
	{
		SetFailState("Failed to create folder for hud config (%s). Check file permissions", sPath);		
	}

	gB_ReplayPlayback = LibraryExists("shavit-replay-playback");
	gB_Zones = LibraryExists("shavit-zones");
	gB_DynamicChannels = LibraryExists("DynamicChannels");
	
	if (!gB_DynamicChannels)
	{
		for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
		{
			if (gH_ElementHUDSynchronizer[i] == null)
			{
				gH_ElementHUDSynchronizer[i] = CreateHudSynchronizer();
			} 
		}		
	}

	LoadDefaultHUDConfig();
	LoadTranslations("shavit-coloredhud.phrases");

	if (gB_Late)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i))
			{
				continue;
			}

			if (IsClientAuthorized(i))
			{
				OnClientAuthorized(i, "");
			}
		}
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;
	return APLRes_Success;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-replay-playback"))
	{
		gB_ReplayPlayback = true;
	}
	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}
	else if(StrEqual(name, "DynamicChannels"))
	{
		gB_DynamicChannels = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-replay-playback"))
	{
		gB_ReplayPlayback = false;
	}
	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}
	else if(StrEqual(name, "DynamicChannels"))
	{
		gB_DynamicChannels = false;
	}
}

public void OnClientPutInServer(int client)
{
	gI_LastMenuPos[client] = 0;
	gI_LastEditElement[client] = -1;
	gI_LastEditColorIndex[client] = -1;
	gI_EditPrimaryColor[client] = -1;
	gI_ColorEditStepSize[client] = 5;
	gI_EditPositionAxis[client] = -1;
	gI_PositonStepSize[client] = 10;
	gF_LastFinishedTime[client] = -1.0;
	gB_OnGround[client] = false;
	SDKHook(client, SDKHook_PostThinkPost, PostThinkPost);
}

public void OnMapEnd()
{
	FlushHUDConfigs();
}

public void OnPluginEnd()
{
	FlushHUDConfigs();
}

public void OnClientDisconnect(int client)
{
	if (gB_HUDConfigChanged[client])
	{
		SaveHUDConfig(client);
	}
}

public void OnClientAuthorized(int client, const char[] auth)
{
	LoadHUDConfig(client);		
}

public Action Command_ColoredHUD(int client, int args)
{
	OpenHUDElementMenu(client);
	return Plugin_Handled;
}


// Menus
public void OpenHUDElementMenu(int client)
{
	if (!IsClientAuthorized(client))
	{
		Shavit_PrintToChat(client, "%T", "Unauthorized", client);
		return;
	}	

	Menu menu = new Menu(MenuHandler_HUDElement);
	menu.SetTitle("%T\n ", "HUDElementMenuTitle", client);

	char sInfo[8];
	char sMenuItem[64];
	for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
	{
		IntToString(i, sInfo, 8);
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", gS_ElementTranslations[i], client);
		menu.AddItem(sInfo, sMenuItem);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_HUDElement(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		int iElement = StringToInt(sInfo);

		OpenHUDElementSettingMenu(param1, iElement);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}


public void OpenHUDElementSettingMenu(int client, int element)
{
	Menu menu = new Menu(MenuHandler_HUDElementSetting);
	menu.SetTitle("%T %T\n ", gS_ElementTranslations[element], client, "ElementSettingMenuTitle", client);

	static char sDisplayLogicTranslations[][3][64]=
	{
		{"Speed_Horizental", "Speed_Real", ""},
		{"", "", ""},
		{"", "", ""},
		{"TimeFormat_Default", "TimeFormat_FullHMS", ""},
		{"TimeDifference_Dynamic", "TimeDifference_Checkpoint_PB", "TimeDifference_Checkpoint_WR"},
	};

	char sInfo[32];
	char sMenuItem[64];
	FormatEx(sMenuItem, sizeof(sMenuItem), "[%s] %T\n ", gB_HUDEnabled[client][element] ? "✓":"　", "ElementEnabled", client);
	FormatEx(sInfo, sizeof(sInfo), "enable;%d", element);
	menu.AddItem(sInfo, sMenuItem);

	if (element == HUD_Speedometer || element == HUD_Timer || element == HUD_TimeDifference)
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "ElementDisplayLogic", client, sDisplayLogicTranslations[element][gI_HUDDisplayLogic[client][element]], client);
		FormatEx(sInfo, sizeof(sInfo), "display;%d", element);
		menu.AddItem(sInfo, sMenuItem);
	}

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "ElementColorSettings", client);
	FormatEx(sInfo, sizeof(sInfo), "color;%d", element);
	menu.AddItem(sInfo, sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "ElementPositionSettings", client);
	FormatEx(sInfo, sizeof(sInfo), "pos;%d", element);
	menu.AddItem(sInfo, sMenuItem);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_HUDElementSetting(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, 32);
		char sExploded[2][16];
		ExplodeString(sInfo, ";", sExploded, 2, 16);
		int element = StringToInt(sExploded[1]);

		if (StrEqual(sExploded[0], "enable"))
		{
			gB_HUDConfigChanged[param1] = true;
			gB_HUDEnabled[param1][element] = !gB_HUDEnabled[param1][element];
			OpenHUDElementSettingMenu(param1, element);
		}
		else if (StrEqual(sExploded[0], "display"))
		{
			gB_HUDConfigChanged[param1] = true;
			int top = (element == HUD_TimeDifference) ? 3:2;
			gI_HUDDisplayLogic[param1][element] = (gI_HUDDisplayLogic[param1][element] + 1) % top;
			OpenHUDElementSettingMenu(param1, element);
		}
		else if (StrEqual(sExploded[0], "color"))
		{
			OpenElementColorMenu(param1, element, 0);
		}
		else if (StrEqual(sExploded[0], "pos"))
		{
			gI_LastEditElement[param1] = element;
			gF_PositionEditCache[param1] = gF_HUDPosition[param1][element];
			OpenPositionSettingMenu(param1, element);
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenHUDElementMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OpenElementColorMenu(int client, int element, int item)
{
	static char sColorLogicTranslations[][3][64]=
	{
		{"ColorLogic_None", "ColorLogic_Speed_GainLose", ""},
		{"ColorLogic_None", "ColorLogic_SpeedDiffernce_HigherLower", ""},
		{"ColorLogic_None", "ColorLogic_Energy_GainLose", "ColorLogic_Energy_HigherLower"},
		{"ColorLogic_None", "ColorLogic_Timer_Status", ""},
		{"ColorLogic_None", "ColorLogic_TimeDiffernce_GainLose", "ColorLogic_TimeDiffernce_FasterSlower"},
	};

	Menu menu = new Menu(MenuHandler_ElementColor);
	menu.SetTitle("%T %T\n ", gS_ElementTranslations[element], client, "ElementColorMenuTitle", client);

	char sInfo[32];
	char sMenuItem[64];
	FormatEx(sInfo, 16, "logic;%d", element);
	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T\n ", "ElementColorLogic", client, sColorLogicTranslations[element][gI_HUDColorLogic[client][element]], client);
	menu.AddItem(sInfo, sMenuItem);

	for (int i = gI_ElementColorIndexRange[element][0]; i <= gI_ElementColorIndexRange[element][1]; i++)
	{
		FormatEx(sInfo, 8, "%d;%d", i, element);
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n RGB: {%d, %d, %d}", gS_ElementColorTranslations[i], client, gI_HUDColors[client][i][0], gI_HUDColors[client][i][1], gI_HUDColors[client][i][2]);
		menu.AddItem(sInfo, sMenuItem);
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int MenuHandler_ElementColor(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, 32);
		char sExploded[2][16];
		ExplodeString(sInfo, ";", sExploded, 2, 16);
		int element = StringToInt(sExploded[1]);
		gI_LastMenuPos[param1] = GetMenuSelectionPosition();

		if (StrEqual(sExploded[0], "logic"))
		{
			int top = (element == HUD_Energymeter || element == HUD_TimeDifference) ? 3:2;
			gI_HUDColorLogic[param1][element] = (gI_HUDColorLogic[param1][element] + 1) % top;
			gB_HUDConfigChanged[param1] = true;
			OpenElementColorMenu(param1, element, 0);
		}
		else
		{
			int iColorIndex = StringToInt(sExploded[0]);
			gI_LastEditElement[param1] = element;
			gI_ColorEditCache[param1] = gI_HUDColors[param1][iColorIndex];
			gI_LastEditColorIndex[param1] = iColorIndex;
			OpenColorSettingMenu(param1, iColorIndex);			
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		char sInfo[8];
		menu.GetItem(0, sInfo, 32);
		char sExploded[2][4];
		ExplodeString(sInfo, ";", sExploded, 2, 4);

		OpenHUDElementSettingMenu(param1, StringToInt(sExploded[1]));
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OpenColorSettingMenu(int client, int color)
{
	if (gI_EditPrimaryColor[client] == -1)
	{
		gI_EditPrimaryColor[client] = 0;
	}

	Menu menu = new Menu(MenuHandler_ColorSetting);
	menu.SetTitle("%T - %T\n ", "ColorSettingMenuTitle", client, gS_ElementTranslations[gI_LastEditElement[client]], client);

	char sMenuItem[64];
	char sInfo[16];

	char sPrimaryColor[4];
	strcopy(sPrimaryColor, 4, "RGB");

	FormatEx(sMenuItem, sizeof(sMenuItem), "[ %T ]\n(R: %d, G: %d, B: %d)\n ", gS_ElementColorTranslations[color], client, gI_ColorEditCache[client][0], gI_ColorEditCache[client][1], gI_ColorEditCache[client][2]);
	FormatEx(sInfo, 16, "color;%d", color);
	menu.AddItem(sInfo, sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", "ConfirmChange", client);
	FormatEx(sInfo, 16, "conf;%d", color);
	menu.AddItem(sInfo, sMenuItem, ColorEqual(gI_ColorEditCache[client], gI_HUDColors[client][color]) ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "ChangePrimaryColor", client);
	FormatEx(sInfo, 16, "change;%d", color);
	menu.AddItem(sInfo, sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", "ChangeStepSize", client);
	FormatEx(sInfo, 16, "step;%d", color);
	menu.AddItem(sInfo, sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%c ＋%d  (MAX: 255)", sPrimaryColor[gI_EditPrimaryColor[client]], gI_ColorEditStepSize[client]);
	FormatEx(sInfo, 16, "incr;%d", color);
	menu.AddItem(sInfo, sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%c －%d  (MIN: 255)", sPrimaryColor[gI_EditPrimaryColor[client]], gI_ColorEditStepSize[client]);
	FormatEx(sInfo, 16, "decr;%d", color);
	menu.AddItem(sInfo, sMenuItem);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ColorSetting(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int element = gI_LastEditElement[param1];
		char sInfo[32];
		char sExploded[2][16];
		menu.GetItem(param2, sInfo, 32);
		ExplodeString(sInfo, ";", sExploded, 2, 16);
		int iColorIndex = StringToInt(sExploded[1]);

		if (StrEqual(sExploded[0], "color"))
		{
			if (++iColorIndex > gI_ElementColorIndexRange[element][1])
				iColorIndex = gI_ElementColorIndexRange[element][0];
			gI_ColorEditCache[param1] = gI_HUDColors[param1][iColorIndex];
			gI_LastEditColorIndex[param1] = iColorIndex;
		}
		else if (StrEqual(sExploded[0], "conf"))
		{
			gI_HUDColors[param1][iColorIndex] = gI_ColorEditCache[param1];
			gB_HUDConfigChanged[param1] = true;
		}
		else if (StrEqual(sExploded[0], "change"))
		{
			gI_EditPrimaryColor[param1] = (gI_EditPrimaryColor[param1] + 1) % 3;
		}
		else if (StrEqual(sExploded[0], "step"))
		{
			int step = gI_ColorEditStepSize[param1] == 1 ? 4:5;
			gI_ColorEditStepSize[param1] = (gI_ColorEditStepSize[param1] + step) % 30;
			if (gI_ColorEditStepSize[param1] == 0)
			{
				gI_ColorEditStepSize[param1] = 1;
			}
		}
		else if (StrEqual(sExploded[0], "incr"))
		{
			if (gI_ColorEditCache[param1][gI_EditPrimaryColor[param1]] == 255)
			{
				gI_ColorEditCache[param1][gI_EditPrimaryColor[param1]] = 0;
			}
			else
			{
				gI_ColorEditCache[param1][gI_EditPrimaryColor[param1]] += gI_ColorEditStepSize[param1];
				if (gI_ColorEditCache[param1][gI_EditPrimaryColor[param1]] > 255)
				{
					gI_ColorEditCache[param1][gI_EditPrimaryColor[param1]] = 255;
				}				
			}
		}
		else if (StrEqual(sExploded[0], "decr"))
		{
			if (gI_ColorEditCache[param1][gI_EditPrimaryColor[param1]] == 0)
			{
				gI_ColorEditCache[param1][gI_EditPrimaryColor[param1]] = 255;
			}
			else
			{
				gI_ColorEditCache[param1][gI_EditPrimaryColor[param1]] -= gI_ColorEditStepSize[param1];
				if (gI_ColorEditCache[param1][gI_EditPrimaryColor[param1]] < 0)
				{
					gI_ColorEditCache[param1][gI_EditPrimaryColor[param1]] = 0;
				}				
			}
		}

		OpenColorSettingMenu(param1, iColorIndex);
	}
	else if(action == MenuAction_Cancel)
	{
		gI_EditPrimaryColor[param1] = -1;
		gI_LastEditColorIndex[param1] = -1;
		int element = gI_LastEditElement[param1];
		gI_LastEditElement[param1] = -1;

		if (param2 == MenuCancel_ExitBack)
		{
			OpenElementColorMenu(param1, element, gI_LastMenuPos[param1]);			
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OpenPositionSettingMenu(int client, int element)
{
	if (gI_EditPositionAxis[client] == -1)
	{
		gI_EditPositionAxis[client] = 1;
	}

	Menu menu = new Menu(MenuHandler_PositionSetting);
	menu.SetTitle("%T\n ", "ElementPositionSettingMenuTitle", client);
 	char sAxis[4];
	strcopy(sAxis, 4, "XY");

	char sInfo[16];
	char sMenuItem[64];

	FormatEx(sMenuItem, sizeof(sMenuItem), "[ %T ]\n(X: %.0f, Y: %.0f)\n ", 
	gS_ElementTranslations[element], client, gF_PositionEditCache[client][0] * 1000.0, gF_PositionEditCache[client][1] * 1000.0);
	FormatEx(sInfo, sizeof(sInfo), "ele;%d", element);
	menu.AddItem(sInfo, sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", "ConfirmChange", client);
	FormatEx(sInfo, sizeof(sInfo), "conf;%d", element);
	menu.AddItem(sInfo, sMenuItem, PosEqual(gF_PositionEditCache[client], gF_HUDPosition[client][element]) ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %c", "ChangeAxis", client, sAxis[gI_EditPositionAxis[client]]);
	FormatEx(sInfo, sizeof(sInfo), "axis;%d", element);
	menu.AddItem(sInfo, sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", "ChangeStepSize", client);
	FormatEx(sInfo, sizeof(sInfo), "step;%d", element);
	menu.AddItem(sInfo, sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%c ＋%d  (MAX: 1000)", sAxis[gI_EditPositionAxis[client]], gI_PositonStepSize[client]);
	FormatEx(sInfo, sizeof(sInfo), "plus;%d", element);
	menu.AddItem(sInfo, sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%c －%d  (MIN: 0)\n ", sAxis[gI_EditPositionAxis[client]], gI_PositonStepSize[client]);
	FormatEx(sInfo, sizeof(sInfo), "minus;%d", element);
	menu.AddItem(sInfo, sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "CenterHUDPosition", client);
	FormatEx(sInfo, sizeof(sInfo), "center;%d", element);
	menu.AddItem(sInfo, sMenuItem);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_PositionSetting(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[16];
		char sExploded[2][8];
		menu.GetItem(param2, sInfo, 16);
		ExplodeString(sInfo, ";", sExploded, 2, 8);
		int element = StringToInt(sExploded[1]);

		if (StrEqual(sExploded[0], "ele"))
		{
			element = (element + 1) % HUD_ELEMENTCOUNTS;
			gF_PositionEditCache[param1] = gF_HUDPosition[param1][element];
			gI_LastEditElement[param1] = element;
		}
		else if (StrEqual(sExploded[0], "conf"))
		{
			gF_HUDPosition[param1][element] = gF_PositionEditCache[param1];
			gB_HUDConfigChanged[param1] = true;
		}
		else if (StrEqual(sExploded[0], "axis"))
		{
			gI_EditPositionAxis[param1] = (gI_EditPositionAxis[param1] + 1) % 2;
		}
		else if (StrEqual(sExploded[0], "step"))
		{
			gI_PositonStepSize[param1] = (gI_PositonStepSize[param1] * 10) % 1000;
			if (gI_PositonStepSize[param1] == 0)
			{
				gI_PositonStepSize[param1] = 1;
			}
		}
		else if (StrEqual(sExploded[0], "plus"))
		{
			float step = float(gI_PositonStepSize[param1]) / 1000.0;
			if (gF_PositionEditCache[param1][gI_EditPositionAxis[param1]] == -1.0)
			{
				gF_PositionEditCache[param1][gI_EditPositionAxis[param1]] = 0.5;
			}
			
			gF_PositionEditCache[param1][gI_EditPositionAxis[param1]] += step;

			if (gF_PositionEditCache[param1][gI_EditPositionAxis[param1]] > 1.0)
			{
				gF_PositionEditCache[param1][gI_EditPositionAxis[param1]] = 1.0;
			}
		}
		else if (StrEqual(sExploded[0], "minus"))
		{
			float step = float(gI_PositonStepSize[param1]) / 1000.0;
			if (gF_PositionEditCache[param1][gI_EditPositionAxis[param1]] == -1.0)
			{
				gF_PositionEditCache[param1][gI_EditPositionAxis[param1]] = 0.5;
			}
			
			gF_PositionEditCache[param1][gI_EditPositionAxis[param1]] -= step;

			if (gF_PositionEditCache[param1][gI_EditPositionAxis[param1]] < 0.0)
			{
				gF_PositionEditCache[param1][gI_EditPositionAxis[param1]] = 0.0;
			}
		}
		else if (StrEqual(sExploded[0], "center"))
		{
			gF_PositionEditCache[param1][gI_EditPositionAxis[param1]] = -1.0;
		}

		OpenPositionSettingMenu(param1, element);
	}
	else if(action == MenuAction_Cancel)
	{
		gI_EditPositionAxis[param1] = -1;
		gI_LastEditElement[param1] = -1;

		if (param2 == MenuCancel_ExitBack)
		{
			char sInfo[16];
			char sExploded[2][8];
			menu.GetItem(0, sInfo, 16);
			ExplodeString(sInfo, ";", sExploded, 2, 8);
			OpenHUDElementSettingMenu(param1, StringToInt(sExploded[1]));
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}


// Hooks
public void Player_Jump(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsFakeClient(client))
	{
		return;
	}

	ProcessJump(client);
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);

	if(IsFakeClient(client))
	{
		return;
	}

	gF_Energy[client] = {0.0, 0.0, 0.0};
	gI_LastTickOnGround[client] = 0;

	gB_RecalcEnergy[client] = true;
}

public void PostThinkPost(int client)
{
	bool bReplay = (gB_ReplayPlayback && Shavit_IsReplayEntity(client));

	if (!IsValidClient(client) || (IsFakeClient(client) && !bReplay))
	{
		return;
	}

	if (bReplay && Shavit_GetReplayStatus(client) == Replay_Idle)
	{
		return;
	}

	int target = GetClientObserverTarget(client, client);

	if(bReplay)
	{
		float yawDiff;
		ProcessClientData(client, bReplay, Shavit_GetReplayButtons(target, yawDiff), Shavit_GetReplayEntityFlags(client), GetEntityMoveType(target));
	}
	else
	{
		ProcessClientData(client, bReplay, GetClientButtons(client), GetEntityFlags(client), GetEntityMoveType(client));
	}
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	int target = GetClientObserverTarget(client, client);

	UpdateClientHUD(client, target, cmdnum);
	return;
}

void ProcessClientData(int client, bool replaybot, int buttons, int flags, MoveType movetype)
{
	if (!Shavit_ShouldProcessFrame(client))
	{
		return;
	}

	bool bShouldUpdate = (GetGameTickCount() % gI_UpdateFrequency[2]) == 0;

	gF_LastVelocity[client] = gF_Velocity[client];
	gF_LastEnergy[client] = gF_Energy[client];
	if (bShouldUpdate)
	{
		gF_LastTimeDifference[client] = gF_TimeDifference[client];
	}

	int style = replaybot ? Shavit_GetReplayBotStyle(client):Shavit_GetBhopStyle(client);
	float fGravityScale = Shavit_GetStyleSettingFloat(style, "gravity");
	float origin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", origin);

	float fPotential = CaculatePotentialEnergy(origin[2], fGravityScale);

	if(flags & FL_ONGROUND)
	{
		if (++gI_LastTickOnGround[client] > BHOP_INTERVAL) // Client Grounded
		{	
			gB_OnGround[client] = true;
			gF_Energy[client][2] = fPotential;
		}
	}
	else
	{
		gI_LastTickOnGround[client] = 0;
		gB_OnGround[client] = false;
	}

	gF_VelocityDifference[client] = -1.0;
	gF_TimeDifference[client] = -1.0;

	if (replaybot)
	{
		if (!(flags & FL_ONGROUND) && (gI_LastEntityFlags[client] & FL_ONGROUND) && (buttons & IN_JUMP) > 0)
			ProcessJump(client, true);
	}
	else
	{
		float fClosestReplayLength = 0.0;
		int iTrack = Shavit_GetClientTrack(client);
		int iStage = Shavit_GetClientLastStage(client);
		int iZoneStage;
		bool bInsideStageZone = iTrack == Track_Main ? Shavit_InsideZoneStage(client, iZoneStage):false;
		gB_InStartZone[client] = gB_Zones && Shavit_InsideZone(client, Zone_Start, iTrack) || 
							(Shavit_IsOnlyStageMode(client) && bInsideStageZone && iZoneStage == iStage);

		if (!gB_InStartZone[client] && Shavit_GetTimerStatus(client) == Timer_Running)
		{
			gI_LastFinishState[client] = 0;
			gF_LastFinishedTime[client] = -1.0;
			
			bool hasFrames = Shavit_GetReplayFrameCount(Shavit_GetClosestReplayStyle(client), iTrack, Shavit_IsOnlyStageMode(client) ? iStage : 0) != 0;
			if (gB_ReplayPlayback && hasFrames)
			{
				float fClosestReplayTime = Shavit_GetClosestReplayTime(client, fClosestReplayLength);
				gF_TimeDifference[client] = Shavit_GetClientTime(client) - fClosestReplayTime;

				if (fClosestReplayTime != -1.0)
				{
					gF_VelocityDifference[client] = Shavit_GetClosestReplayVelocityDifference(client, false);
				}
			}
		}
	}

	// Update velocity;
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", gF_Velocity[client]);

	// Update energy;
	gF_Energy[client][0] = CaculateKineticEnergy(GetVectorLength(gF_Velocity[client]), fGravityScale);
	gF_Energy[client][1] = fPotential;

	gI_LastEntityFlags[client] = flags;
}

void ProcessJump(int client, bool replaybot = false)
{
	int style = replaybot ? Shavit_GetReplayBotStyle(client):Shavit_GetBhopStyle(client);
	float fGravityScale = Shavit_GetStyleSettingFloat(style, "gravity");

	float origin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", origin);
	gF_Energy[client][2] = CaculatePotentialEnergy(origin[2], fGravityScale);
}

// HUD Update & Colors
public void UpdateClientHUD(int client, int target, int cmdnum)
{
	bool bUpdate = (cmdnum % gI_UpdateFrequency[0]) == 0;
	bool bLowUpdate = (cmdnum % gI_UpdateFrequency[1]) == 0;

	if (gI_LastEditElement[client] > -1)
	{
		if (!bLowUpdate)
		{
			return;
		}

		if (gI_LastEditColorIndex[client] > -1)
		{
			SetHudTextParams(-1.0, -1.0, 0.12, gI_ColorEditCache[client][0], gI_ColorEditCache[client][1], gI_ColorEditCache[client][2], 255, 0, 0.0, 0.0, 0.0);
			if (gB_DynamicChannels)
				ShowHudText(client, GetDynamicChannel(gI_LastEditElement[client]), "%T", gS_ElementColorTranslations[gI_LastEditColorIndex[client]], client);
			else
				ShowSyncHudText(client, gH_ElementHUDSynchronizer[gI_LastEditElement[client]], "%T", gS_ElementColorTranslations[gI_LastEditColorIndex[client]], client);		
		}
		else if (gI_EditPositionAxis[client] > -1)
		{
			SetHudTextParams(gF_PositionEditCache[client][0], gF_PositionEditCache[client][1], 0.12, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
			if (gB_DynamicChannels)
				ShowHudText(client, GetDynamicChannel(gI_LastEditElement[client]), "[ %s ]", gS_ElementEditStrings[gI_LastEditElement[client]]);
			else
				ShowSyncHudText(client, gH_ElementHUDSynchronizer[gI_LastEditElement[client]], "[ %s ]", gS_ElementEditStrings[gI_LastEditElement[client]]);

			for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
			{
				if (gI_LastEditElement[client] != i)
				{
					SetHudTextParams(gF_HUDPosition[client][i][0], gF_HUDPosition[client][i][1], 0.12, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
					if (gB_DynamicChannels)
						ShowHudText(client, GetDynamicChannel(i), "%s", gS_ElementEditStrings[i]);
					else
						ShowSyncHudText(client, gH_ElementHUDSynchronizer[i], "%s", gS_ElementEditStrings[i]);	
				}
			}
		}
	}
	else
	{
		bool bReplay = (gB_ReplayPlayback && Shavit_IsReplayEntity(target));

		float fPos[2];
		int color[3]; 
		char sTime[32];

		if (bUpdate)
		{
			if (gB_HUDEnabled[client][HUD_Speedometer])
			{
				float fSpeed = gI_HUDDisplayLogic[client][HUD_Speedometer] == DisplayLogic_Default ? SquareRoot(Pow(gF_Velocity[target][0], 2.0) + Pow(gF_Velocity[target][1], 2.0)):GetVectorLength(gF_Velocity[target]);
				fPos = gF_HUDPosition[client][HUD_Speedometer];
				GetSpeedometerColor(client, target, color);

				SetHudTextParams(fPos[0], fPos[1], 0.12, color[0], color[1], color[2], 255, 0, 0.0, 0.0, 0.0);
				if (gB_DynamicChannels)
					ShowHudText(client, GetDynamicChannel(HUD_Speedometer), "%.0f", fSpeed);
				else
					ShowSyncHudText(client, gH_ElementHUDSynchronizer[HUD_Speedometer], "%.0f", fSpeed);
			}

			if (gB_HUDEnabled[client][HUD_Energymeter])
			{
				float fEnergyDiff = (gF_Energy[target][0] + gF_Energy[target][1]) - gF_Energy[target][2];
				fPos = gF_HUDPosition[client][HUD_Energymeter];
				GetEnergymeterColor(client, target, color);

				SetHudTextParams(fPos[0], fPos[1], 0.12, color[0], color[1], color[2], 255, 0, 0.0, 0.0, 0.0);
				if (gB_DynamicChannels)
					ShowHudText(client, GetDynamicChannel(HUD_Energymeter), "%.0f", fEnergyDiff);
				else
					ShowSyncHudText(client, gH_ElementHUDSynchronizer[HUD_Energymeter], "%.0f", fEnergyDiff);
			}

			if (gB_HUDEnabled[client][HUD_Timer])
			{
				float fTime;
				if(!bReplay)
				{
					fTime = gF_LastFinishedTime[target] != -1.0 ? gF_LastFinishedTime[target]: (Shavit_GetTimerStatus(target) == Timer_Stopped) ? 0.0:Shavit_GetClientTime(target);
				}  
				else if (Shavit_GetReplayStatus(target) != Replay_Idle)
				{
					fTime = Shavit_GetReplayTime(target);
				}

				GetTimerColor(client, target, color);
				fPos = gF_HUDPosition[client][HUD_Timer];
				
				FormatSeconds(fTime < 0.0 ? 0.0:fTime, sTime, 32, true, false, gI_HUDDisplayLogic[client][HUD_Timer] == DisplayLogic_First);

				SetHudTextParams(fPos[0], fPos[1], 0.12, color[0], color[1], color[2], 255, 0, 0.0, 0.0, 0.0);
				if (gB_DynamicChannels)
					ShowHudText(client, GetDynamicChannel(HUD_Timer), "%s", sTime);
				else
					ShowSyncHudText(client, gH_ElementHUDSynchronizer[HUD_Timer], "%s", sTime);	
			}
		}

		if (bLowUpdate)
		{
			if (gB_HUDEnabled[client][HUD_TimeDifference] && gI_HUDDisplayLogic[client][HUD_TimeDifference] == DisplayLogic_Default && gF_TimeDifference[target] != -1.0)
			{
				GetTimeDifferenceColor(client, target, color);
				fPos = gF_HUDPosition[client][HUD_TimeDifference];
				
				FormatSeconds(gF_TimeDifference[target], sTime, 32, false);

				SetHudTextParams(fPos[0], fPos[1], 0.24, color[0], color[1], color[2], 255, 0, 0.0, 0.0, 0.0);
				if (gB_DynamicChannels)
					ShowHudText(client, GetDynamicChannel(HUD_TimeDifference), "%s%s", gF_TimeDifference[target] >= 0.0 ? "+":"", sTime);
				else
					ShowSyncHudText(client, gH_ElementHUDSynchronizer[HUD_TimeDifference], "%s%s", gF_TimeDifference[target] >= 0.0 ? "+":"", sTime);

			}

			if (gB_HUDEnabled[client][HUD_SpeedDifference] && gF_VelocityDifference[target] != -1.0)
			{
				GetSpeedDifferenceColor(client, target, color);
				fPos = gF_HUDPosition[client][HUD_SpeedDifference];
				SetHudTextParams(fPos[0], fPos[1], 0.24, color[0], color[1], color[2], 255, 0, 0.0, 0.0, 0.0);
				if (gB_DynamicChannels)
					ShowHudText(client, GetDynamicChannel(HUD_SpeedDifference), "%s%.0f", gF_VelocityDifference[target] > 0.0 ? "+":"", gF_VelocityDifference[target]);
				else
					ShowSyncHudText(client, gH_ElementHUDSynchronizer[HUD_SpeedDifference], "%s%.0f", gF_VelocityDifference[target] > 0.0 ? "+":"", gF_VelocityDifference[target]);
			}
		}
	}
}

void GetTimeDifferenceColor(int client, int target, int color[3])
{
	int logic = gI_HUDColorLogic[client][HUD_TimeDifference];
	if (logic == ColorLogic_None)
	{
		color = gI_HUDColors[client][Color_TimeDifference_Defualt];
	}
	else if (logic == ColorLogic_First)
	{
		color = (gF_TimeDifference[target] > gF_LastTimeDifference[target]) ? gI_HUDColors[client][Color_TimeDifference_Lose]:gI_HUDColors[client][Color_TimeDifference_Gain];
	}
	else if (logic == ColorLogic_Second)
	{
		color = (gF_TimeDifference[target] >= 0.0) ? gI_HUDColors[client][Color_TimeDifference_Slower]:gI_HUDColors[client][Color_TimeDifference_Faster];
	}
}

void GetTimerColor(int client, int target, int color[3])
{
	int logic = gI_HUDColorLogic[client][HUD_Timer];
	if (logic == ColorLogic_None)
	{
		color = gI_HUDColors[client][Color_Timer_Default];
	}
	else
	{
		bool bReplay = (gB_ReplayPlayback && Shavit_IsReplayEntity(target));

		if (!bReplay)
		{
			TimerStatus status = Shavit_GetTimerStatus(target);
			bool bPractice = Shavit_IsPracticeMode(target);

			if (Shavit_IsClientForzen(client))
			{
				color = gI_HUDColors[client][Color_Timer_Paused];
			}
			else if (status == Timer_Running)
			{
				if (gB_InStartZone[target])
				{
					color = gI_HUDColors[client][Color_Timer_Start];
				}
				else
				{
					color = bPractice ? gI_HUDColors[client][Color_Timer_Practice]:gI_HUDColors[client][Color_Timer_Running];					
				}
			}
			else if (status == Timer_Paused)
			{
				color = gI_HUDColors[client][Color_Timer_Paused];
			}
			else
			{
				color = gF_LastFinishedTime[target] == -1.0 ? gI_HUDColors[client][Color_Timer_Stopped]:gI_HUDColors[client][Color_Timer_Finished_Worse + gI_LastFinishState[target]];
			}
		}
		else
		{
			int iStatus = Shavit_GetReplayStatus(target);
			if (iStatus == Replay_Idle)
			{
				color = gI_HUDColors[client][Color_Timer_Stopped];
			}
			else
			{
				float fTime = Shavit_GetReplayTime(target);
				if (fTime < 0.0)
				{
					color = gI_HUDColors[client][Color_Timer_Start];
				}
				else if(fTime >= Shavit_GetReplayCacheLength(target))
				{
					color = gI_HUDColors[client][Color_Timer_Finished_PB];
				}
				else
				{
					color = gI_HUDColors[client][Color_Timer_Running];
				}
			}
		}
	}
}

void GetSpeedometerColor(int client, int target, int color[3])
{
	int logic = gI_HUDColorLogic[client][HUD_Speedometer];

	if (logic == ColorLogic_None)
	{
		color = gI_HUDColors[client][Color_Speed_Default];
	}
	else if(logic == ColorLogic_First)
	{
		float fSpeed;
		float fLastSpeed;

		if (gI_HUDDisplayLogic[client][HUD_Speedometer] == DisplayLogic_Default)
		{
			fSpeed = SquareRoot(Pow(gF_Velocity[target][0], 2.0) + Pow(gF_Velocity[target][1], 2.0));
			fLastSpeed = SquareRoot(Pow(gF_LastVelocity[target][0], 2.0) + Pow(gF_LastVelocity[target][1], 2.0));
		}
		else
		{
			fSpeed = GetVectorLength(gF_Velocity[target]);
			fLastSpeed = GetVectorLength(gF_LastVelocity[target]);
		}

		if (fSpeed > fLastSpeed)
		{
			color = gI_HUDColors[client][Color_SpeedGradient_Gain];
		}
		else if(fSpeed < fLastSpeed)
		{
			color = gI_HUDColors[client][Color_SpeedGradient_Lose];			
		}
		else
		{
			color = gI_HUDColors[client][Color_Speed_Default];
		}
	}
}

void GetSpeedDifferenceColor(int client, int target, int color[3])
{
	int logic = gI_HUDColorLogic[client][HUD_SpeedDifference];

	if (logic == ColorLogic_None)
	{
		color = gI_HUDColors[client][Color_SpeedDifference_Default];
	}
	else if(logic == ColorLogic_First)
	{
		if (gF_VelocityDifference[target] >= 0.0)
		{
			color = gI_HUDColors[client][Color_SpeedDifference_Higher];
		}
		else
		{
			color = gI_HUDColors[client][Color_SpeedDifference_Lower];
		}
	}
}

void GetEnergymeterColor(int client, int target, int color[3])
{
	int logic = gI_HUDColorLogic[client][HUD_Energymeter];
	float fEnergyDiff = (gF_Energy[target][0] + gF_Energy[target][1]) - gF_Energy[target][2];

	if (logic == ColorLogic_None)
	{
		color = gI_HUDColors[client][Color_Energy_Default];
	}
	else if(logic == ColorLogic_First)
	{
		float fLastEnergyDiff = (gF_LastEnergy[target][0] + gF_LastEnergy[target][1]) - gF_LastEnergy[target][2];

		if (fEnergyDiff > fLastEnergyDiff)
		{
			color = gI_HUDColors[client][Color_EnergyGradient_Gain];
		}
		else if(fEnergyDiff < fLastEnergyDiff)
		{
			color = gI_HUDColors[client][Color_EnergyGradient_Lose];
		}
		else
		{
			color = gI_HUDColors[client][Color_Energy_Default];
		}		
	}
	else if(logic == ColorLogic_Second)
	{
		color = (fEnergyDiff >= 0) ? gI_HUDColors[client][Color_Energy_Higher]:gI_HUDColors[client][Color_Energy_Lower];
	}
}

// Forwards
public void Shavit_OnRestart(int client, int track)
{
	gF_LastFinishedTime[client] = -1.0;
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, float startvel, float endvel, int timestamp)
{
	gI_LastFinishState[client] = 0;
	gF_LastFinishedTime[client] = time;
	float fWR = Shavit_GetWorldRecord(style, track);

	if (!Shavit_IsPracticeMode(client))
	{
		if (time < fWR)
			gI_LastFinishState[client] = 2;
		else if(time < oldtime || oldtime == 0.0)
			gI_LastFinishState[client] = 1;
	}

	float fComparsion = (gI_HUDDisplayLogic[client][HUD_TimeDifference] == DisplayLogic_Second) ? fWR:oldtime;
	if (fComparsion == 0.0)
		return;

	float fTimeDifference = time - fComparsion;
	char sTime[32];
	FormatSeconds(fTimeDifference, sTime, 32, true);

	for (int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i))
		{
			return;
		}

		if (GetSpectatorTarget(i, i) == client && gB_HUDEnabled[i][HUD_TimeDifference] && gI_HUDDisplayLogic[i][HUD_TimeDifference] > DisplayLogic_Default)
		{
			int iColorIndex;
			iColorIndex = fTimeDifference > 0.0 ? Color_TimeDifference_Slower:Color_TimeDifference_Faster;

			SetHudTextParams(gF_HUDPosition[i][HUD_TimeDifference][0], gF_HUDPosition[i][HUD_TimeDifference][1], 8.0, gI_HUDColors[i][iColorIndex][0], gI_HUDColors[i][iColorIndex][1], gI_HUDColors[i][iColorIndex][2], 255, 0, 0.0, 0.0, 0.0);
			if (gB_DynamicChannels)
				ShowHudText(i, GetDynamicChannel(HUD_TimeDifference), "%s%s", fTimeDifference >= 0.0 ? "+":"", sTime);
			else
				ShowSyncHudText(i, gH_ElementHUDSynchronizer[HUD_TimeDifference], "%s%s", fTimeDifference >= 0.0 ? "+":"", sTime);			
		}
	}
}

public void Shavit_OnFinishStage(int client, int track, int style, int stage, float time, float oldtime, int jumps, int strafes, float sync, float perfs)
{
	if (!Shavit_IsOnlyStageMode(client))
	{
		return;
	}

	gI_LastFinishState[client] = 0;
	gF_LastFinishedTime[client] = time;
	float fWR = Shavit_GetStageWorldRecord(style, stage);

	if (!Shavit_IsPracticeMode(client))
	{
		if (time < fWR)
			gI_LastFinishState[client] = 2;
		else if(time < oldtime)
			gI_LastFinishState[client] = 1;
	}

	float fComparsion = (gI_HUDDisplayLogic[client][HUD_TimeDifference] == DisplayLogic_Second) ? fWR:oldtime;
	if (fComparsion == 0.0)
		return;

	float fTimeDifference = time - fComparsion;
	char sTime[32];
	FormatSeconds(fTimeDifference, sTime, 32, true);

	for (int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i))
		{
			return;
		}

		if (GetSpectatorTarget(i, i) == client && gB_HUDEnabled[i][HUD_TimeDifference] && gI_HUDDisplayLogic[i][HUD_TimeDifference] > DisplayLogic_Default)
		{
			int iColorIndex;
			iColorIndex = fTimeDifference > 0.0 ? Color_TimeDifference_Slower:Color_TimeDifference_Faster;

			SetHudTextParams(gF_HUDPosition[i][HUD_TimeDifference][0], gF_HUDPosition[i][HUD_TimeDifference][1], 8.0, gI_HUDColors[i][iColorIndex][0], gI_HUDColors[i][iColorIndex][1], gI_HUDColors[i][iColorIndex][2], 255, 0, 0.0, 0.0, 0.0);
			if (gB_DynamicChannels)
				ShowHudText(i, GetDynamicChannel(HUD_TimeDifference), "%s%s", fTimeDifference >= 0.0 ? "+":"", sTime);
			else
				ShowSyncHudText(i, gH_ElementHUDSynchronizer[HUD_TimeDifference], "%s%s", fTimeDifference >= 0.0 ? "+":"", sTime);
		}
	}
}

public void Shavit_OnReachNextCP(int client, int track, int checkpoint, float time)
{
	int style = Shavit_GetBhopStyle(client);
	float fComparsion, fComparsionLast; 
	if (gI_HUDDisplayLogic[client][HUD_TimeDifference] == DisplayLogic_Second)
	{
		fComparsion = Shavit_GetStageCPWR(track, style, checkpoint);
		fComparsionLast = checkpoint == 1 ? 0.0:Shavit_GetStageCPPB(client, track, style, checkpoint - 1);
	}
	else
	{
		fComparsion = Shavit_GetStageCPPB(client, track, style, checkpoint);
		fComparsionLast = checkpoint == 1 ? 0.0:Shavit_GetStageCPPB(client, track, style, checkpoint - 1);		
	}

	if (fComparsion == 0.0)
	{
		return;
	}
	
	float fLastCPTime = checkpoint == 1 ? 0.0:Shavit_GetClientCPTime(client, checkpoint - 1);
	float fTimeDifferenceLast = fLastCPTime - fComparsionLast;
	float fTimeDifference = time - fComparsion;
	bool bGained = (fTimeDifference - fTimeDifferenceLast) < 0.0;
	char sTime[32];
	FormatSeconds(fTimeDifference, sTime, 32, true);

	for (int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i))
		{
			return;
		}

		if (GetSpectatorTarget(i, i) == client && gB_HUDEnabled[i][HUD_TimeDifference] && gI_HUDDisplayLogic[i][HUD_TimeDifference] > DisplayLogic_Default)
		{
			int iColorIndex;
			if (gI_HUDColorLogic[i][HUD_TimeDifference] == ColorLogic_None)
			{
				iColorIndex = Color_TimeDifference_Defualt;
			}
			else if (gI_HUDColorLogic[i][HUD_TimeDifference] == ColorLogic_First)
			{
				iColorIndex = bGained ? Color_TimeDifference_Gain:Color_TimeDifference_Lose;
			}
			else if (gI_HUDColorLogic[i][HUD_TimeDifference] == ColorLogic_Second)
			{
				iColorIndex = fTimeDifference > 0.0 ? Color_TimeDifference_Slower:Color_TimeDifference_Faster;
			}

			SetHudTextParams(gF_HUDPosition[i][HUD_TimeDifference][0], gF_HUDPosition[i][HUD_TimeDifference][1], 4.0, gI_HUDColors[i][iColorIndex][0], gI_HUDColors[i][iColorIndex][1], gI_HUDColors[i][iColorIndex][2], 255, 0, 0.0, 0.0, 0.0);
			if (gB_DynamicChannels)
				ShowHudText(i, GetDynamicChannel(HUD_TimeDifference), "%s%s", fTimeDifference >= 0.0 ? "+":"", sTime);
			else
				ShowSyncHudText(i, gH_ElementHUDSynchronizer[HUD_TimeDifference], "%s%s", fTimeDifference >= 0.0 ? "+":"", sTime);				
		}
	}
}

public void Shavit_OnTimerMenuMade(int client, Menu menu)
{
	char sMenu[64];
	FormatEx(sMenu, sizeof(sMenu), "%T", "ColoredHUD", client);
	menu.AddItem("chud", sMenu);
}

public Action Shavit_OnTimerMenuSelect(int client, int position, char[] info, int maxlength)
{
	if(StrEqual(info, "chud"))
	{
		OpenHUDElementMenu(client);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

// stocks
stock float CaculateKineticEnergy(float velocity, float gravityScale)
{
	return 0.5 * PLAYER_MASS * Pow(velocity, 2.0) / (gravityScale * 800.0);
}

stock float CaculatePotentialEnergy(float height, float gravityScale)
{
	return PLAYER_MASS * gravityScale * height;
}

stock int GetClientObserverTarget(int client, int fallback = -1)
{
	int target = fallback;

	if(IsClientObserver(client))
	{
		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		if (iObserverMode >= 3 && iObserverMode <= 7)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if (IsValidEntity(iTarget))
			{
				target = iTarget;
			}
		}
	}

	return target;
}

stock bool PosEqual(float pos1[2], float pos2[2])
{
	for (int i = 0; i < 2; i++)
	{
		if (pos1[i] != pos2[i])
			return false;
	}

	return true;
}

stock bool ColorEqual(int color1[3], int color2[3])
{
	for (int i = 0; i < 3; i++)
	{
		if (color1[i] != color2[i])
			return false;
	}

	return true;
}

void LoadHUDConfig(int client)
{
	int iSteamID = GetSteamAccountID(client);

	if (iSteamID == 0) return;
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/coloredhud-config/%d.cfg", iSteamID);

	KeyValues kv = new KeyValues("HUDConfig");
	if (!kv.ImportFromFile(sPath))
	{
		SetDefaultHUDConfig(client);
		delete kv;
		return;
	}

	char sKey[8];
	if (kv.JumpToKey("enabled"))
	{
		for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
		{
			IntToString(i, sKey, 8);
			gB_HUDEnabled[client][i] = view_as<bool>(kv.GetNum(sKey, 0));
		}
		kv.GoBack();
	}

	char sValue[32];
	if (kv.JumpToKey("position"))
	{
		char sSpiltPos[2][16];
		for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
		{
			IntToString(i, sKey, 8);
			kv.GetString(sKey, sValue, sizeof(sValue), "-1.0;-1.0");
			ExplodeString(sValue, ";", sSpiltPos, 2, 16);
			gF_HUDPosition[client][i][0] = StringToFloat(sSpiltPos[0]);
			gF_HUDPosition[client][i][1] = StringToFloat(sSpiltPos[1]);
		}
		kv.GoBack();
	}

	if (kv.JumpToKey("colors"))
	{
		char sSpiltColor[3][8];
		for (int i = 0; i < Color_Size; i++)
		{
			IntToString(i, sKey, 8);
			kv.GetString(sKey, sValue, sizeof(sValue), "0;255;0");
			ExplodeString(sValue, ";", sSpiltColor, 3, 8);
			
			gI_HUDColors[client][i][0] = StringToInt(sSpiltColor[0]);
			gI_HUDColors[client][i][1] = StringToInt(sSpiltColor[1]);
			gI_HUDColors[client][i][2] = StringToInt(sSpiltColor[2]);
		}
		kv.GoBack();
	}

	if (kv.JumpToKey("displaylogic"))
	{
		for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
		{
			IntToString(i, sKey, 8);
			gI_HUDDisplayLogic[client][i] = kv.GetNum(sKey, 1);
		}
		kv.GoBack();
	}

	if (kv.JumpToKey("colorlogic"))
	{
		for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
		{
			IntToString(i, sKey, 8);
			gI_HUDColorLogic[client][i] = kv.GetNum(sKey, 1);
		}
		kv.GoBack();
	}

	gB_HUDConfigChanged[client] = false;
	delete kv;
}

void SaveHUDConfig(int client)
{
	int iSteamID = GetSteamAccountID(client);

	if (iSteamID == 0) return;
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/coloredhud-config/%d.cfg", iSteamID);

	KeyValues kv = new KeyValues("HUDConfig");
	char sKey[8];

	// enabled
	if (kv.JumpToKey("enabled", true))
	{
		for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
		{
			IntToString(i, sKey, 8);
			kv.SetNum(sKey, view_as<int>(gB_HUDEnabled[client][i]));
		}
		kv.GoBack();		
	}

	char sValue[32];
	if (kv.JumpToKey("position", true))
	{
		for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
		{
			IntToString(i, sKey, 8);
			FormatEx(sValue, sizeof(sValue), "%.3f;%.3f", gF_HUDPosition[client][i][0], gF_HUDPosition[client][i][1]);

			kv.SetString(sKey, sValue);
		}
		kv.GoBack();		
	}

	// colors
	if(kv.JumpToKey("colors", true))
	{
		for (int i = 0; i < Color_Size; i++)
		{
			IntToString(i, sKey, 8);
			FormatEx(sValue, sizeof(sValue), "%d;%d;%d", gI_HUDColors[client][i][0], gI_HUDColors[client][i][1], gI_HUDColors[client][i][2]);
			
			kv.SetString(sKey, sValue);
		}
		kv.GoBack();		
	}

	if (kv.JumpToKey("displaylogic", true))
	{
		for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
		{
			IntToString(i, sKey, 8);
			kv.SetNum(sKey, gI_HUDDisplayLogic[client][i]);
		}
		kv.GoBack();
	}

	// state
	if(kv.JumpToKey("colorlogic", true))
	{
		for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
		{
			IntToString(i, sKey, 8);
			kv.SetNum(sKey, gI_HUDColorLogic[client][i]);
		}
		kv.GoBack();		
	}

	kv.ExportToFile(sPath);
	gB_HUDConfigChanged[client] = false;
	delete kv;
}

public void FlushHUDConfigs()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (gB_HUDConfigChanged[i])
			{
				SaveHUDConfig(i);
			}
		}
	}
}

void SetDefaultHUDConfig(int client)
{
	gB_HUDConfigChanged[client] = true;

	gB_HUDEnabled[client] = gB_HUDEnabled[0];
	gI_HUDDisplayLogic[client] = gI_HUDDisplayLogic[0];
	gI_HUDColorLogic[client] = gI_HUDColorLogic[0];

	for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
	{
		gF_HUDPosition[client][i] = gF_HUDPosition[0][i];
	}

	for (int j = 0; j < Color_Size; j++)
	{
		gI_HUDColors[client][j] = gI_HUDColors[0][j];
	}
}

bool LoadDefaultHUDConfig()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/shavit-coloredhud.cfg");

	KeyValues kv = new KeyValues("Elements");
	if (!kv.ImportFromFile(sPath))
	{
		SetFailState("Failed to load default HUD config from %s.", sPath);
		delete kv;
		return false;
	}

	static char sElementNames[][32] =
	{
		"Speedometer", "SpeedDifference", "Energymeter", "Timer", "TimeDifference",
	};

	char sValue[64];
	char sSplitPos[2][16];
	char sSplitColor[3][8];

	for (int i = 0; i < HUD_ELEMENTCOUNTS; i++)
	{
		if (!kv.JumpToKey(sElementNames[i]))
		{
			SetFailState("Missing element '%s' in config.", sElementNames[i]);
			return false;
		}

		gB_HUDEnabled[0][i] = view_as<bool>(kv.GetNum("enabled", 0));

		kv.GetString("position", sValue, sizeof(sValue), "-1.0;-1.0");
		ExplodeString(sValue, ";", sSplitPos, 2, 16);
		gF_HUDPosition[0][i][0] = StringToFloat(sSplitPos[0]);
		gF_HUDPosition[0][i][1] = StringToFloat(sSplitPos[1]);

		gI_HUDDisplayLogic[0][i] = kv.GetNum("logic_display", 1);
		gI_HUDColorLogic[0][i] = kv.GetNum("logic_color", 1);

		for (int j = gI_ElementColorIndexRange[i][0]; j <= gI_ElementColorIndexRange[i][1]; j++)
		{
			kv.GetString(gS_ElementColorTranslations[j], sValue, sizeof(sValue), "255,255,255");
			ExplodeString(sValue, ",", sSplitColor, 3, 8);
			gI_HUDColors[0][j][0] = StringToInt(sSplitColor[0]);
			gI_HUDColors[0][j][1] = StringToInt(sSplitColor[1]);
			gI_HUDColors[0][j][2] = StringToInt(sSplitColor[2]);
		}

		kv.GoBack();
	}

	delete kv;
	return true;
}