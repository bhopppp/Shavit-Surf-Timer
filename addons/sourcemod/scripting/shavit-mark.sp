/*
 * shavit's Surf Timer - Mark
 * by: SlidyBat, Ciallo-Ani, KikI
 * 
 * Ping mark implementation reference: https://github.com/DeadSurfer/trikz/blob/main/pingmark.sp
 *
 * This file is part of shavit's Surf Timer (https://github.com/shavitush/bhoptimer)
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
#include <shavit>

#pragma newdecls required
#pragma semicolon 1

#define PAINT_DISTANCE_SQ 1.0

#define MENU_PAINT 1
#define MENU_PING 2

#define RESPONSE_ACCEPT 1
#define RESPONSE_DECLINE 2
#define RESPONSE_CANCEL 3

#define PING_MODEL_PATH "models/expert_zone/pingtool/pingtool.mdl"
#define PING_SOUND_PATH "expert_zone/pingtool/click.wav"

/* Colour name, file name */
char gS_PaintColors[][][64] =    // Modify this to add/change colours
{
	{"ColorRandom",     	"random"         },
	{"ColorWhite",      	"paint_white"    },
	{"ColorBlack",      	"paint_black"    },
	{"ColorBlue",       	"paint_blue"     },
	{"ColorLightBlue", 		"paint_lightblue"},
	{"ColorBrown",      	"paint_brown"    },
	{"ColorCyan",       	"paint_cyan"     },
	{"ColorGreen",      	"paint_green"    },
	{"ColorDarkGreen", 		"paint_darkgreen"},
	{"ColorRed",        	"paint_red"      },
	{"ColorOrange",     	"paint_orange"   },
	{"ColorYellow",     	"paint_yellow"   },
	{"ColorPink",       	"paint_pink"     },
	{"ColorLightPink", 		"paint_lightpink"},
	{"ColorPurple",     	"paint_purple"   },
};

char gS_PingColors[][][64] =
{
	{"ColorTurquoise",	 	"134;226;213;150"},
    {"ColorWhite",       	"255;255;255;150"},
    {"ColorBlue",        	"40;120;255;150"},
    {"ColorGreen",       	"0;230;64;150"},
    {"ColorRed",         	"255;60;60;150"},
    {"ColorOrange",      	"255;125;35;150"},
    {"ColorYellow",      	"255;235;0;150"},
    {"ColorPink",        	"255;192;203;150"},
    {"ColorPurple",      	"168;70;228;150"},
    {"ColorCyan",        	"0;255;255;150"},
};

/* Size name, size suffix */
char gS_PaintSizes[][][64] =    // Modify this to add more sizes
{
	{"PaintSizeSmall",  ""      },
	{"PaintSizeMedium", "_med"  },
	{"PaintSizeLarge",  "_large"},
};

int gI_Sprites[sizeof(gS_PaintColors) - 1][sizeof(gS_PaintSizes)];
int gI_Eraser[sizeof(gS_PaintSizes)];
int gI_LastOpenedMenu[MAXPLAYERS + 1];

// Player Paint info
bool gB_ErasePaint[MAXPLAYERS + 1];
bool gB_IsPainting[MAXPLAYERS + 1];
float gF_LastPaint[MAXPLAYERS + 1][3];

// Player Ping info
int gI_PingEntity[2048] = {-1, ...};
int gI_PlayerPing[MAXPLAYERS + 1];
int gI_PlayerLastPing[MAXPLAYERS + 1];
Handle gH_PingTimer[MAXPLAYERS + 1];

// Player Partner info
int gI_Partner[MAXPLAYERS + 1];
int gI_Partnering[MAXPLAYERS + 1];

// Player Partner Setting
bool gB_ReciveRequest[MAXPLAYERS + 1];

// Paint Settings
int gI_PlayerPaintColor[MAXPLAYERS + 1];
int gI_PlayerPaintSize[MAXPLAYERS + 1];
bool gB_PaintToAll[MAXPLAYERS + 1];
bool gB_PaintMode[MAXPLAYERS + 1];

// Ping Settings
int gI_PingColor[MAXPLAYERS + 1];
bool gB_PingSound[MAXPLAYERS + 1];
bool gB_PingDuration[MAXPLAYERS + 1];	// True - Until next ping 		False - Only few seconds
bool gB_PingToAll[MAXPLAYERS + 1];

// Global Variables
int gI_Tickrate;
int gI_PingIntervalTick;
bool gB_Late = false;

chatstrings_t gS_ChatStrings;

/* COOKIES */
Cookie gH_PlayerPaintColor;
Cookie gH_PlayerPaintSize;
Cookie gH_PlayerReciveRequest;
Cookie gH_PlayerPaintMode;

Cookie gH_PlayerPingDuration;
Cookie gH_PlayerPingSound;
Cookie gH_PlayerPingColor;

/* CONVARS */
Convar gCV_AccessFlag;
Convar gCV_PingDuration;
Convar gCV_PingInterval;

public Plugin myinfo =
{
	name = "[shavit-surf] Mark",
	author = "SlidyBat, Ciallo-Ani, KikI",
	description = "Allow players to mark a position with decals or ping markers.",
	version = "4.0",
	url = "https://github.com/bhopppp/Shavit-Surf-Timer"
}

