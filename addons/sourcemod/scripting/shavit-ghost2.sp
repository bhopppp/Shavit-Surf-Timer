#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <cstrike>
#include <clientprefs>
#include <closestpos>
#include <convar_class>

#include <shavit/core>
#include <shavit/replay-playback>
#include <shavit/zones>
#include <shavit/wr>
#include <shavit/checkpoints>
#include <shavit/replay-stocks.sp>

#pragma semicolon 1
#pragma newdecls required

#define GhostMode_Race 0
#define GhostMode_Route 1
#define	GhostMode_Guide 2
#define GhostMode_Size 3

#define RouteWidth_Thin 1
#define	RouteWidth_Normal 2
#define RouteWidth_Thick 3
#define RouteWidth_UltraThick 4
#define RouteWidth_Size 5

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

int gI_Colors[11][4] = 
{
	{0,0,0, 255},
	{255, 255, 255, 255},	//White
	{255, 0, 0, 255},		//Red
	{0, 255, 0, 255},		//Green
	{150, 255, 0, 255},		//Lime
	{40, 150, 255, 255},	//Blue
	{0, 255, 255, 255},		//Cyan
	{255, 215, 0, 255},		//Yellow
	{219, 72, 16, 255},		//Orange
	{128, 0, 128, 255},		//Purple
	{255, 70, 60, 255}		//LightRed
};		

char gS_GhostModeName[3][16] =
{
	"GhostModeRace",
	"GhostModeRoute",
	"GhostModeGuide",
};

enum struct ghost_info_t
{
    ArrayList aFrames;
    ClosestPos hClosestPos;
    int iPreFrames;
    int iPostFrames;
    int iFrameCount;
	float fTime;
}

//frames & info
ghost_info_t gA_GhostInfo[TRACKS_SIZE][STYLE_LIMIT][MAX_STAGES];

//style stuffs
stylestrings_t gS_StyleStrings[STYLE_LIMIT];
int gI_Styles;

//variables
int gI_Tickrate;
int gI_DrawRouteInterval;
int gI_MaxRecaculateFrameDiff;
int gI_RouteFramesAhead;
int gI_GuideFramesAhead;
int gI_TimeCompensation;
int gI_DrawFrameOffsetDivision;

// client stuffs
int gI_ClientTicks[MAXPLAYERS + 1];
int gI_ClientPrevFrame[MAXPLAYERS + 1];
bool gB_GhostFnished[MAXPLAYERS + 1];

int gI_LastFrameDrawDifference[MAXPLAYERS + 1];

// client settings
bool gB_Ghost[MAXPLAYERS + 1];
bool gB_StageGhost[MAXPLAYERS + 1];
bool gB_DrawBox[MAXPLAYERS + 1];

int gGM_GhostMode[MAXPLAYERS + 1];
int gI_GhostRouteColor[MAXPLAYERS + 1];
int gI_GhostBoxColor[MAXPLAYERS + 1];
int gI_GhostStyle[MAXPLAYERS + 1];
bool gB_GhostIgnorez[MAXPLAYERS + 1];

int gI_TELimitData;
Address TELimitAddress;

float gF_RouteWidth[MAXPLAYERS + 1];
float gF_GhostBoxSize[MAXPLAYERS + 1];

// cookies
Handle gH_GhostCookie;
Handle gH_GhostModeCookie;
Handle gH_GhostRouteColorCookie;
Handle gH_GhostRouteWidthCookie;
Handle gH_GhostDrawBoxCookie;
Handle gH_GhostBoxColorCookie;
Handle gH_GhostBoxSizeCookie;
Handle gH_GhostIgnorezCookie;

//Convars
Convar gCV_MaxFrameDistance = null;
Convar gCV_GuideFramesAhead = null;
Convar gCV_RecaculateFrameDiff = null;
Convar gCV_RouteDrawInterval = null;
Convar gCV_RouteFramesAhead = null;
Convar gCV_RouteDrawSkipFrames = null;

int gI_Sprite;
int gI_SpriteIgnorez;
bool gB_Late;
bool gB_Linux;
EngineVersion gEV_Type = Engine_Unknown;


public Plugin myinfo = 
{
	name = "[shavit-surf] Ghost",
	author = "KikI",
	description = "Draw record path with multiple modes.",
	version = "2.0.0",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;
	return APLRes_Success;
}

