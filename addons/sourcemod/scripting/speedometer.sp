#include <sourcemod>
#include <clientprefs>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <shavit/core>
#include <shavit/replay-playback>
#include <shavit/zones>

#pragma newdecls required
#pragma semicolon 1

#define BHOP_TIME 3
#define dynamicColor_off 1
#define dynamicColor_mode_1 2
#define dynamicColor_mode_2 3
#define modifier_1 1
#define modifier_10 2
#define modifier_100 3

#define White 1
#define Red 2
#define Green 3
#define Lime 4
#define Blue 5
#define Cyan 6
#define Yellow 7
#define Orange 8
#define Purple 9
#define LightRed 10


int Colors[11][3] = 
{{0,0,0},
{255, 255, 255},	//White
{255, 0, 0},		//Red
{0, 255, 0},		//Green
{150, 255, 0},		//Lime
{40, 150, 255},		//Blue
{0, 255, 255},		//Cyan
{255, 215, 0},		//Yellow
{219, 72, 16},		//Orange
{128, 0, 128},		//Purple
{255, 70, 60}};		//LightRed


bool gB_ReplayPlayback = false;
bool gB_Zones = false;
bool gB_Core = false;
bool gB_AllLibraryExists = false;

//Speedometer Settings
bool gB_SpeedometerDebug[MAXPLAYERS + 1];
bool gB_Speedometer[MAXPLAYERS + 1];

//Speedometer HUD Preference
bool gB_SpeedometerHud_SpeedDiff[MAXPLAYERS + 1];
bool gB_SpeedometerHud_SpeedDiffDynamicColor[MAXPLAYERS + 1];
int gI_SpeedometerHud_SpeedDynamicColor[MAXPLAYERS + 1];	//0 disable; 1 speed diff; 2 gain diff;
int gI_SpeedometerHud_RefreshPreTick[MAXPLAYERS + 1];
float gF_SpeedometerHud_PosX[MAXPLAYERS + 1];
float gF_SpeedometerHud_PosY[MAXPLAYERS + 1];

//Speedometer Color Settings
int gI_SpeedometerColor_Default[MAXPLAYERS + 1];
int gI_SpeedometerColor_SpeedIncrease[MAXPLAYERS + 1];
int gI_SpeedometerColor_SpeedDecrease[MAXPLAYERS + 1];
int gI_SpeedometerColor_SpeedGreater[MAXPLAYERS + 1];
int gI_SpeedometerColor_SpeedLess[MAXPLAYERS + 1];

//Setting Parameters
bool gB_SpeedometerAxis[MAXPLAYERS + 1]; //true: X, false: Y
int gI_SpeedometerPosModifier[MAXPLAYERS + 1];

//Datas
int g_iTicksOnGround[MAXPLAYERS + 1];
int g_strafeTick[MAXPLAYERS + 1];
int g_iTouchTicks[MAXPLAYERS + 1];
float g_flRawGain[MAXPLAYERS + 1];
bool g_bTouchesWall[MAXPLAYERS + 1];
float g_fLastSpeed[MAXPLAYERS + 1];

//Speedometer Cookies
Handle gH_SpeedometerCookie;
Handle gH_SpeedometerHudCookie_SpeedDiff;
Handle gH_SpeedometerHudCookie_SpeedDiffDynamicColor;
Handle gH_SpeedometerHudCookie_SpeedDynamicColor;
Handle gH_SpeedometerHudCookie_PosX;
Handle gH_SpeedometerHudCookie_PosY;
Handle gH_SpeedometerHudCookie_RefreshPreTickCookie;
Handle gH_SpeedometerColorCookie_Default;
Handle gH_SpeedometerColorCookie_Increase;
Handle gH_SpeedometerColorCookie_Decrease;
Handle gH_SpeedometerColorCookie_Greater;
Handle gH_SpeedometerColorCookie_Less;
Handle hudSync_Spd;
Handle hudSync_SpdDiff;

bool gB_Late;

public Plugin myinfo =
{
	name = "[shavit-surf] Speedometer",
	author = "KikI",
	description = "A advanced center speed hud plugin work with shavit surf timer",
	version = "1.3.0",
	url = "https://github.com/bhopppp/Shavit-Surf-Timer"
};

public void OnAllPluginsLoaded()
{
	HookEvent("player_jump", OnPlayerJump);
	gB_Core = LibraryExists("shavit");
	gB_ReplayPlayback = LibraryExists("shavit-replay-playback");
	gB_Zones = LibraryExists("shavit-zones");
	gB_AllLibraryExists = gB_Core && gB_ReplayPlayback && gB_Zones;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;
	return APLRes_Success;
}