public void OnPluginStart()
{
	/* Register Cookies */
	gH_PlayerPaintColor = new Cookie("mark_playerpaintcolor", "mark_playerpaintcolor", CookieAccess_Protected);
	gH_PlayerPaintSize = new Cookie("mark_playerpaintsize", "mark_playerpaintsize", CookieAccess_Protected);
	gH_PlayerPaintMode = new Cookie("mark_playerpaintmode", "mark_playerpaintmode", CookieAccess_Protected);
	gH_PlayerReciveRequest = new Cookie("mark_playerreciverequest", "mark_playerreciverequest", CookieAccess_Protected);

	gH_PlayerPingDuration = new Cookie("paint_playerpingduration", "paint_playerpingduration", CookieAccess_Protected);
	gH_PlayerPingSound = new Cookie("paint_playerpingsound", "paint_playerpingsound", CookieAccess_Protected);
	gH_PlayerPingColor = new Cookie("paint_playerpingcolor", "paint_playerpingcolor", CookieAccess_Protected);

	gCV_AccessFlag = new Convar("shavit_mark_displaytoall_accessflag", "", "Flag to require privileges for send decals or ping markers to all players", 0, false, 0.0, false, 0.0);
	gCV_PingDuration = new Convar("shavit_mark_pingduration", "4.0", "The duration time (in seconds) of ping marks\n 0.0 - Until next ping marks created", 0, true, 0.0, true, 20.0);
	gCV_PingInterval = new Convar("shavit_mark_pinginterval", "0.5", "The minimum time interval (in seconds) between two ping marks", 0, true, 0.1, true, 5.0);
	Convar.AutoExecConfig();

	gCV_PingInterval.AddChangeHook(OnConVarChanged);

	gI_Tickrate = RoundToNearest(1.0 / GetTickInterval());

	/* COMMANDS */
	RegConsoleCmd("+paint", Command_EnablePaint, "Start Painting");
	RegConsoleCmd("-paint", Command_DisablePaint, "Stop Painting");
	RegConsoleCmd("sm_paint", Command_Paint, "Open a paint menu for a client");
	RegConsoleCmd("sm_paintcolour", Command_PaintColour, "Open a paint color menu for a client");
	RegConsoleCmd("sm_paintcolor", Command_PaintColour, "Open a paint color menu for a client");
	RegConsoleCmd("sm_paintsize", Command_PaintSize, "Open a paint size menu for a client");
	RegConsoleCmd("sm_paintmode", Command_PaintMode, "Toggle paint mode for a client");
	RegConsoleCmd("sm_painteraser", Command_PaintErase, "Toggle paint eraser for a client");

	RegConsoleCmd("sm_ping", Command_Ping, "Ping the position where player aiming at");
	RegConsoleCmd("sm_pingmenu", Command_PingMenu, "Open a ping menu for a client");
	RegConsoleCmd("sm_pingcolor", Command_PingColor, "Open a ping color menu for a client");
	
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-mark.phrases");

	/* Late loading */
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientCookiesCached(i);
		}
	}

	if(gB_Late)
	{
		Shavit_OnChatConfigLoaded();
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;

	return APLRes_Success;
}

public void OnClientCookiesCached(int client)
{
	if(!GetClientCookieInt(client, gH_PlayerPaintColor, gI_PlayerPaintColor[client]))
	{
		SetClientCookieInt(client, gH_PlayerPaintColor, 0);
	}

	if(!GetClientCookieInt(client, gH_PlayerPaintSize, gI_PlayerPaintSize[client]))
	{
		SetClientCookieInt(client, gH_PlayerPaintSize, 0);
	}

	if(!GetClientCookieBool(client, gH_PlayerPaintMode, gB_PaintMode[client]))
	{
		SetClientCookieBool(client, gH_PlayerPaintMode, false);
	}

	if(!GetClientCookieBool(client, gH_PlayerPingSound, gB_PingSound[client]))
	{
		gB_PingSound[client] = true;
		SetClientCookieBool(client, gH_PlayerPingSound, true);
	}

	if(!GetClientCookieBool(client, gH_PlayerPingDuration, gB_PingDuration[client]))
	{
		SetClientCookieBool(client, gH_PlayerPingDuration, false);
	}

	if(!GetClientCookieInt(client, gH_PlayerPingColor, gI_PingColor[client]))
	{
		gI_PingColor[client] = 0;
		SetClientCookieInt(client, gH_PlayerPingColor, 0);
	}

	if(!GetClientCookieBool(client, gH_PlayerReciveRequest, gB_ReciveRequest[client]))
	{
		gB_ReciveRequest[client] = true;
		SetClientCookieBool(client, gH_PlayerReciveRequest, true);
	}

	gB_PingToAll[client] = false;
	gB_PaintToAll[client] = false;

	gI_Partner[client] = 0;
}

public void OnConfigsExecuted() 
{
	gI_PingIntervalTick = RoundToCeil(gCV_PingInterval.FloatValue * float(gI_Tickrate));
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(StrEqual(oldValue, newValue))
	{
		return;
	}

	if(convar == gCV_PingInterval)
	{
		gI_PingIntervalTick = RoundToCeil(gCV_PingInterval.FloatValue * float(gI_Tickrate));
	}
}