public void OnPluginStart() 
{
	gEV_Type = GetEngineVersion();

	RegConsoleCmd("sm_ghost", Command_Ghost, "Shows ghost menu to client.");
	RegConsoleCmd("sm_toggleghost", Command_ToggleGhost, "Toggle ghost usage.");
	RegConsoleCmd("sm_toggleignorez", Command_ToggleIgnorez, "Toggle ghost ignorez.");

	gH_GhostCookie = RegClientCookie("ghost_enable", "Ghost enable", CookieAccess_Public);
	gH_GhostModeCookie = RegClientCookie("ghost_mode", "Ghost mode", CookieAccess_Public);
	gH_GhostRouteWidthCookie = RegClientCookie("ghost_routewidth", "Ghost route width", CookieAccess_Public);
	gH_GhostRouteColorCookie = RegClientCookie("ghost_routecolor", "Ghost routecolor", CookieAccess_Public);
	gH_GhostDrawBoxCookie = RegClientCookie("ghost_drawbox", "Ghost drawbox", CookieAccess_Public);
	gH_GhostBoxColorCookie = RegClientCookie("ghost_boxcolor", "Ghost boxcolor", CookieAccess_Public);
	gH_GhostBoxSizeCookie = RegClientCookie("ghost_boxsize", "Ghost boxsize", CookieAccess_Public);
	gH_GhostIgnorezCookie = RegClientCookie("ghost_ignorez", "Ghost ignorez", CookieAccess_Public);

	gCV_GuideFramesAhead = new Convar("shavit_ghost_guide_framesahead", "1.5", "How many seconds of frames ahead should be drawn to client in Guide mode", 0, true, 0.1, true, 4.0);
	gCV_RecaculateFrameDiff = new Convar("shavit_ghost_guide_recaculateframediff", "3.0", "How many seconds of frame difference should recalculating the next closest frame", 0, true, 2.0, true, 5.0);
	gCV_RouteDrawInterval = new Convar("shavit_ghost_route_drawinterval", "0.8", "The interval (in seconds) between route draws", 0, true, 0.5, true, 3.0);
	gCV_RouteFramesAhead = new Convar("shavit_ghost_route_framesahead", "5.0", "How many seconds of frames ahead should be drawn to client in Route mode", 0, true, 1.0, true, 10.0);
	gCV_MaxFrameDistance = new Convar("shavit_ghost_route_maxframedistance", "1000.0", "Maximum distance between frames before skipping beam drawing", 0, true, 50.0, false, 0.0);
	gCV_RouteDrawSkipFrames = new Convar("shavit_ghost_route_skipframes", "5", "Number of frames to skip between route draws to optimize performance\n(higher = better performance but less smooth route)", 0, true, 1.0, true, 10.0);

	gCV_GuideFramesAhead.AddChangeHook(OnConVarChanged);
	gCV_RecaculateFrameDiff.AddChangeHook(OnConVarChanged);
	gCV_RouteDrawInterval.AddChangeHook(OnConVarChanged);
	gCV_RouteFramesAhead.AddChangeHook(OnConVarChanged);

	Convar.AutoExecConfig();

	LoadDHooks();

	LoadTranslations("shavit-ghost2.phrases");

	gI_Tickrate = RoundToNearest(1.0 / GetTickInterval());
	gI_TimeCompensation = gI_Tickrate / 10;

	if(LibraryExists("shavit-replay-playback"))
	{
		Shavit_OnReplaysLoaded();
		Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount());
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

void LoadDHooks()
{
	GameData gamedata = new GameData("shavit.games");

	if (gamedata == null)
	{
		SetFailState("Failed to load shavit gamedata");
	}

	gB_Linux = (gamedata.GetOffset("OS") == 2);

	gEV_Type = GetEngineVersion();

	if(gEV_Type == Engine_CSS)
	{
		//TELimit
		TELimitAddress = GameConfGetAddress(gamedata, "TELimit");

		if(TELimitAddress == Address_Null)
		{
			SetFailState("Failed to get address for TELimit");
		}
		
		gI_TELimitData = LoadFromAddress(TELimitAddress, NumberType_Int8);
		
		if(gB_Linux)
		{
			StoreToAddress(TELimitAddress, 0x02, NumberType_Int8);
		}
		else
		{
			StoreToAddress(TELimitAddress, 0xFF, NumberType_Int8);
		}	
	}

	delete gamedata;
}

public void OnPluginEnd()
{
	if(TELimitAddress == Address_Null)
	{
		return;		
	}
	
	StoreToAddress(TELimitAddress, gI_TELimitData, NumberType_Int8);
}

public void OnClientConnected(int client)
{
	gB_StageGhost[client] = false;
	gI_GhostStyle[client] = Shavit_GetBhopStyle(client);
}

public void OnConfigsExecuted() 
{
	gI_Sprite = PrecacheModel("sprites/laserbeam.vmt");
	gI_SpriteIgnorez = PrecacheModel("shavit/laserbeam_ignorez.vmt");

	gI_DrawRouteInterval = RoundToNearest(gCV_RouteDrawInterval.FloatValue * gI_Tickrate);
	gI_MaxRecaculateFrameDiff = RoundToNearest(gCV_RecaculateFrameDiff.FloatValue * gI_Tickrate);
	gI_RouteFramesAhead = RoundToNearest(gCV_RouteFramesAhead.FloatValue * gI_Tickrate);
	gI_GuideFramesAhead = RoundToNearest(gCV_GuideFramesAhead.FloatValue * gI_Tickrate);
	gI_DrawFrameOffsetDivision = gI_GuideFramesAhead / 2;	
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(StrEqual(oldValue, newValue))
	{
		return;
	}

	if(convar == gCV_RouteDrawInterval)
	{
		gI_DrawRouteInterval = RoundToNearest(gCV_RouteDrawInterval.FloatValue * gI_Tickrate);
	}
	else if(convar == gCV_RecaculateFrameDiff)
	{
		gI_MaxRecaculateFrameDiff = RoundToNearest(gCV_RecaculateFrameDiff.FloatValue * gI_Tickrate);
	}
	else if(convar == gCV_RouteFramesAhead)
	{
		gI_RouteFramesAhead = RoundToNearest(gCV_RouteFramesAhead.FloatValue * gI_Tickrate);
	}
	else if(convar == gCV_GuideFramesAhead)
	{
		gI_GuideFramesAhead = RoundToNearest(gCV_GuideFramesAhead.FloatValue * gI_Tickrate);
		gI_DrawFrameOffsetDivision = gI_GuideFramesAhead / 2;				
	}
}

public void OnClientCookiesCached(int client)
{
	if (!GetClientCookieBool(client, gH_GhostCookie, gB_Ghost[client]))
	{
		gB_Ghost[client] = false;
		SetClientCookieBool(client, gH_GhostCookie, false);
	}

	if (!GetClientCookieInt(client, gH_GhostModeCookie, gGM_GhostMode[client]))
	{
		gGM_GhostMode[client] = GhostMode_Guide;
		SetClientCookieInt(client, gH_GhostModeCookie, GhostMode_Guide);
	}

	if (!GetClientCookieBool(client, gH_GhostDrawBoxCookie, gB_DrawBox[client]))
	{
		gB_DrawBox[client] = true;
		SetClientCookieBool(client, gH_GhostDrawBoxCookie, true);
	}

	if (!GetClientCookieInt(client, gH_GhostRouteColorCookie, gI_GhostRouteColor[client]))
	{
		gI_GhostRouteColor[client] = 6;
		SetClientCookieInt(client, gH_GhostRouteColorCookie, 6);
	}

	if (!GetClientCookieFloat(client, gH_GhostRouteWidthCookie, gF_RouteWidth[client]))
	{
		gF_RouteWidth[client] = 1.0;
		SetClientCookieFloat(client, gH_GhostRouteWidthCookie, 1.0);
	}

	if (!GetClientCookieInt(client, gH_GhostBoxColorCookie, gI_GhostBoxColor[client]))
	{
		gI_GhostBoxColor[client] = 1;
		SetClientCookieInt(client, gH_GhostBoxColorCookie, 1);
	}

	if (!GetClientCookieBool(client, gH_GhostIgnorezCookie, gB_GhostIgnorez[client]))
	{
		gB_GhostIgnorez[client] = false;
		SetClientCookieInt(client, gH_GhostIgnorezCookie, false);
	}

	gF_GhostBoxSize[client] = 10.0;
	SetClientCookieFloat(client, gH_GhostBoxSizeCookie, 10.0);

	if (!GetClientCookieFloat(client, gH_GhostBoxSizeCookie, gF_GhostBoxSize[client]))
	{
		gF_GhostBoxSize[client] = 10.0;
		SetClientCookieFloat(client, gH_GhostBoxSizeCookie, 10.0);
	}
}

public Action Command_Ghost(int client, int args) 
{
	if(!IsValidClient2(client)) 
	{
		return Plugin_Handled;
	}

	ShowGhostMenu(client);

	return Plugin_Handled;
}

public Action Command_ToggleGhost(int client, int args) 
{
	if(!IsValidClient2(client)) 
	{
		return Plugin_Handled;
	}

	gB_Ghost[client] = !gB_Ghost[client];
	SetClientCookieBool(client, gH_GhostCookie, gB_Ghost[client]);
	
	if (gGM_GhostMode[client] == GhostMode_Race)
	{
		SynchronizeClientTick(client);				
	}

	Shavit_PrintToChat(client, "Ghost: %s", gB_Ghost[client] ? "enabled":"disabled");

	return Plugin_Handled;
}

public Action Command_ToggleIgnorez(int client, int args) 
{
	if(!IsValidClient2(client)) 
	{
		return Plugin_Handled;
	}

	gB_GhostIgnorez[client] = !gB_GhostIgnorez[client];
	SetClientCookieBool(client, gH_GhostIgnorezCookie, gB_GhostIgnorez[client]);

	Shavit_PrintToChat(client, "Ghost Ignorez: %s", gB_GhostIgnorez[client] ? "enabled":"disabled");

	return Plugin_Handled;
}

public void ShowGhostMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Ghost, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem|MenuAction_Display);
	menu.SetTitle("%T\n ", "GhostMenuTitle", client);

	char sMenu[64];
	FormatEx(sMenu, sizeof(sMenu), "%T", "ToggleGhost", client, gB_Ghost[client] ? "Enabled":"Disabled", client);
	menu.AddItem("toggle", sMenu, ITEMDRAW_DEFAULT);
	
	FormatEx(sMenu, sizeof(sMenu), "%T", "GhostMode", client, gS_GhostModeName[gGM_GhostMode[client]], client);
	menu.AddItem("mode", sMenu, ITEMDRAW_DEFAULT);
	
	int track = Shavit_GetClientTrack(client);
	int stage = track > Track_Main ? 0 : (Shavit_IsOnlyStageMode(client) || gB_StageGhost[client]) ? Shavit_GetClientLastStage(client) : 0;
	
	char sTime[32];
	if(!gA_GhostInfo[track][gI_GhostStyle[client]][stage].aFrames)
	{
		FormatEx(sTime, 32, "N/A");
	}
	else
	{
		FormatSeconds(gA_GhostInfo[track][gI_GhostStyle[client]][stage].fTime, sTime, 32, false, false, true);
	}

	FormatEx(sMenu, sizeof(sMenu), "%T: %s (%s)", "ChangeStyle", client, gS_StyleStrings[gI_GhostStyle[client]].sStyleName, sTime);
	menu.AddItem("style", sMenu, ITEMDRAW_DEFAULT);

	FormatEx(sMenu, sizeof(sMenu), "%T\n ", "StageRoute", client, gB_StageGhost[client] ? "Enabled":"Disabled", client);
	menu.AddItem("stage", sMenu, Shavit_GetStageCount(Track_Main) > 1 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);		

	FormatEx(sMenu, sizeof(sMenu), "%T", "ToggleIgnorez", client, gB_GhostIgnorez[client] ? "Enabled":"Disabled", client);
	menu.AddItem("toggleignorez", sMenu, ITEMDRAW_DEFAULT);

	FormatEx(sMenu, sizeof(sMenu), "%T", "GhostOptions", client);
	menu.AddItem("option", sMenu);

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Ghost(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "toggle", false))
		{
			gB_Ghost[param1] = !gB_Ghost[param1];
			SetClientCookieBool(param1, gH_GhostCookie, gB_Ghost[param1]);
			if (gGM_GhostMode[param1] == GhostMode_Race)
			{
				SynchronizeClientTick(param1);				
			}

			ShowGhostMenu(param1);
		}
		else if(StrEqual(sInfo, "mode", false))
		{
			if (++gGM_GhostMode[param1] >= GhostMode_Size)
			{
				gGM_GhostMode[param1] = GhostMode_Race;
				SynchronizeClientTick(param1);
			}

			SetClientCookieInt(param1, gH_GhostModeCookie, view_as<int>(gGM_GhostMode[param1]));
			
			ShowGhostMenu(param1);
		}
		else if(StrEqual(sInfo, "style", false))
		{
			int iOriginalStyle = gI_GhostStyle[param1];
			int track = Shavit_GetClientTrack(param1);
			int stage = track > Track_Main ? 0 : (Shavit_IsOnlyStageMode(param1) || gB_StageGhost[param1]) ? Shavit_GetClientLastStage(param1) : 0;
			int count = 0;

			do
			{
				if(++gI_GhostStyle[param1] >= gI_Styles)
				{
					gI_GhostStyle[param1] = 0;
				}

				if(++count > gI_Styles)
				{
					gI_GhostStyle[param1] = iOriginalStyle;
					break;
				}
			}
			while(!gA_GhostInfo[track][gI_GhostStyle[param1]][stage].aFrames);

			ShowGhostMenu(param1);
		}
		else if(StrEqual(sInfo, "stage", false))
		{
			gB_StageGhost[param1] = !gB_StageGhost[param1];

			ShowGhostMenu(param1);
		}
		else if(StrEqual(sInfo, "toggleignorez", false))
		{
			gB_GhostIgnorez[param1] = !gB_GhostIgnorez[param1];
			SetClientCookieBool(param1, gH_GhostIgnorezCookie, gB_GhostIgnorez[param1]);

			ShowGhostMenu(param1);
		}
		else if(StrEqual(sInfo, "option", false))
		{
			ShowGhostOptionMenu(param1);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OnMapStart()
{
	AddFileToDownloadsTable("materials/sprites/laserbeam.vtf");
	AddFileToDownloadsTable("materials/sprites/laserbeam.vmt");
	AddFileToDownloadsTable("materials/shavit/laserbeam_ignorez.vmt");
}


public void ShowGhostOptionMenu(int client)
{
	Menu menu = new Menu(MenuHandler_GhostOption);
	menu.SetTitle("%T\n ", "GhostOptionsMenuTitle", client);
	char sMenu[64];
	char sColor[32];
	
	GetColorName(gI_GhostRouteColor[client], sColor, 32);
	FormatEx(sMenu, sizeof(sMenu), "%T: %s\n ", "RouteColor", client, sColor);
	menu.AddItem("routecolor", sMenu, ITEMDRAW_DEFAULT);
	
	FormatEx(sMenu, sizeof(sMenu), "＋＋%T\n %T", "RouteWidth", client, "CurrentWidth", client, gF_RouteWidth[client]);
	menu.AddItem("plusroutewidth", sMenu, gF_RouteWidth[client] >= 5.0 ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

	FormatEx(sMenu, sizeof(sMenu), "－－%T\n ", "RouteWidth", client);
	menu.AddItem("minusroutewidth", sMenu, gF_RouteWidth[client] <= 0.1 ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	
	FormatEx(sMenu, sizeof(sMenu), "%T", "JumpMarkerDraw", client, gB_DrawBox[client] ? "Enabled":"Disabled", client);
	menu.AddItem("drawbox", sMenu, ITEMDRAW_DEFAULT);

	GetColorName(gI_GhostBoxColor[client], sColor, 32);
	FormatEx(sMenu, sizeof(sMenu), "%T: %s\n ", "JumpMarkerColor", client, sColor);
	menu.AddItem("boxcolor", sMenu, ITEMDRAW_DEFAULT);

	FormatEx(sMenu, sizeof(sMenu), "＋＋%T\n %T", "JumpMarkerSize", client, "CurrentJumpMarkerSize", client, gF_GhostBoxSize[client]);
	menu.AddItem("plusboxsize", sMenu, gF_GhostBoxSize[client] >= 15.0 ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

	FormatEx(sMenu, sizeof(sMenu), "－－%T", "JumpMarkerSize", client);
	menu.AddItem("minusboxsize", sMenu, gF_GhostBoxSize[client] <= 5.0 ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_GhostOption(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "routecolor", false))
		{
			gI_GhostRouteColor[param1] = (gI_GhostRouteColor[param1] % 10) + 1;
			SetClientCookieInt(param1, gH_GhostRouteColorCookie, gI_GhostRouteColor[param1]);
			ShowGhostOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "plusroutewidth", false))
		{
			gF_RouteWidth[param1] += 0.1;
			SetClientCookieFloat(param1, gH_GhostRouteWidthCookie, gF_RouteWidth[param1]);
			ShowGhostOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "minusroutewidth", false))
		{
			gF_RouteWidth[param1] -= 0.1;
			SetClientCookieFloat(param1, gH_GhostRouteWidthCookie, gF_RouteWidth[param1]);
			ShowGhostOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "drawbox", false))
		{
			gB_DrawBox[param1] = !gB_DrawBox[param1];
			SetClientCookieBool(param1, gH_GhostDrawBoxCookie, gB_DrawBox[param1]);
			ShowGhostOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "boxcolor", false))
		{
			gI_GhostBoxColor[param1] = (gI_GhostBoxColor[param1] % 10) + 1;
			SetClientCookieInt(param1, gH_GhostBoxColorCookie, gI_GhostBoxColor[param1]);
			ShowGhostOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "plusboxsize", false))
		{
			gF_GhostBoxSize[param1] += 0.5;
			SetClientCookieFloat(param1, gH_GhostBoxSizeCookie, gF_GhostBoxSize[param1]);
			ShowGhostOptionMenu(param1);
		}
		else if(StrEqual(sInfo, "minusboxsize", false))
		{
			gF_GhostBoxSize[param1] -= 0.5;
			SetClientCookieFloat(param1, gH_GhostBoxSizeCookie, gF_GhostBoxSize[param1]);
			ShowGhostOptionMenu(param1);
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowGhostMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void ResetGhostInfo(int track, int style, int stage)
{
	gA_GhostInfo[track][style][stage].iPreFrames = 0;
	gA_GhostInfo[track][style][stage].iPostFrames = 0;
	gA_GhostInfo[track][style][stage].iFrameCount = 0;
	gA_GhostInfo[track][style][stage].fTime = 0.0;
	delete gA_GhostInfo[track][style][stage].aFrames;
	delete gA_GhostInfo[track][style][stage].hClosestPos;
}

public bool LoadGhostInfo(int track, int style, int stage)
{
	float length = Shavit_GetReplayLength(style, track, stage);
	if (length == 0.0)
	{
		return false;
	}

	gA_GhostInfo[track][style][stage].aFrames = Shavit_GetReplayFrames(style, track, stage);

	if(!gA_GhostInfo[track][style][stage].aFrames)
	{
		return false;	
	}

	gA_GhostInfo[track][style][stage].iPreFrames = Shavit_GetReplayPreFrames(style, track, stage);
	gA_GhostInfo[track][style][stage].iPostFrames = Shavit_GetReplayPostFrames(style, track, stage);
	gA_GhostInfo[track][style][stage].iFrameCount = Shavit_GetReplayFrameCount(style, track, stage);
	gA_GhostInfo[track][style][stage].fTime = length;
	gA_GhostInfo[track][style][stage].hClosestPos = new ClosestPos(gA_GhostInfo[track][style][stage].aFrames, 0, 0, gA_GhostInfo[track][style][stage].aFrames.Length - gA_GhostInfo[track][style][stage].iPostFrames);

	return true;
}

public void DefaultLoadGhostInfo()
{
	for (int i = 0; i < TRACKS_SIZE; i++)
	{
		for(int j = 0; j < STYLE_LIMIT; j ++)
		{
			ResetGhostInfo(i, j, 0);
			LoadGhostInfo(i, j, 0);
		}
	}
		
	for (int k = 1; k < MAX_STAGES; k++)
	{
		for(int v = 0; v < STYLE_LIMIT; v ++)
		{
			ResetGhostInfo(Track_Main, v, k);
			LoadGhostInfo(Track_Main, v, k);
		}
	}
}

public void Shavit_OnReplaysLoaded() 
{
	DefaultLoadGhostInfo();
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	gI_Styles = styles;

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleStringsStruct(i, gS_StyleStrings[i]);
	}
}