public void OnClientPostAdminCheck(int client)
{
	g_strafeTick[client] = 0;
	g_flRawGain[client] = 0.0;
	g_iTicksOnGround[client] = 0;
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_speedometer", Command_Speedometer, "Show speedometer menu to client.");
	RegConsoleCmd("sm_speed", Command_Speedometer, "Show speedometer menu to client.");
	RegConsoleCmd("sm_spd", Command_Speedometer, "Show speedometer menu to client.");
	RegAdminCmd("sm_spddebug", Command_Debug, ADMFLAG_ROOT);

	gH_SpeedometerCookie = RegClientCookie("speedometer_enabled", "Speedometer enabled", CookieAccess_Public);
	gH_SpeedometerHudCookie_SpeedDiff = RegClientCookie("speedometer_showdiff", "Speedometer show speed differnce", CookieAccess_Public);
	gH_SpeedometerHudCookie_SpeedDynamicColor = RegClientCookie("speedometer_speedDynamicColor", "Speedometer show speed dynamic color", CookieAccess_Public);
	gH_SpeedometerHudCookie_SpeedDiffDynamicColor = RegClientCookie("speedometer_speedDiffDynamicColor", "Speedometer show speed diff dynamic color", CookieAccess_Public);
	gH_SpeedometerHudCookie_PosX = RegClientCookie("speedometer_postion_x", "Speedometer position X", CookieAccess_Public);
	gH_SpeedometerHudCookie_PosY = RegClientCookie("speedometer_postion_y", "Speedometer position Y", CookieAccess_Public);
	gH_SpeedometerHudCookie_RefreshPreTickCookie = RegClientCookie("speedometer_refreshFreq", "Speedometer refresh frequancy", CookieAccess_Public);

	gH_SpeedometerColorCookie_Default = RegClientCookie("speedometer_defaultColor", "Speedometer Default Color", CookieAccess_Public);
	gH_SpeedometerColorCookie_Increase = RegClientCookie("speedometer_color_increasing", "Speedometer Speed Increasing Color", CookieAccess_Public);
	gH_SpeedometerColorCookie_Decrease = RegClientCookie("speedometer_color_decreasing", "Speedometer Speed Decreasing Color", CookieAccess_Public);
	gH_SpeedometerColorCookie_Greater = RegClientCookie("speedometer_color_greater", "Speedometer Greater Speed Color", CookieAccess_Public);
	gH_SpeedometerColorCookie_Less = RegClientCookie("speedometer_color_less", "Speedometer Less Speed Color", CookieAccess_Public);

	gB_Core = LibraryExists("shavit");
	gB_ReplayPlayback = LibraryExists("shavit-replay-playback");
	gB_Zones = LibraryExists("shavit-zones");
	gB_AllLibraryExists = gB_Core && gB_ReplayPlayback && gB_Zones;

	if (hudSync_Spd == null)
	{
		hudSync_Spd = CreateHudSynchronizer();
	}

	if (hudSync_SpdDiff == null)
	{
		hudSync_SpdDiff = CreateHudSynchronizer();
	}

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
	if (!GetClientCookieBool(client, gH_SpeedometerCookie, gB_Speedometer[client]))
	{
		gB_Speedometer[client] = false;
		SetClientCookieBool(client, gH_SpeedometerCookie, false);
	}

	if (!GetClientCookieBool(client, gH_SpeedometerHudCookie_SpeedDiff, gB_SpeedometerHud_SpeedDiff[client]))
	{
		gB_SpeedometerHud_SpeedDiff[client] = false;
		SetClientCookieBool(client, gH_SpeedometerHudCookie_SpeedDiff, false);
	}

	if (!GetClientCookieBool(client, gH_SpeedometerHudCookie_SpeedDiffDynamicColor, gB_SpeedometerHud_SpeedDiffDynamicColor[client]))
	{
		gB_SpeedometerHud_SpeedDiffDynamicColor[client] = true;
		SetClientCookieBool(client, gH_SpeedometerHudCookie_SpeedDiffDynamicColor, true);
	}

	if (!GetClientCookieInt(client, gH_SpeedometerHudCookie_RefreshPreTickCookie, gI_SpeedometerHud_RefreshPreTick[client]))
	{
		gI_SpeedometerHud_RefreshPreTick[client] = 2;
		SetClientCookieInt(client, gH_SpeedometerHudCookie_RefreshPreTickCookie, 2);
	}

	if (!GetClientCookieInt(client, gH_SpeedometerHudCookie_SpeedDynamicColor, gI_SpeedometerHud_SpeedDynamicColor[client]))
	{
		gI_SpeedometerHud_SpeedDynamicColor[client] = 2;
		SetClientCookieInt(client, gH_SpeedometerHudCookie_SpeedDynamicColor, 2);
	}

	//Color Cookie
	if (!GetClientCookieInt(client, gH_SpeedometerColorCookie_Default, gI_SpeedometerColor_Default[client]))
	{
		gI_SpeedometerColor_Default[client] = White;
		SetClientCookieInt(client, gH_SpeedometerColorCookie_Default, White);
	}

	if (!GetClientCookieInt(client, gH_SpeedometerColorCookie_Increase, gI_SpeedometerColor_SpeedIncrease[client]))
	{
		gI_SpeedometerColor_SpeedIncrease[client] = Blue;
		SetClientCookieInt(client, gH_SpeedometerColorCookie_Increase, Blue);
	}

	if (!GetClientCookieInt(client, gH_SpeedometerColorCookie_Decrease, gI_SpeedometerColor_SpeedDecrease[client]))
	{
		gI_SpeedometerColor_SpeedDecrease[client] = LightRed;
		SetClientCookieInt(client, gH_SpeedometerColorCookie_Decrease, LightRed);
	}

	if (!GetClientCookieInt(client, gH_SpeedometerColorCookie_Greater, gI_SpeedometerColor_SpeedGreater[client]))
	{
		gI_SpeedometerColor_SpeedGreater[client] = Green;
		SetClientCookieInt(client, gH_SpeedometerColorCookie_Greater, Green);
	}

	if (!GetClientCookieInt(client, gH_SpeedometerColorCookie_Less, gI_SpeedometerColor_SpeedLess[client]))
	{
		gI_SpeedometerColor_SpeedLess[client] = Red;
		SetClientCookieInt(client, gH_SpeedometerColorCookie_Less, Red);
	}
	//Color Cookie

	if (!GetClientCookieFloat(client, gH_SpeedometerHudCookie_PosX, gF_SpeedometerHud_PosX[client]))
	{
		gF_SpeedometerHud_PosX[client] = -1.0;
		SetClientCookieFloat(client, gH_SpeedometerHudCookie_PosX, -1.0);
	}

	if (!GetClientCookieFloat(client, gH_SpeedometerHudCookie_PosY, gF_SpeedometerHud_PosY[client]))
	{
		gF_SpeedometerHud_PosY[client] = -1.0;
		SetClientCookieFloat(client, gH_SpeedometerHudCookie_PosY, -1.0);
	}
	
	gB_SpeedometerDebug[client] = false;
	gB_SpeedometerAxis[client] = true;
	gI_SpeedometerPosModifier[client] = modifier_10;
}