public void OnMapStart()
{
	char buffer[PLATFORM_MAX_PATH];

	for (int color = 1; color < sizeof(gS_PaintColors); color++)
	{
		for (int size = 0; size < sizeof(gS_PaintSizes); size++)
		{
			Format(buffer, sizeof(buffer), "decals/paint/%s%s.vmt", gS_PaintColors[color][1], gS_PaintSizes[size][1]);
			gI_Sprites[color - 1][size] = PrecachePaint(buffer); // color - 1 because starts from [1], [0] is reserved for random
		}
	}

	for (int size = 0; size < sizeof(gS_PaintSizes); size++)
	{
		Format(buffer, sizeof(buffer), "decals/paint/paint_eraser%s.vmt", gS_PaintSizes[size][1]);
		gI_Eraser[size] = PrecachePaint(buffer); 
	}

	AddFilesToDownloadsTable();
}

public void OnClientConnected(int client)
{
	gI_PlayerPing[client] = 0;
	gI_PingEntity[gI_PlayerPing[client]] = -1;
	gI_PlayerLastPing[client] = 0;
}

public void OnMapEnd()
{
	for (int i = 0; i++; i <= MaxClients)
	{
		RemovePing(i);
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public Action Command_EnablePaint(int client, int args)
{
	gB_IsPainting[client] = true;

	return Plugin_Handled;
}

public Action Command_DisablePaint(int client, int args)
{
	if(!gB_PaintMode[client])
	{
		gB_IsPainting[client] = false;		
	}

	return Plugin_Handled;
}

public Action Command_Paint(int client, int args)
{
	OpenPaintMenu(client);

	return Plugin_Handled;
}

public Action Command_PingMenu(int client, int args)
{
	OpenPingMenu(client);

	return Plugin_Handled;
}

public Action Command_Ping(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(GetGameTickCount() - gI_PlayerLastPing[client] <= gI_PingIntervalTick)
	{
		return Plugin_Handled;
	}

	RemovePing(client);

	float pos[3];
	if(!TraceEye(client, pos))
	{
		return Plugin_Handled;
	}

	float angle[3];
	CaculatePlaneRotation(angle);

	float vec[3];
	GetAngleVectors(angle, vec, NULL_VECTOR, NULL_VECTOR);
	
	pos[0] -= vec[0] * 1.0;
	pos[1] -= vec[1] * 1.0;
	pos[2] -= vec[2] * 1.0;

	int color[4];
	GetPingColor(gI_PingColor[client], color);

	CreatePingEffect(client, pos, angle, color, gCV_PingDuration.FloatValue);

	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (cmdnum % 2 != 0)
	{
		return Plugin_Continue;
	}

	if (IsClientInGame(client) && gB_IsPainting[client])
	{
		static float pos[3];
		TraceEye(client, pos);

		if (GetVectorDistance(pos, gF_LastPaint[client], true) > PAINT_DISTANCE_SQ) 
		{
			if (gB_ErasePaint[client])
			{
				EracePaint(client, pos, gI_PlayerPaintSize[client]);
			}
			else
			{
				AddPaint(client, pos, gI_PlayerPaintColor[client], gI_PlayerPaintSize[client]);
			}
		}

		gF_LastPaint[client] = pos;

		if(gB_PaintMode[client])
		{
			gB_IsPainting[client] = false;
		}
	}

	return Plugin_Continue;
}

void OpenPingMenu(int client)
{
	gI_LastOpenedMenu[client] = MENU_PING;

	Menu menu = new Menu(Ping_MenuHandler);

	menu.SetTitle("%T\n  \n%T\n ", "PingMenuTitle", client, "PingTips", client);

	char sMenuItem[64];

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "CreatePingMarker", client);
	menu.AddItem("ping", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", "RemovePingMarker", client);
	menu.AddItem("unping", sMenuItem);

	if(gI_Partner[client] == 0)
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", "PaintSelectPartner", client);
		menu.AddItem("partner", sMenuItem);
	}
	else
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %N\n ", "RemovePartner", client, gI_Partner[client]);
		menu.AddItem("remove", sMenuItem);
	}

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n \n \n \n ", "PingOptions", client);
	menu.AddItem("option", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "<< %T", "PaintMenuTitle", client);
	menu.AddItem("paintmenu", sMenuItem);

	menu.Display(client, MENU_TIME_FOREVER);
}