public void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, int stage, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong, bool iscopy, const char[] replaypath, ArrayList frames, ArrayList offsets, int preframes, int postframes, const char[] name)
{
	if(isbestreplay && !istoolong)
	{
		ResetGhostInfo(track, style, stage);
		gA_GhostInfo[track][style][stage].aFrames = view_as<ArrayList>(CloneHandle(frames));
		gA_GhostInfo[track][style][stage].iPreFrames = preframes;
		gA_GhostInfo[track][style][stage].iPostFrames = postframes;
		gA_GhostInfo[track][style][stage].iFrameCount = frames.Length - preframes - postframes;
		gA_GhostInfo[track][style][stage].fTime = time;
		gA_GhostInfo[track][style][stage].hClosestPos = new ClosestPos(frames, 0, gA_GhostInfo[track][style][stage].iPreFrames, gA_GhostInfo[track][style][stage].iFrameCount);	
	}
}

public Action Shavit_OnStart(int client)
{
	int style = gI_GhostStyle[client];
	int track = Shavit_GetClientTrack(client);
	int stage = track > Track_Main ? 0 : (Shavit_IsOnlyStageMode(client) || gB_StageGhost[client]) ? Shavit_GetClientLastStage(client) : 0;

	gB_GhostFnished[client] = false;

	gI_ClientTicks[client] = gA_GhostInfo[track][style][stage].iPreFrames + gI_TimeCompensation;
	return Plugin_Continue;
}