public Action OnPlayerJump(Event event, char[] name, bool dontBroadcast)
{
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);

	if(IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	g_strafeTick[client] = 0;
	g_flRawGain[client] = 0.0;
	SDKHook(client, SDKHook_Touch, onTouch);

	return Plugin_Handled;
}

public Action onTouch(int client, int entity)
{
	if(!(GetEntProp(entity, Prop_Data, "m_usSolidFlags") & 12))
	{
		g_bTouchesWall[client] = true;
	}

	return Plugin_Handled;
}

public Action Command_Speedometer(int client, int args)
{
	if (!IsValidClient2(client))
	{
		return Plugin_Continue;
	}

	return ShowSpeedometerMenu(client);
}

public Action Command_Debug(int client, int args)
{
	if (!IsValidClient2(client))
	{
		return Plugin_Continue;
	}

	gB_SpeedometerDebug[client] = !gB_SpeedometerDebug[client];
	if(gB_AllLibraryExists)
	{
		Shavit_PrintToChat(client, "Speedometer debug: \x07e9e500%s", gB_SpeedometerDebug[client] ? "ON":"OFF");
	}
	else
	{
		PrintToChat(client, "Speedometer debug: %s", gB_SpeedometerDebug[client] ? "ON":"OFF");
	}

	return Plugin_Handled;
}

public void Shavit_OnTimerMenuMade(int client, Menu menu)
{
	menu.AddItem("speed", "Center Speed HUD Options");
}