public int Ping_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		if(StrEqual(sInfo, "ping"))
		{
			Command_Ping(param1, 0);
			OpenPingMenu(param1);
		}
		else if(StrEqual(sInfo, "unping"))
		{
			RemovePing(param1);

			OpenPingMenu(param1);
		}
		else if(StrEqual(sInfo, "option"))
		{
			OpenPingOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "partner"))
		{
			OpenPartnerMenu(param1);
		}
		else if(StrEqual(sInfo, "remove"))
		{
			RemovePartner(param1);

			OpenPingMenu(param1);
		}
		else if(StrEqual(sInfo, "paintmenu"))
		{
			OpenPaintMenu(param1);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OpenPingOptionMenu(int client)
{
	Menu menu = new Menu(PingtOption_MenuHandler);
	menu.SetTitle("%T\n ", "PingOptionMenuTitle", client);

	char sMenuItem[64];
	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: ", "PingDuration", client);

	if(gB_PingDuration[client])
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%s%T", sMenuItem, "DurationLong", client);
	}
	else
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%s%T", sMenuItem, "DurationShort", client, gCV_PingDuration.IntValue);
	}
	
	menu.AddItem("duration", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "PingColor", client, gS_PingColors[gI_PingColor[client]][0], client);
	menu.AddItem("color", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "[%T] %T", gB_PingSound[client] ? "ItemEnabled":"ItemDisabled", client, "PingSound", client);
	menu.AddItem("sound", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "[%T] %T", gB_ReciveRequest[client] ? "ItemEnabled":"ItemDisabled", client, "ReceivePartnerRequest", client);
	menu.AddItem("receive", sMenuItem);

	if(CheckClientAccess(client))
    {
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "PingObject", client, gB_PingToAll[client] ? "ObjectAll":"ObjectSingle", client);
		menu.AddItem("object", sMenuItem);
    }

	menu.ExitBackButton = true;

	menu.Display(client, MENU_TIME_FOREVER);
}

public int PingtOption_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		if(StrEqual(sInfo, "duration"))
		{
			gB_PingDuration[param1] = !gB_PingDuration[param1];
			SetClientCookieBool(param1, gH_PlayerPingDuration, gB_PingDuration[param1]);

			OpenPingOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "color"))
		{
			OpenPingColorMenu(param1);
		}
		else if(StrEqual(sInfo, "sound"))
		{
			gB_PingSound[param1] = !gB_PingSound[param1];
			SetClientCookieBool(param1, gH_PlayerPingSound, gB_PingSound[param1]);

			OpenPingOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "receive"))
		{
			gB_ReciveRequest[param1] = !gB_ReciveRequest[param1];

			SetClientCookieBool(param1, gH_PlayerReciveRequest, gB_ReciveRequest[param1]);
			OpenPingOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "object"))
		{
			gB_PingToAll[param1] = !gB_PingToAll[param1];
			OpenPingOptionMenu(param1);
		}
	}
	else if(action == MenuAction_Cancel)
	{
		OpenPingMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_PingColor(int client, int args)
{
	OpenPingColorMenu(client);

	return Plugin_Continue;
}

void OpenPingColorMenu(int client, int item = 0)
{
	Menu menu = new Menu(PingColour_MenuHandler);

	menu.SetTitle("%T\n ", "PingColorMenuTitle", client);
	
	char sMenuItem[64];
	for (int i = 0; i < sizeof(gS_PingColors); i++)
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", gS_PingColors[i][0], client);

		menu.AddItem("", sMenuItem, gI_PingColor[client] == i ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int PingColour_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		gI_PingColor[param1] = param2;
		SetClientCookieInt(param1, gH_PlayerPingColor, gI_PingColor[param1]);

		if(gI_PlayerPing[param1] > 0)
		{
			int color[4];
			GetPingColor(param2, color);
			SetEntityRenderColor(gI_PlayerPing[param1], color[0], color[1], color[2], color[3]);
		}

		OpenPingColorMenu(param1, GetMenuSelectionPosition());
	}
	else if(action == MenuAction_Cancel)
	{
		OpenPingOptionMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenPaintMenu(int client)
{
	gI_LastOpenedMenu[client] = MENU_PAINT;

	Menu menu = new Menu(Paint_MenuHandler);

	menu.SetTitle("%T\n  \n%T\n ", "PaintMenuTitle", client, "PaintTips", client);

	char sMenuItem[64];

	if(gB_PaintMode[client])
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", gB_ErasePaint[client] ? "ToggleErase":"TogglePaint", client);
		menu.AddItem("paint", sMenuItem);
	}
	else
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "[%T] %T\n ", gB_IsPainting[client] ? "ItemEnabled":"ItemDisabled", client, gB_ErasePaint[client] ? "ToggleErase":"TogglePaint", client);
		menu.AddItem("paint", sMenuItem);		
	}

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "PaintEraser", client, gB_ErasePaint[client] ? "EraserOn":"EraserOff", client);
	menu.AddItem("erase", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", "PaintClear", client);
	menu.AddItem("clear", sMenuItem);

	if(gI_Partner[client] == 0)
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", "PaintSelectPartner", client);
		menu.AddItem("partner", sMenuItem);
	}
	else
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %N\n ", "RemovePartner", client, gI_Partner[client]);
		menu.AddItem("remove", sMenuItem);
	}

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n \n ", "PaintOptions", client);
	menu.AddItem("option", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T >>", "PingMenuTitle", client);
	menu.AddItem("pingmenu", sMenuItem);

	menu.Display(client, MENU_TIME_FOREVER);
}