public void Shavit_OnCheckpointCacheLoaded(int client, cp_cache_t cache, int index)
{
	int track = cache.aSnapshot.iTimerTrack;
	int style = gI_GhostStyle[client];
	int stage = track > Track_Main ? 0 : (cache.aSnapshot.bOnlyStageMode || gB_StageGhost[client]) ? cache.aSnapshot.iLastStage : 0;
	
	gI_ClientTicks[client] = cache.aSnapshot.iFullTicks + gA_GhostInfo[track][style][stage].iPreFrames;
	gB_GhostFnished[client] = gI_ClientTicks[client] >= (gA_GhostInfo[track][style][stage].iFrameCount + gA_GhostInfo[track][style][stage].iPreFrames);
}


public void SynchronizeClientTick(int client)
{
	int style = gI_GhostStyle[client];
	int track = Shavit_GetClientTrack(client);
	int stage = track > Track_Main ? 0 : (Shavit_IsOnlyStageMode(client) || gB_StageGhost[client]) ? Shavit_GetClientLastStage(client) : 0;

	timer_snapshot_t snapshot;
	Shavit_SaveSnapshot(client, snapshot, sizeof(snapshot));

	gI_ClientTicks[client] = snapshot.iFullTicks + gA_GhostInfo[track][style][stage].iPreFrames;

	gB_GhostFnished[client] = gI_ClientTicks[client] >= (gA_GhostInfo[track][style][stage].iFrameCount + gA_GhostInfo[track][style][stage].iPreFrames);
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if(!IsValidClient2(client, true) || !gB_Ghost[client]) 
	{
		return;
	}

	int style = gI_GhostStyle[client];
	int track = Shavit_GetClientTrack(client);
	int stage = track > Track_Main ? 0 : (Shavit_IsOnlyStageMode(client) || gB_StageGhost[client]) ? Shavit_GetClientLastStage(client) : 0;

	ArrayList info = gA_GhostInfo[track][style][stage].aFrames;
	
	if(!info) 
	{
		return;	
	}

	frame_t curFrame, prevFrame, prevDrawFrame;

	if(gGM_GhostMode[client] == GhostMode_Race)
	{
		if(gB_GhostFnished[client])
		{
			return;
		}

		if(Shavit_GetTimerStatus(client) != Timer_Running || Shavit_GetClientTime(client) < 0.1)
		{
			return;
		}

		if(++gI_ClientTicks[client] >= (gA_GhostInfo[track][style][stage].iFrameCount + gA_GhostInfo[track][style][stage].iPreFrames))
		{
			gB_GhostFnished[client] = true;
			return;
		}
		
		info.GetArray(gI_ClientTicks[client], curFrame, sizeof(frame_t));
		info.GetArray(gI_ClientTicks[client] - 1, prevFrame, sizeof(frame_t));

		DrawBeam(client, prevFrame.pos, curFrame.pos, 0.7, gF_RouteWidth[client], gF_RouteWidth[client], gI_Colors[gI_GhostRouteColor[client]], 0.0, 0);

		if(gB_DrawBox[client] && (!(curFrame.flags & FL_ONGROUND) && prevFrame.flags & FL_ONGROUND))
		{
			DrawBox(client, prevFrame.pos, gF_GhostBoxSize[client], gI_Colors[gI_GhostBoxColor[client]]);
		}
	}
	else if(gGM_GhostMode[client] == GhostMode_Route)
	{
		if (cmdnum % gI_DrawRouteInterval != 0)
		{
			return;
		}

		float clientPos[3];
		GetClientAbsOrigin(client, clientPos);

		int iClosestFrame = Max(1, (gA_GhostInfo[track][style][stage].hClosestPos.Find(clientPos) - 10));
		int iEndFrame = Min(info.Length, iClosestFrame + gI_RouteFramesAhead);

		info.GetArray(iClosestFrame, prevFrame, sizeof(frame_t));
		prevDrawFrame = prevFrame;

		for(int i = iClosestFrame + 1; i < iEndFrame; i++)
		{
			info.GetArray(i, curFrame, sizeof(frame_t));

			if(GetVectorDistance(prevDrawFrame.pos, curFrame.pos) > gCV_MaxFrameDistance.FloatValue)
			{
				prevFrame = curFrame;

				continue;
			}

			bool bFrameOnGround = !(curFrame.flags & FL_ONGROUND) && (prevFrame.flags & FL_ONGROUND);
			
			if(bFrameOnGround && gB_DrawBox[client])
			{
				DrawBox(client, prevFrame.pos, gF_GhostBoxSize[client], gI_Colors[gI_GhostBoxColor[client]]);					

				// Draw beams between previous drawn frames to jump mark
				DrawBeam(client, prevDrawFrame.pos, prevFrame.pos, gCV_RouteDrawInterval.FloatValue, gF_RouteWidth[client], gF_RouteWidth[client], gI_Colors[gI_GhostRouteColor[client]], 0.0, 0);
				
				prevDrawFrame = prevFrame;
				prevFrame = curFrame;
			}
			else if (i % gCV_RouteDrawSkipFrames.IntValue != 0)
			{
				prevFrame = curFrame;

				continue;
			}
			else
			{
				DrawBeam(client, prevDrawFrame.pos, curFrame.pos, gCV_RouteDrawInterval.FloatValue, gF_RouteWidth[client], gF_RouteWidth[client], gI_Colors[gI_GhostRouteColor[client]], 0.0, 0);

				prevFrame = curFrame;
				prevDrawFrame = curFrame;
			}
		}
	}
	else if(gGM_GhostMode[client] == GhostMode_Guide)	// code from shavit-myroute
	{
		float clientPos[3];
		GetClientAbsOrigin(client, clientPos);

		int iClosestFrame = gA_GhostInfo[track][style][stage].hClosestPos.Find(clientPos);
		
		//Client isn't moving, so there's no need to redraw redundant frames
		if(iClosestFrame == gI_ClientPrevFrame[client])
		{
			gI_ClientPrevFrame[client] = iClosestFrame;
			return;
		}

		int iClosestFrameDiff = iClosestFrame - gI_ClientPrevFrame[client];
		int iOriginalClosestFrame = iClosestFrame;
		int iDrawFrameOffset = 1;
		
		if(Abs(iClosestFrameDiff) > gI_MaxRecaculateFrameDiff)
		{
			// closest frame has great diff between previous frame, assign new closest frame as previous frame.
			gI_ClientPrevFrame[client] = iClosestFrame;
		}
		else if(iClosestFrameDiff > 1)
		{
			// fill missing frames when client move too fast
			iDrawFrameOffset = RoundToCeil(float(gI_LastFrameDrawDifference[client]) / gI_DrawFrameOffsetDivision);
			iClosestFrame = gI_ClientPrevFrame[client] + iDrawFrameOffset;
		}

		gI_ClientPrevFrame[client] = iClosestFrame;

		if(iClosestFrameDiff < 0)	// dont draw if player go backward
		{
			return;
		}

		int iMaxFrames;
		
		if(iClosestFrameDiff < gA_GhostInfo[track][style][stage].iPreFrames)
		{
			//draw closer frames ahead in startzone which can shows preframes to clients
			iMaxFrames = iClosestFrame + gI_GuideFramesAhead / 2;
		}
		else
		{
			iMaxFrames = iClosestFrame + gI_GuideFramesAhead;
		}

		gI_LastFrameDrawDifference[client] = gI_GuideFramesAhead - iMaxFrames + iOriginalClosestFrame;

		if(iClosestFrame >= info.Length)
		{
			return;
		}
		else if(iMaxFrames >= info.Length)
		{
			iMaxFrames = info.Length - 2;
		}

		int iPrevFrame = iMaxFrames <= iDrawFrameOffset ? 0 : iMaxFrames - iDrawFrameOffset;

		for (int i = iPrevFrame; i < iMaxFrames; i++)
		{
			info.GetArray(i + 1, curFrame, sizeof(frame_t));
			info.GetArray(i, prevFrame, sizeof(frame_t));

			if(GetVectorDistance(prevFrame.pos, curFrame.pos) > gCV_MaxFrameDistance.FloatValue)
			{
				continue;
			}

			if(gB_DrawBox[client] && (!(curFrame.flags & FL_ONGROUND) && prevFrame.flags & FL_ONGROUND))
			{
				DrawBox(client, prevFrame.pos, gF_GhostBoxSize[client], gI_Colors[gI_GhostBoxColor[client]]);
			}

			DrawBeam(client, prevFrame.pos, curFrame.pos, 1.0, gF_RouteWidth[client], gF_RouteWidth[client], gI_Colors[gI_GhostRouteColor[client]], 0.0, 0);
		}
	}

	return;	
}