public Action Shavit_OnTimerMenuSelect(int client, int position, char[] info, int maxlength)
{
	if(StrEqual(info, "speed"))
	{
		ShowSpeedometerMenu(client, 0);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

Action ShowSpeedometerMenu(int client, int item = 0)
{
	Menu menu = new Menu(SpeedometerMenu_Handler, MENU_ACTIONS_ALL);
	SetMenuTitle(menu, "Speedometer Settings:\n \n");
	menu.AddItem("usage", gB_Speedometer[client]? "Usage: Enabled":"Usage: Disabled");
	if(gB_AllLibraryExists)
	{
		menu.AddItem("showDiff", gB_SpeedometerHud_SpeedDiff[client] ? "Speed Difference: ON":"Speed Difference: OFF");
	}
	else
	{
		menu.AddItem("showDiff", "Speed Difference: Not available", ITEMDRAW_DISABLED);
	}
	menu.AddItem("positon", "Postion Settings");
	menu.AddItem("colorSetting", "Color Settings\n ");
	char sMenu[64];
	float frequancy = 1 / (float(gI_SpeedometerHud_RefreshPreTick[client]) * GetTickInterval());
	FormatEx(sMenu, 64, "++Frequency\nUpdate Frequency: %.1f Hz", frequancy);
	menu.AddItem("plusRefreshPreTick", sMenu);
	menu.AddItem("minusRefreshPreTick", "--Frequency");
	menu.ExitButton = true;
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int SpeedometerMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_Select)
    {
        switch (param2)
		{
            case 0:
			{
				gB_Speedometer[param1] = !gB_Speedometer[param1];
				SetClientCookieBool(param1, gH_SpeedometerCookie, gB_Speedometer[param1]);
				ShowSpeedometerMenu(param1, GetMenuSelectionPosition());
			}
			case 1:
			{
				if (gB_AllLibraryExists)
				{
					gB_SpeedometerHud_SpeedDiff[param1] = !gB_SpeedometerHud_SpeedDiff[param1];
					SetClientCookieBool(param1, gH_SpeedometerHudCookie_SpeedDiff, gB_SpeedometerHud_SpeedDiff[param1]);
				}
				ShowSpeedometerMenu(param1, GetMenuSelectionPosition());
			}
			case 2:
			{
				ShowPosSettingMenu(param1);
			}
			case 3:
			{
				ShowColorSettingMenu(param1);
			}
			case 4:
			{
				if(gI_SpeedometerHud_RefreshPreTick[param1] > 1)
				{
					gI_SpeedometerHud_RefreshPreTick[param1] = gI_SpeedometerHud_RefreshPreTick[param1] - 1;
					SetClientCookieInt(param1, gH_SpeedometerHudCookie_RefreshPreTickCookie, gI_SpeedometerHud_RefreshPreTick[param1]);
				}
				ShowSpeedometerMenu(param1, GetMenuSelectionPosition());
			}
			case 5:
			{
				if(gI_SpeedometerHud_RefreshPreTick[param1] != 10)
				{
					gI_SpeedometerHud_RefreshPreTick[param1] = gI_SpeedometerHud_RefreshPreTick[param1] + 1;
					SetClientCookieInt(param1, gH_SpeedometerHudCookie_RefreshPreTickCookie, gI_SpeedometerHud_RefreshPreTick[param1]);
				}
				ShowSpeedometerMenu(param1, GetMenuSelectionPosition());
			}
		}
    }
	else if (action == MenuAction_End)
	{
		delete menu;
	}
    return 0;
}

Action ShowPosSettingMenu(int client, int item = 0)
{
	Menu menu = new Menu(PosSettingMenu_Handler);
	char sMenu[128];
	Format(sMenu, 128, "Speedometer Position Settings:\n \nCurrent Position: (X: %.3f, Y: %.3f)", gF_SpeedometerHud_PosX[client], gF_SpeedometerHud_PosY[client]);
	SetMenuTitle(menu, sMenu);
	menu.AddItem("axis", gB_SpeedometerAxis[client] ? "Axis: X":"Axis: Y"); // 0
	menu.AddItem("stepsize", gI_SpeedometerPosModifier[client] == modifier_1 ? "Step size: 1\n ": gI_SpeedometerPosModifier[client] == modifier_10 ? "Step size: 10\n ":"Step size: 100\n ");	//1
	menu.AddItem("plus", gI_SpeedometerPosModifier[client] == modifier_1 ? "+1": gI_SpeedometerPosModifier[client] == modifier_10 ? "+10":"+100");	//2
	menu.AddItem("minus", gI_SpeedometerPosModifier[client] == modifier_1 ? "-1\n ": gI_SpeedometerPosModifier[client] == modifier_10 ? "-10\n ":"-100\n ");	//3
	menu.AddItem("center", "Center");	//4
	menu.ExitBackButton = true;
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int PosSettingMenu_Handler(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		switch(selection)
		{
			case 0:
			{
				gB_SpeedometerAxis[client] = !gB_SpeedometerAxis[client];
				ShowPosSettingMenu(client, GetMenuSelectionPosition());
			}
			case 1:
			{
				gI_SpeedometerPosModifier[client] = (gI_SpeedometerPosModifier[client] % 3) + 1;
				ShowPosSettingMenu(client, GetMenuSelectionPosition());
			}
			case 2:	//plus
			{
				SetSpeedometerPos(client, true);
				ShowPosSettingMenu(client, GetMenuSelectionPosition());
			}
			case 3:	//minus
			{
				SetSpeedometerPos(client, false);
				ShowPosSettingMenu(client, GetMenuSelectionPosition());
			}
			case 4:
			{
				if(gB_SpeedometerAxis[client])
				{
					gF_SpeedometerHud_PosX[client] = -1.0;
					SetClientCookieFloat(client, gH_SpeedometerHudCookie_PosX, gF_SpeedometerHud_PosX[client]);
				}
				else
				{
					gF_SpeedometerHud_PosY[client] = -1.0;
					SetClientCookieFloat(client, gH_SpeedometerHudCookie_PosY, gF_SpeedometerHud_PosY[client]);
				}
				ShowPosSettingMenu(client, GetMenuSelectionPosition());
			}
		}
	}
	else if(action == MenuAction_Cancel && selection == MenuCancel_ExitBack)
	{
		ShowSpeedometerMenu(client);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}


Action ShowColorSettingMenu(int client, int item = 0)
{
	Menu menu = new Menu(ColorSettingMenu_Handler);
	SetMenuTitle(menu, "Speedometer Color Settings:\n \nSpeed Color Customize");
	char sMessage[64];
	Format(sMessage, sizeof(sMessage), "Dynamic Speed Color: %s", 
	gI_SpeedometerHud_SpeedDynamicColor[client] == dynamicColor_off ? "OFF" : gI_SpeedometerHud_SpeedDynamicColor[client] == dynamicColor_mode_1 ? "Speed Gradient":"Gain");
	menu.AddItem("dynamicSpeedColor", sMessage);

	char sColor[16];
	GetColorName(gI_SpeedometerColor_Default[client], sColor, sizeof(sColor));
	Format(sMessage, sizeof(sMessage), "Defalut Color: %s", sColor);
	menu.AddItem("defaultColor", sMessage);

	GetColorName(gI_SpeedometerColor_SpeedIncrease[client], sColor, sizeof(sColor));
	Format(sMessage, sizeof(sMessage), "Increasing Color: %s", sColor);
	menu.AddItem("increasingColor", sMessage, gI_SpeedometerHud_SpeedDynamicColor[client] == dynamicColor_mode_1 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	GetColorName(gI_SpeedometerColor_SpeedDecrease[client], sColor, sizeof(sColor));
	Format(sMessage, sizeof(sMessage), "Decreasing Color: %s%s", sColor, gB_AllLibraryExists ? "\n \nSpeed Difference Color Customize":"");
	menu.AddItem("decreasingColor", sMessage, gI_SpeedometerHud_SpeedDynamicColor[client] == dynamicColor_mode_1 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	if(gB_AllLibraryExists)
	{
		Format(sMessage, sizeof(sMessage), "Dynamic Speed Difference Color: %s", gB_SpeedometerHud_SpeedDiffDynamicColor[client] ? "ON":"OFF");
		menu.AddItem("dynamicSpeedDiffColor", sMessage);

		GetColorName(gI_SpeedometerColor_SpeedGreater[client], sColor, sizeof(sColor));
		Format(sMessage, sizeof(sMessage), "Greater Speed Color: %s", sColor);
		menu.AddItem("greaterColor", sMessage, gB_SpeedometerHud_SpeedDiffDynamicColor[client] ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

		GetColorName(gI_SpeedometerColor_SpeedLess[client], sColor, sizeof(sColor));
		Format(sMessage, sizeof(sMessage), "Less Speed Color: %s", sColor);
		menu.AddItem("lessColor", sMessage, gB_SpeedometerHud_SpeedDiffDynamicColor[client] ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int ColorSettingMenu_Handler(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		switch(selection)
		{
			case 0:
			{
				gI_SpeedometerHud_SpeedDynamicColor[client] = (gI_SpeedometerHud_SpeedDynamicColor[client] % 3) + 1;
				SetClientCookieInt(client, gH_SpeedometerHudCookie_SpeedDynamicColor, gI_SpeedometerHud_SpeedDynamicColor[client]);
				ShowColorSettingMenu(client, GetMenuSelectionPosition());
			}
			case 1:
			{
				gI_SpeedometerColor_Default[client] = (gI_SpeedometerColor_Default[client] % 10) + 1;
				SetClientCookieInt(client, gH_SpeedometerColorCookie_Default, gI_SpeedometerColor_Default[client]);
				ShowColorSettingMenu(client, GetMenuSelectionPosition());
			}
			case 2:
			{
				gI_SpeedometerColor_SpeedIncrease[client] = (gI_SpeedometerColor_SpeedIncrease[client] % 10) + 1;
				SetClientCookieInt(client, gH_SpeedometerColorCookie_Increase, gI_SpeedometerColor_SpeedIncrease[client]);
				ShowColorSettingMenu(client, GetMenuSelectionPosition());
			}
			case 3:
			{
				gI_SpeedometerColor_SpeedDecrease[client] = (gI_SpeedometerColor_SpeedDecrease[client] % 10) + 1;
				SetClientCookieInt(client, gH_SpeedometerColorCookie_Decrease, gI_SpeedometerColor_SpeedDecrease[client]);
				ShowColorSettingMenu(client, GetMenuSelectionPosition());
			}
			case 4:
			{
				gB_SpeedometerHud_SpeedDiffDynamicColor[client] = !gB_SpeedometerHud_SpeedDiffDynamicColor[client];
				SetClientCookieBool(client, gH_SpeedometerHudCookie_SpeedDiffDynamicColor, gB_SpeedometerHud_SpeedDiffDynamicColor[client]);
				ShowColorSettingMenu(client, GetMenuSelectionPosition());
			}
			case 5:
			{
				gI_SpeedometerColor_SpeedGreater[client] = (gI_SpeedometerColor_SpeedGreater[client] % 10) + 1;
				SetClientCookieInt(client, gH_SpeedometerColorCookie_Greater, gI_SpeedometerColor_SpeedGreater[client]);
				ShowColorSettingMenu(client, GetMenuSelectionPosition());
			}
			case 6:
			{
				gI_SpeedometerColor_SpeedLess[client] = (gI_SpeedometerColor_SpeedLess[client] % 10) + 1;
				SetClientCookieInt(client, gH_SpeedometerColorCookie_Less, gI_SpeedometerColor_SpeedLess[client]);
				ShowColorSettingMenu(client, GetMenuSelectionPosition());
			}
		}
	}
	else if(action == MenuAction_Cancel && selection == MenuCancel_ExitBack)
	{
		ShowSpeedometerMenu(client);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (!IsValidClient2(client) || IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	if (!gB_Speedometer[client])
	{
		return Plugin_Continue;
	}

	if (cmdnum % gI_SpeedometerHud_RefreshPreTick[client] != 0)
	{
		return Plugin_Continue;
	}

	int target = GetClientObserverTarget(client, client);

	if(!IsValidClient2(target))
	{
		return Plugin_Continue;
	}

	float speed = GetClientSpeed(target);
	bool bReplay = false;
	int iTrack;
	int iStage;
	TimerStatus iTimerStatus;
	float fClosestReplayTime = -1.0;
	float fClosestVelocityDifference = 0.0;
	float fClosestReplayLength = 0.0;

	if(gB_AllLibraryExists)
	{
		bReplay = (gB_ReplayPlayback && Shavit_IsReplayEntity(target));
		target = bReplay ? Shavit_GetReplayBotInfoIndex(target) : target;
		iTrack = (bReplay) ? Shavit_GetReplayBotTrack(target) : Shavit_GetClientTrack(target);
		iStage = Shavit_GetClientLastStage(target);
		iTimerStatus = (bReplay)  ? Timer_Running : Shavit_GetTimerStatus(target);
	}
	else
	{
		bReplay = IsClientObserver(client);
	}

	int iZoneStage;
	
	bool bInsideStageZone = iTrack == Track_Main ? Shavit_InsideZoneStage(client, iZoneStage):false;
	bool bInStart = gB_Zones && Shavit_InsideZone(client, Zone_Start, iTrack) || 
						(Shavit_IsOnlyStageMode(client) && bInsideStageZone && iZoneStage == Shavit_GetClientLastStage(client));

	if(GetEntityFlags(target) & FL_ONGROUND)
	{
		if(g_iTicksOnGround[target] > BHOP_TIME)
		{
			g_strafeTick[target] = 0;
			g_flRawGain[target] = 0.0;
		}
		
		g_iTicksOnGround[target]++;
		
		if(!bReplay && buttons & IN_JUMP && g_iTicksOnGround[target] == 1)
		{
			GetClientGains(target, vel, angles);
			g_iTicksOnGround[target] = 0;
		}

	}
	else
	{
		if(/*!bReplay &&*/ GetEntityMoveType(target) != MOVETYPE_NONE && GetEntityMoveType(target) != MOVETYPE_NOCLIP && GetEntityMoveType(target) != MOVETYPE_LADDER && GetEntProp(target, Prop_Data, "m_nWaterLevel") < 2)
		{
			GetClientGains(target, vel, angles);
		}

		if(g_bTouchesWall[target])
		{
			g_iTouchTicks[target]++;
			g_bTouchesWall[target] = false;
		}
		else
		{
			g_iTouchTicks[target] = 0;
		}

		g_iTicksOnGround[target] = 0;
	}

	if(g_bTouchesWall[target])
	{
		g_iTouchTicks[target]++;
		g_bTouchesWall[target] = false;
	}
	else
	{
		g_iTouchTicks[target] = 0;
	}

	if (!bReplay)
	{
		bool hasFrames = Shavit_GetReplayFrameCount(Shavit_GetClosestReplayStyle(target), iTrack, Shavit_IsOnlyStageMode(target) ? iStage : 0) != 0;
		if (gB_AllLibraryExists && hasFrames)
		{
			fClosestReplayTime = Shavit_GetClosestReplayTime(target, fClosestReplayLength);

			if (fClosestReplayTime != -1.0)
			{
				fClosestVelocityDifference = Shavit_GetClosestReplayVelocityDifference(target, false);
			}
		}
	}

	float coeffsum = g_flRawGain[target];
	coeffsum /= g_strafeTick[target];
	int rgb[3];

	if(gI_SpeedometerHud_SpeedDynamicColor[client] == dynamicColor_mode_1)
	{
		GetColorBySpeed(client, bReplay ? client:target, speed, rgb);
		SetPrevVelocity(client, speed);
	}
	else if(!bReplay && gI_SpeedometerHud_SpeedDynamicColor[client] == dynamicColor_mode_2)
	{
		if (GetEntityMoveType(client) != MOVETYPE_NONE && GetEntityMoveType(client) != MOVETYPE_NOCLIP && GetEntityMoveType(client) != MOVETYPE_LADDER)
		{
			GetColorByGain(client, target, coeffsum, rgb);
		}
		else
		{
			rgb = Colors[gI_SpeedometerColor_Default[client]];
		}
	}
	else
	{
		rgb = Colors[gI_SpeedometerColor_Default[client]];
	}

	if (gB_SpeedometerDebug[client])
	{
		SetHudTextParams(-1.0, -1.0, 0.3, rgb[0], rgb[1], rgb[2], 255, 0, 0.0, 0.0, 0.0);
		if (gB_AllLibraryExists)
		{
			ShowSyncHudText(client, hudSync_Spd, "Debug mode\nSpd: %.0f\nGn: %.2f\nRGB: %i %i %i\nSpd Diff: %s%.0f", speed, coeffsum*100, rgb[0], rgb[1], rgb[2], fClosestVelocityDifference > 0 ? "+":"", fClosestVelocityDifference);
		}
		else
		{
			ShowSyncHudText(client, hudSync_Spd, "Debug mode\nSpd: %.0f\nGn: %.2f\nRGB: %i %i %i\nSpd Diff: N/A", speed, coeffsum*100, rgb[0], rgb[0], rgb[2]);
		}
	}
	else
	{
		SetHudTextParams(gF_SpeedometerHud_PosX[client], gF_SpeedometerHud_PosY[client], 0.3, rgb[0], rgb[1], rgb[2], 255, 0, 0.0, 0.0, 0.0);
		ShowSyncHudText(client, hudSync_Spd, "%.0f\n", speed);
		if (gB_AllLibraryExists && gB_SpeedometerHud_SpeedDiff[client])
		{
			if(fClosestReplayTime != -1.0 && !bReplay && iTimerStatus == Timer_Running && !bInStart)
			{
				if(!gB_SpeedometerHud_SpeedDiffDynamicColor[client])
				{
					rgb = Colors[gI_SpeedometerColor_Default[client]];
				}
				else
				{
					if(fClosestVelocityDifference >= 0)
					{
						rgb = Colors[gI_SpeedometerColor_SpeedGreater[client]];
					}
					else
					{
						rgb = Colors[gI_SpeedometerColor_SpeedLess[client]];
					}
				}
				SetHudTextParams(gF_SpeedometerHud_PosX[client], gF_SpeedometerHud_PosY[client], 0.3, rgb[0], rgb[1], rgb[2], 255, 0, 0.0, 0.0, 0.0);
				ShowSyncHudText(client, hudSync_SpdDiff, "\n(%s%.0f)", fClosestVelocityDifference >= 0 ? "+":"", fClosestVelocityDifference);
			}
		}
	}
	
	return Plugin_Continue;
}

void SetPrevVelocity(int client, float vel)
void GetColorBySpeed(int client, int target, float speed, int rgb[3])
{
	if (speed > g_fLastSpeed[target])
	{
		rgb = Colors[gI_SpeedometerColor_SpeedIncrease[client]];
	}
	else if (speed < g_fLastSpeed[target])
	{
		rgb = Colors[gI_SpeedometerColor_SpeedDecrease[client]];
	}
	else
	{
		rgb = Colors[gI_SpeedometerColor_Default[client]];
	}		
}


void GetColorByGain(int client, int target, float gain, int rgb[3])
{
	if(g_iTicksOnGround[target] > BHOP_TIME)
	{
		rgb = Colors[gI_SpeedometerColor_Default[client]];
	}
	else
	{
		int offset;
		if (gain >= 0.95)
		{
			rgb[0] = 0; 
			rgb[1] = 255;
			rgb[2] = 200;
		}
		else if (gain >= 0.75)
		{
			offset = RoundToNearest((gain - 0.75) * 1000);
			rgb[0] = 0; 
			rgb[1] = 255;
			rgb[2] = offset;
		}
		else if (gain >=  0.60)
		{
			offset = RoundToNearest((gain - 0.60) * 1600);
			rgb[0] = 250 - offset;
			rgb[1] = 255;
			rgb[2] = 0;
		}
		else if (gain >= 0.40)
		{
			offset = RoundToNearest((gain - 0.40) * 1000);
			rgb[0] = 255;
			rgb[1] = offset;
			rgb[2] = 0;
		}
		else
		{
			rgb[0] = 255;
			rgb[1] = 0;
			rgb[2] = 0;
		}
	}
}


void SetSpeedometerPos(int client, bool param1)
{
	float modifier = gI_SpeedometerPosModifier[client] == modifier_1 ? 0.001 : gI_SpeedometerPosModifier[client] == modifier_10 ? 0.01 : 0.1;
	if (gB_SpeedometerAxis[client])
	{
		if(param1)
		{
			gF_SpeedometerHud_PosX[client] = gF_SpeedometerHud_PosX[client] == -1.0 ? 0.5 : gF_SpeedometerHud_PosX[client] + modifier;

			if (gF_SpeedometerHud_PosX[client] > 1.0)
			{
				gF_SpeedometerHud_PosX[client] = 1.0;
			}
		}
		else
		{
			gF_SpeedometerHud_PosX[client] = gF_SpeedometerHud_PosX[client] == -1.0 ? 0.5 : gF_SpeedometerHud_PosX[client] - modifier;

			if (gF_SpeedometerHud_PosX[client] < 0.0)
			{
				gF_SpeedometerHud_PosX[client] = 0.0;
			}
		}
		SetClientCookieFloat(client, gH_SpeedometerHudCookie_PosX, gF_SpeedometerHud_PosX[client]);
	}
	else
	{
		if(param1)
		{
			gF_SpeedometerHud_PosY[client] = gF_SpeedometerHud_PosY[client] == -1.0 ? 0.5 : gF_SpeedometerHud_PosY[client] + modifier;

			if(gF_SpeedometerHud_PosY[client] > 1.0)
			{
				gF_SpeedometerHud_PosY[client] = 1.0;
			}
		}
		else
		{
			gF_SpeedometerHud_PosY[client] = gF_SpeedometerHud_PosY[client] == -1.0 ? 0.5 : gF_SpeedometerHud_PosY[client] - modifier;

			if(gF_SpeedometerHud_PosY[client] < 0.0)
			{
				gF_SpeedometerHud_PosY[client] = 0.0;
			}
		}
		SetClientCookieFloat(client, gH_SpeedometerHudCookie_PosY, gF_SpeedometerHud_PosY[client]);
	}
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

stock void SetClientCookieInt(int client, Handle cookie, int value)
{
	char buffer[8];
	IntToString(value, buffer, 8);
	SetClientCookie(client, cookie, buffer);
}

stock bool GetClientCookieInt(int client, Handle cookie, int& value)
{
	char buffer[8];
	GetClientCookie(client, cookie, buffer, sizeof(buffer));
	if (buffer[0] == '\0')
	{
		return false;
	}

	value = StringToInt(buffer);
	return true;
}

stock void SetClientCookieFloat(int client, Handle cookie, float value)
{
	char buffer[8];
	FloatToString(value, buffer, 8);
	SetClientCookie(client, cookie, buffer);
}

stock bool GetClientCookieFloat(int client, Handle cookie, float& value)
{
	char buffer[8];
	GetClientCookie(client, cookie, buffer, sizeof(buffer));
	if (buffer[0] == '\0')
	{
		return false;
	}

	value = StringToFloat(buffer);
	return true;
}

stock int GetClientObserverMode(int client)
{
	return GetEntProp(client, Prop_Send, "m_iObserverMode");
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

void GetClientGains(int client, float vel[3], float angles[3])
{
	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	
	float gaincoeff;
	g_strafeTick[client]++;
	
	float fore[3], side[3], wishvel[3], wishdir[3];
	float wishspeed, wishspd, currentgain;
	
	GetAngleVectors(angles, fore, side, NULL_VECTOR);
	
	fore[2] = 0.0;
	side[2] = 0.0;
	NormalizeVector(fore, fore);
	NormalizeVector(side, side);
	
	for(int i = 0; i < 2; i++)
	{
		wishvel[i] = fore[i] * vel[0] + side[i] * vel[1];
	}
	
	wishspeed = NormalizeVector(wishvel, wishdir);
	if(wishspeed > GetEntPropFloat(client, Prop_Send, "m_flMaxspeed") && GetEntPropFloat(client, Prop_Send, "m_flMaxspeed") != 0.0)
	{
		wishspeed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");
	}
	
	if(wishspeed)
	{
		wishspd = (wishspeed > 30.0) ? 30.0 : wishspeed;
		
		currentgain = GetVectorDotProduct(velocity, wishdir);
		if(currentgain < 30.0)
		{
			gaincoeff = (wishspd - FloatAbs(currentgain)) / wishspd;
		}
		
		if(g_bTouchesWall[client] && g_iTouchTicks[client] && gaincoeff > 0.5)
		{
			gaincoeff -= 1;
			gaincoeff = FloatAbs(gaincoeff);
		}
		
		g_flRawGain[client] += gaincoeff;
	}
}

void GetColorName(int flag, char[] output, int size)
{
	switch (flag)
	{
		case White:		Format(output, size, "White");
		case Red:		Format(output, size, "Red");
		case Green:		Format(output, size, "Green");
		case Lime:		Format(output, size, "Lime");
		case Blue:		Format(output, size, "Blue");
		case Cyan:		Format(output, size, "Cyan");
		case Yellow:	Format(output, size, "Yellow");
		case Orange:	Format(output, size, "Orange");
		case Purple:	Format(output, size, "Purple");
		case LightRed:	Format(output, size, "Light Red");
	}
}


stock float GetClientSpeed(int client)
{
    float vel[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);

    return SquareRoot(Pow(vel[0], 2.0) + Pow(vel[1], 2.0));
}