public int Paint_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		if(StrEqual(sInfo, "paint"))
		{
			gB_IsPainting[param1] = !gB_IsPainting[param1];
			OpenPaintMenu(param1);
		}
		else if(StrEqual(sInfo, "option"))
		{
			OpenPaintOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "erase"))
		{
			gB_ErasePaint[param1] = !gB_ErasePaint[param1];
			OpenPaintMenu(param1);
		}
		else if(StrEqual(sInfo, "clear"))
		{
			ClientCommand(param1, "r_cleardecals");
			Shavit_PrintToChat(param1, "%T", "PaintCleared", param1);
			OpenPaintMenu(param1);
		}
		else if(StrEqual(sInfo, "partner"))
		{
			OpenPartnerMenu(param1);
		}
		else if(StrEqual(sInfo, "remove"))
		{
			RemovePartner(param1);

			OpenPaintMenu(param1);
		}
		else if(StrEqual(sInfo, "pingmenu"))
		{
			OpenPingMenu(param1);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenPaintOptionMenu(int client)
{
	Menu menu = new Menu(PaintOption_MenuHandler);
	menu.SetTitle("%T\n ", "PaintOptionMenuTitle", client);

	char sMenuItem[64];
	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "PaintMode", client, gB_PaintMode[client] ? "ModeSingle":"ModeContinuous", client);
	menu.AddItem("mode", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "PaintColor", client, gS_PaintColors[gI_PlayerPaintColor[client]][0], client);
	menu.AddItem("color", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "PaintSize", client, gS_PaintSizes[gI_PlayerPaintSize[client]][0], client);
	menu.AddItem("size", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "[%T] %T", gB_ReciveRequest[client] ? "ItemEnabled":"ItemDisabled", client, "ReceivePartnerRequest", client);
	menu.AddItem("receive", sMenuItem);

	if(CheckClientAccess(client))
    {
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "PaintObject", client, gB_PaintToAll[client] ? "ObjectAll":"ObjectSingle", client);
		menu.AddItem("object", sMenuItem);
    }

	menu.ExitBackButton = true;

	menu.Display(client, MENU_TIME_FOREVER);
}