void DrawBox(int client, float pos[3], float size, int color[4]) 
{
	float square[4][3];

	square[0][0] = pos[0] - size;
	square[0][1] = pos[1] + size;
	square[0][2] = pos[2];

	square[1][0] = pos[0] + size;
	square[1][1] = pos[1] + size;
	square[1][2] = pos[2];

	square[2][0] = pos[0] - size;
	square[2][1] = pos[1] - size;
	square[2][2] = pos[2];

	square[3][0] = pos[0] + size;
	square[3][1] = pos[1] - size;
	square[3][2] = pos[2];

	DrawBeam(client, square[0], square[1], 1.0, 0.5, 0.5, color, 0.0, 0);
	DrawBeam(client, square[0], square[2], 1.0, 0.5, 0.5, color, 0.0, 0);
	DrawBeam(client, square[2], square[3], 1.0, 0.5, 0.5, color, 0.0, 0);
	DrawBeam(client, square[1], square[3], 1.0, 0.5, 0.5, color, 0.0, 0);
}

void DrawBeam(int client, float startvec[3], float endvec[3], float life, float width, float endwidth, int color[4], float amplitude, int speed) 
{
	if(gB_GhostIgnorez[client])
	{
		TE_SetupBeamPoints(startvec, endvec, gI_SpriteIgnorez, 0, 0, 66, life, width, endwidth, 0, amplitude, color, speed);
		TE_SendToClient(client);
	}
	else
	{
		TE_SetupBeamPoints(startvec, endvec, gI_Sprite, 0, 0, 66, life, width, endwidth, 0, amplitude, color, speed);
		TE_SendToClient(client);
	}
}

// Caculate stuffs
int Min(int a, int b) 
{
    return a < b ? a : b;
}

int Max(int a, int b) 
{
    return a > b ? a : b;
}

int Abs(int num)
{
	return num > 0 ? num : -num;
}

// Cookie stuffs
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

stock bool IsValidClient2(int client, bool bAlive = false)
{
	return (client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}

//misc
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