public int PaintOption_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		if(StrEqual(sInfo, "color"))
		{
			OpenPaintColorMenu(param1);
		}
		else if(StrEqual(sInfo, "size"))
		{
			OpenPaintSizeMenu(param1);
		}
		else if(StrEqual(sInfo, "mode"))
		{
			if(gB_IsPainting[param1])
			{
				Shavit_PrintToChat(param1, "%T", "PaintModeChangeError", param1);
			}
			else
			{
				gB_PaintMode[param1] = !gB_PaintMode[param1];
				SetClientCookieBool(param1, gH_PlayerPaintMode, gB_PaintMode[param1]);
			}

			OpenPaintOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "object"))
		{
			gB_PaintToAll[param1] = !gB_PaintToAll[param1];

			OpenPaintOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "receive"))
		{
			gB_ReciveRequest[param1] = !gB_ReciveRequest[param1];
			SetClientCookieBool(param1, gH_PlayerReciveRequest, gB_ReciveRequest[param1]);

			OpenPaintOptionMenu(param1);
		}
	}
	else if(action == MenuAction_Cancel)
	{
		OpenPaintMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_PaintColour(int client, int args)
{
	OpenPaintColorMenu(client);

	return Plugin_Continue;
}

void OpenPaintColorMenu(int client, int item = 0)
{
	Menu menu = new Menu(PaintColour_MenuHandler);

	menu.SetTitle("%T\n ", "PaintColorMenuTitle", client);
	
	char sMenuItem[64];
	for (int i = 0; i < sizeof(gS_PaintColors); i++)
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", gS_PaintColors[i][0], client);

		menu.AddItem("", sMenuItem, gI_PlayerPaintColor[client] == i ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int PaintColour_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		gI_PlayerPaintColor[param1] = param2;
		SetClientCookieInt(param1, gH_PlayerPaintColor, gI_PlayerPaintColor[param1]);

		OpenPaintColorMenu(param1, GetMenuSelectionPosition());
	}
	else if(action == MenuAction_Cancel)
	{
		OpenPaintOptionMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void RemovePartner(int client)
{
	if(gI_Partner[client] != 0)
	{
		int partner = gI_Partner[client];

		gI_Partner[client] = 0; 
		gI_Partner[partner] = 0;

		char sName[64];
		GetClientName(client, sName, sizeof(sName));
		char sPartnerName[64];
		GetClientName(partner, sPartnerName, sizeof(sPartnerName));

		Shavit_PrintToChat(client, "%T", "Unpartnered", client, gS_ChatStrings.sVariable2, sPartnerName, gS_ChatStrings.sText);
		Shavit_PrintToChat(partner, "%T", "Unpartnered", partner, gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText);				
	}
	else
	{
		Shavit_PrintToChat(client, "%T", "NoPartner", client);
	}
}

public void OnClientDisconnect(int client)
{
	if(gI_Partnering[client] != 0)
	{
		PartneringResponse(client, gI_Partnering[client], 4);
	}

	if(gI_Partner[client] != 0)
	{
		char sName[64];
		GetClientName(client, sName, sizeof(sName));
		Shavit_PrintToChat(gI_Partner[client], "%T", "PartnerDisconnected", gI_Partner[client], gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText);
		gI_Partner[gI_Partner[client]] = 0;
		gI_Partner[client] = 0;
	}

	RemovePing(client);
}

public void OpenPartnerMenu(int client)
{
	Menu menu = new Menu(Partner_MenuHandler);
	menu.SetTitle("%T\n ", "SendPartnerRequest", client);

	char sMenuItem[64];
	char sInfo[8];

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T\n ", "Refresh", client);
	menu.AddItem("refresh", sMenuItem);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && i != client && gB_ReciveRequest[i] && gI_Partner[i] == 0 && gI_Partnering[i] == 0)
		{
			IntToString(i, sInfo, sizeof(sInfo));
			FormatEx(sMenuItem, sizeof(sMenuItem), "%N", i);
			menu.AddItem(sInfo, sMenuItem);
		}
	}

	if(menu.ItemCount == 1)
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "NoPartnerFound", client);
		menu.AddItem("", sMenuItem, ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Partner_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		if(StrEqual(sInfo, "refresh"))
		{
			OpenPartnerMenu(param1);
		}
		else
		{
			int partner = StringToInt(sInfo);

			SendPartnerRequest(param1, partner);
			Shavit_PrintToChat(param1, "%T", "RequestSent", param1);			
		}
	}
	else if(action == MenuAction_Cancel)
	{
		if(gI_LastOpenedMenu[param1] == MENU_PAINT)
		{
			OpenPaintMenu(param1);
		}
		else if(gI_LastOpenedMenu[param1] == MENU_PING)
		{
			OpenPingMenu(param1);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void SendPartnerRequest(int client, int partner)
{
	gI_Partnering[client] = partner;
	gI_Partnering[partner] = client;

	char sName[64];
	GetClientName(client, sName, sizeof(sName));
	char sPartnerName[64];
	GetClientName(partner, sPartnerName, sizeof(sPartnerName));

	char sMenuItem[64];
	char sInfo[8];
	Menu waitingResponseMenu = new Menu(PartnerWaitingResponse_MenuHandler);
	waitingResponseMenu.SetTitle("%T\n ", "ResponseWaitingMenuTitle", client, sPartnerName);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "CancelRequest", client);
	IntToString(partner, sInfo, sizeof(sInfo));
	waitingResponseMenu.AddItem(sInfo, sMenuItem);

	waitingResponseMenu.ExitButton = false;
	waitingResponseMenu.Display(client, MENU_TIME_FOREVER);

	Menu requestMenu = new Menu(PartnerRequest_MenuHandler);
	requestMenu.SetTitle("%T\n ", "ReceivedRequest", partner, sName);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "AcceptRequest", partner);
	FormatEx(sInfo, sizeof(sInfo), "a;%d", client);
	requestMenu.AddItem(sInfo, sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "DeclineRequest", partner);
	FormatEx(sInfo, sizeof(sInfo), "d;%d", client);
	requestMenu.AddItem(sInfo, sMenuItem);

	requestMenu.ExitButton = false;
	requestMenu.Display(partner, MENU_TIME_FOREVER);
}

public int PartnerWaitingResponse_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		int partner = StringToInt(sInfo);

		PartneringResponse(param1, partner, RESPONSE_CANCEL);
	}
	else if(action == MenuAction_Cancel)
	{
		char sInfo[8];
		menu.GetItem(0, sInfo, sizeof(sInfo));
		int partner = StringToInt(sInfo);

		PartneringResponse(param1, partner, RESPONSE_CANCEL);
	}

	return 0;
}

public int PartnerRequest_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		char sExploded[2][8];
		ExplodeString(sInfo, ";", sExploded, 2, 8);

		int partner = StringToInt(sExploded[1]);

		if(StrEqual(sExploded[0], "a"))
		{
			PartneringResponse(param1, partner, RESPONSE_ACCEPT);
		}
		else if(StrEqual(sExploded[0], "d"))
		{
			PartneringResponse(param1, partner, RESPONSE_DECLINE);
		}
	}
	else if(action == MenuAction_Cancel)
	{
		char sInfo[16];
		menu.GetItem(0, sInfo, sizeof(sInfo));

		char sExploded[2][8];
		ExplodeString(sInfo, ";", sExploded, 2, 8);

		int partner = StringToInt(sExploded[1]);

		PartneringResponse(param1, partner, RESPONSE_DECLINE);
	}

	return 0;
}

public void PartneringResponse(int client, int partner, int status)
{
	Menu menu = new Menu(PartnerResponse_MenuHandler);
	menu.ExitBackButton = false;
	menu.ExitButton = false;

	char sName[64];
	GetClientName(client, sName, sizeof(sName));
	char sPartnerName[64];
	GetClientName(partner, sPartnerName, sizeof(sPartnerName));

	if(status == RESPONSE_ACCEPT) // accept
	{
		menu.SetTitle("%T\n%T\n ", "RequestAccepted", partner, sName, "MenuAutoClose", partner);

		gI_Partner[client] = partner;
		gI_Partner[partner] = client;

		Shavit_PrintToChat(client, "%T", "Partnered", client, gS_ChatStrings.sVariable2, sPartnerName, gS_ChatStrings.sText);
		Shavit_PrintToChat(partner, "%T", "Partnered", partner, gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText);
	}
	else 
	{
		if(status == RESPONSE_DECLINE) // decline
		{
			menu.SetTitle("%T\n%T\n ", "RequestDeclined", partner, sName, "MenuAutoClose", partner);
		}
		else if(status == RESPONSE_CANCEL) // cancel
		{
			menu.SetTitle("%T\n%T\n ", "RequestCanceled", partner, sName, "MenuAutoClose", partner);
		}
		else
		{
		menu.SetTitle("%T\n%T\n ", "RequestAborted", partner, sName, "MenuAutoClose", partner);			
		}
	}

	char sMenuItem[64];
	FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "MenuClose", partner);
	menu.AddItem("close", sMenuItem);

	menu.Display(partner, 10);

	gI_Partnering[client] = 0;
	gI_Partnering[partner] = 0;
}

public int PartnerResponse_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		// nothing here
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_PaintSize(int client, int args)
{
	OpenPaintSizeMenu(client);

	return Plugin_Continue;
}

public Action Command_PaintMode(int client, int args)
{
	if(gB_IsPainting[client])
	{
		Shavit_PrintToChat(client, "%T", "PaintModeChangeError", client);
	}
	else
	{
		gB_PaintMode[client] = !gB_PaintMode[client];

		char sValue[8];
		IntToString(view_as<int>(gB_PaintMode[client]), sValue, sizeof(sValue));
		gH_PlayerPaintMode.Set(client, sValue);

		Shavit_PrintToChat(client, "%T: %T", "PaintMode", client, gB_PaintMode[client] ? "ModeSingle":"ModeContinuous", client);
	}

	return Plugin_Continue;
}

public Action Command_PaintErase(int client, int args)
{
	gB_ErasePaint[client] = !gB_ErasePaint[client];
	Shavit_PrintToChat(client, "%T: %T", "PaintEraser", client, gB_ErasePaint[client] ? "EraserOn":"EraserOff", client);

	return Plugin_Continue;
}

void OpenPaintSizeMenu(int client, int item = 0)
{
	Menu menu = new Menu(PaintSize_MenuHandler);

	menu.SetTitle("%T\n ", "PaintSizeMenuTitle", client);

	char sMenuItem[64];
	for (int i = 0; i < sizeof(gS_PaintSizes); i++)
	{
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", gS_PaintSizes[i][0], client);
		menu.AddItem("", sMenuItem, gI_PlayerPaintSize[client] == i ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int PaintSize_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		gI_PlayerPaintSize[param1] = param2;
		SetClientCookieInt(param1, gH_PlayerPaintSize, gI_PlayerPaintSize[param1]);

		OpenPaintSizeMenu(param1, GetMenuSelectionPosition());
	}
	else if(action == MenuAction_Cancel)
	{
		OpenPaintOptionMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int CreatePingEffect(int client, float pos[3], float rotation[3], int color[4], float duration)
{
	int iEntity = CreateEntityByName("prop_dynamic_override");

	gI_PlayerPing[client] = iEntity;
	gI_PingEntity[iEntity] = client;

	SetEntityModel(iEntity, PING_MODEL_PATH);
	DispatchSpawn(iEntity);
	ActivateEntity(iEntity);
	SetEntPropVector(iEntity, Prop_Data, "m_angRotation", rotation);
	SetEntityRenderMode(iEntity, RENDER_TRANSALPHA);
	SetEntityRenderColor(iEntity, color[0], color[1], color[2], color[3]);
	SDKHook(iEntity, SDKHook_SetTransmit, Hook_SetPingTransmit);
	TeleportEntity(iEntity, pos, NULL_VECTOR, NULL_VECTOR);

	if(gB_PingSound[client])
	{
		EmitSoundToClient(client, PING_SOUND_PATH);		
	}

	if(gI_Partner[client] > 0 && gB_PingSound[gI_Partner[client]])
	{
		EmitSoundToClient(gI_Partner[client], PING_SOUND_PATH);	
	}

	gI_PlayerLastPing[client] = GetGameTickCount();

	if(!gB_PingDuration[client])
	{
		gH_PingTimer[client] = CreateTimer(duration, Timer_RemovePingEffect, iEntity, TIMER_FLAG_NO_MAPCHANGE);		
	}

	return iEntity;
}

public Action Hook_SetPingTransmit(int entity, int other)
{
	int target = other;
	int owner = gI_PingEntity[entity];

	if(IsClientObserver(other))
	{
		int iObserverMode = GetEntProp(other, Prop_Send, "m_iObserverMode");

		if (iObserverMode >= 3 && iObserverMode <= 7)
		{
			int iTarget = GetEntPropEnt(other, Prop_Send, "m_hObserverTarget");

			if (IsValidEntity(target))
			{
				target = iTarget;
			}
		}
	}

	if(owner > 0 && gB_PingToAll[owner])
	{
		return Plugin_Continue;
	}

	if(target == owner || target == gI_Partner[owner])
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

public Action Timer_RemovePingEffect(Handle timer, int entity)
{
	int client = gI_PingEntity[entity];

	gH_PingTimer[client] = null;

	if(client == -1 || gI_PlayerPing[client] != entity)
	{
		return Plugin_Stop;
	}

	RemovePingEntity(entity);	

	return Plugin_Stop;
}

public void RemovePing(int client)
{
	if(gI_PlayerPing[client] > 0)	
	{
		RemovePingEntity(gI_PlayerPing[client]);
	}

	if(gH_PingTimer[client] != null)
	{
		RemovePingTimer(client);
	}
}

public void RemovePingEntity(int entity)
{
	AcceptEntityInput(entity, "Kill");
	gI_PlayerPing[gI_PingEntity[entity]] = 0;
	gI_PingEntity[entity] = -1;
}

public void RemovePingTimer(int client)
{
	if(gH_PingTimer[client] != null)
	{
		delete gH_PingTimer[client];
	}

	delete gH_PingTimer[client];
}

void AddPaint(int client, float pos[3], int paint = 0, int size = 0)
{
	if(paint == 0)
	{
		paint = GetRandomInt(1, sizeof(gS_PaintColors) - 1);
	}

	if(gB_PaintToAll[client])
	{
		TE_SetupWorldDecal(pos, gI_Sprites[paint - 1][size]);
		TE_SendToAll();
	}
	else
	{
		TE_SetupWorldDecal(pos, gI_Sprites[paint - 1][size]);
		TE_SendToClient(client);
		
		if(gI_Partner[client] != 0)
		{
			TE_SetupWorldDecal(pos, gI_Sprites[paint - 1][size]);
			TE_SendToClient(gI_Partner[client]);
		}		
	}
}

void EracePaint(int client, float pos[3], int size = 0)
{
	TE_SetupWorldDecal(pos, gI_Eraser[size]);
	TE_SendToClient(client);

	if(gI_Partner[client] != 0)
	{
		TE_SetupWorldDecal(pos, gI_Eraser[size]);
		TE_SendToClient(gI_Partner[client]);
	}
}

int PrecachePaint(char[] filename)
{
	char tmpPath[PLATFORM_MAX_PATH];
	Format(tmpPath, sizeof(tmpPath), "materials/%s", filename);
	AddFileToDownloadsTable(tmpPath);

	return PrecacheDecal(filename, true);
}

stock void TE_SetupWorldDecal(const float vecOrigin[3], int index)
{
	TE_Start("World Decal");
	TE_WriteVector("m_vecOrigin", vecOrigin);
	TE_WriteNum("m_nIndex", index);
}

stock bool TraceEye(int client, float pos[3])
{
	float vAngles[3], vOrigin[3];
	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);

	TR_TraceRayFilter(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

	if (TR_DidHit())
	{
		TR_GetEndPosition(pos);
		return true;
	}

	return false;
}

stock void CaculatePlaneRotation(float rotation[3])
{
	TR_GetPlaneNormal(null, rotation);
	
	GetVectorAngles(rotation, rotation);

	rotation[0] -= 270.0;
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask)
{
	return (entity > MaxClients || !entity);
}

stock bool CheckClientAccess(int client)
{
    char sFlag[16];
    gCV_AccessFlag.GetString(sFlag, sizeof(sFlag));

    int flags = ReadFlagString(sFlag);
    
    if((GetUserFlagBits(client) & flags) == flags)
    {
        return true;
    }

    return false;
}

stock void GetPingColor(int index, int color[4])
{
	char sExploded[4][8];
	ExplodeString(gS_PingColors[index][1], ";", sExploded, 4, 8);

	for (int i = 0; i < 4; i++)
	{
		color[i] = StringToInt(sExploded[i]);
	}
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

stock void AddFilesToDownloadsTable()
{
	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, sizeof(sPath), "sound/%s", PING_SOUND_PATH);

	AddFileToDownloadsTable(sPath);
	AddFileToDownloadsTable("materials/decals/paint/paint_decal.vtf");
	AddFileToDownloadsTable("materials/decals/paint/paint_eraser.vtf");
	AddFileToDownloadsTable("materials/expert_zone/pingtool/circle_arrow.vtf");
	AddFileToDownloadsTable("materials/expert_zone/pingtool/circle_arrow.vmt");
	AddFileToDownloadsTable("materials/expert_zone/pingtool/circle_point.vtf");
	AddFileToDownloadsTable("materials/expert_zone/pingtool/circle_point.vmt");
	AddFileToDownloadsTable("materials/expert_zone/pingtool/grad.vtf");
	AddFileToDownloadsTable("materials/expert_zone/pingtool/grad.vmt");
	AddFileToDownloadsTable("models/expert_zone/pingtool/pingtool.dx80.vtx");
	AddFileToDownloadsTable("models/expert_zone/pingtool/pingtool.dx90.vtx");
	AddFileToDownloadsTable(PING_MODEL_PATH);
	AddFileToDownloadsTable("models/expert_zone/pingtool/pingtool.sw.vtx");
	AddFileToDownloadsTable("models/expert_zone/pingtool/pingtool.vvd");
	PrecacheModel(PING_MODEL_PATH);
	PrecacheSound(PING_SOUND_PATH);
}
