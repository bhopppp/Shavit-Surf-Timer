#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <convar_class>
#include <shavit>

#pragma newdecls required
#pragma semicolon 1

#define PAINT_DISTANCE_SQ 1.0

/* Colour name, file name */
char gS_PaintColors[][][64] =    // Modify this to add/change colours
{
	{"PaintColorRandom",     	"random"         },
	{"PaintColorWhite",      	"paint_white"    },
	{"PaintColorBlack",      	"paint_black"    },
	{"PaintColorBlue",       	"paint_blue"     },
	{"PaintColorLightBlue", 	"paint_lightblue"},
	{"PaintColorBrown",      	"paint_brown"    },
	{"PaintColorCyan",       	"paint_cyan"     },
	{"PaintColorGreen",      	"paint_green"    },
	{"PaintColorDarkGreen", 	"paint_darkgreen"},
	{"PaintColorRed",        	"paint_red"      },
	{"PaintColorOrange",     	"paint_orange"   },
	{"PaintColorYellow",     	"paint_yellow"   },
	{"PaintColorPink",       	"paint_pink"     },
	{"PaintColorLightPink", 	"paint_lightpink"},
	{"PaintColorPurple",     	"paint_purple"   },
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
int gI_Partner[MAXPLAYERS + 1];
int gI_Partnering[MAXPLAYERS + 1];

int gI_PlayerPaintColor[MAXPLAYERS + 1];
int gI_PlayerPaintSize[MAXPLAYERS + 1];

float gF_LastPaint[MAXPLAYERS + 1][3];

bool gB_IsPainting[MAXPLAYERS + 1];
bool gB_ErasePaint[MAXPLAYERS + 1];
bool gB_ReciveRequest[MAXPLAYERS + 1];
bool gB_PaintToAll[MAXPLAYERS + 1];
bool gB_PaintMode[MAXPLAYERS + 1];

bool gB_Late = false;

chatstrings_t gS_ChatStrings;

/* COOKIES */
Cookie gH_PlayerPaintColour;
Cookie gH_PlayerPaintSize;
Cookie gH_PlayerReciveRequest;
Cookie gH_PlayerPaintMode;

/* CONVARS */
Convar gCV_AccessFlag;

public Plugin myinfo =
{
	name = "[shavit-surf] Paint",
	author = "SlidyBat, Ciallo-Ani, KikI",
	description = "Allow players to paint on walls.",
	version = "3.0",
	url = "https://github.com/bhopppp/Shavit-Surf-Timer"
}

public void OnPluginStart()
{
	/* Register Cookies */
	gH_PlayerPaintColour = new Cookie("paint_playerpaintcolour", "paint_playerpaintcolour", CookieAccess_Protected);
	gH_PlayerPaintSize = new Cookie("paint_playerpaintsize", "paint_playerpaintsize", CookieAccess_Protected);
	gH_PlayerPaintMode = new Cookie("paint_playerpaintmode", "paint_playerpaintmode", CookieAccess_Protected);
	gH_PlayerReciveRequest = new Cookie("paint_playerreciverequest", "paint_playerreciverequest", CookieAccess_Protected);

	gCV_AccessFlag = new Convar("shavit_paint_painttoall_accessflag", "", "Flag to require privileges for send decals to all", 0, false, 0.0, false, 0.0);
	Convar.AutoExecConfig();

	/* COMMANDS */
	RegConsoleCmd("+paint", Command_EnablePaint, "Start Painting");
	RegConsoleCmd("-paint", Command_DisablePaint, "Stop Painting");
	RegConsoleCmd("sm_paint", Command_Paint, "Open a paint menu for a client");
	RegConsoleCmd("sm_paintcolour", Command_PaintColour, "Open a paint color menu for a client");
	RegConsoleCmd("sm_paintcolor", Command_PaintColour, "Open a paint color menu for a client");
	RegConsoleCmd("sm_paintsize", Command_PaintSize, "Open a paint size menu for a client");
	RegConsoleCmd("sm_paintmode", Command_PaintMode, "Toggle paint mode for a client");
	RegConsoleCmd("sm_painteraser", Command_PaintErase, "Toggle paint eraser for a client");

	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-paint.phrases");

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
	char sValue[64];

	gH_PlayerPaintColour.Get(client, sValue, sizeof(sValue));
	gI_PlayerPaintColor[client] = StringToInt(sValue);

	gH_PlayerPaintSize.Get(client, sValue, sizeof(sValue));
	gI_PlayerPaintSize[client] = StringToInt(sValue);

	gH_PlayerPaintMode.Get(client, sValue, sizeof(sValue));
	gB_PaintMode[client] = sValue[0] == '1';
	
	gB_PaintToAll[client] = false;

	gH_PlayerReciveRequest.Get(client, sValue, sizeof(sValue));
	gB_ReciveRequest[client] = sValue[0] == '1';

	gI_Partner[client] = 0;
}

public void OnMapStart()
{
	char buffer[PLATFORM_MAX_PATH];

	AddFileToDownloadsTable("materials/decals/paint/paint_decal.vtf");
	AddFileToDownloadsTable("materials/decals/paint/paint_eraser.vtf");
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

void OpenPaintMenu(int client)
{
	Menu menu = new Menu(Paint_MenuHandler);

	menu.SetTitle("%T\n  \n%T", "PaintMenuTitle", client, "PaintTips", client);

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

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "PaintOptions", client);
	menu.AddItem("option", sMenuItem);

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
			if(gI_Partner[param1] != 0)
			{
				int partner = gI_Partner[param1];

				gI_Partner[param1] = 0; 
				gI_Partner[partner] = 0;

				char sName[64];
				GetClientName(param1, sName, sizeof(sName));
				char sPartnerName[64];
				GetClientName(partner, sPartnerName, sizeof(sPartnerName));

				Shavit_PrintToChat(param1, "%T", "Unpartnered", param1, gS_ChatStrings.sVariable2, sPartnerName, gS_ChatStrings.sText);
				Shavit_PrintToChat(partner, "%T", "Unpartnered", partner, gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText);				
			}
			else
			{
				Shavit_PrintToChat(param1, "%T", "NoPartner", param1);
			}

			OpenPaintMenu(param1);
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

	bool hasAccess = CheckClientAccess(client);

	FormatEx(sMenuItem, sizeof(sMenuItem), "%T: %T", "PaintSize", client, gS_PaintSizes[gI_PlayerPaintSize[client]][0], client);
	menu.AddItem("size", sMenuItem);

	FormatEx(sMenuItem, sizeof(sMenuItem), "[%T] %T", gB_ReciveRequest[client] ? "ItemEnabled":"ItemDisabled", client, "ReceivePartnerRequest", client);
	menu.AddItem("receive", sMenuItem);

	if(hasAccess)
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

				char sValue[8];
				IntToString(view_as<int>(gB_PaintMode[param1]), sValue, sizeof(sValue));
				gH_PlayerPaintMode.Set(param1, sValue);				
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

			char sValue[8];
			IntToString(view_as<int>(gB_ReciveRequest[param1]), sValue, sizeof(sValue));
			gH_PlayerReciveRequest.Set(param1, sValue);
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
		char sValue[64];
		gI_PlayerPaintColor[param1] = param2;
		IntToString(param2, sValue, sizeof(sValue));
		gH_PlayerPaintColour.Set(param1, sValue);

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
		OpenPaintMenu(param1);
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

		PartneringResponse(param1, partner, 3);
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
			PartneringResponse(param1, partner, 1);
		}
		else if(StrEqual(sExploded[0], "d"))
		{
			PartneringResponse(param1, partner, 2);
		}
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

	if(status == 1) // accept
	{
		menu.SetTitle("%T\n%T\n ", "RequestAccepted", partner, sName, "MenuAutoClose", partner);

		gI_Partner[client] = partner;
		gI_Partner[partner] = client;

		Shavit_PrintToChat(client, "%T", "Partnered", client, gS_ChatStrings.sVariable2, sPartnerName, gS_ChatStrings.sText);
		Shavit_PrintToChat(partner, "%T", "Partnered", partner, gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText);
	}
	else if(status == 2) // decline
	{
		menu.SetTitle("%T\n%T\n ", "RequestDeclined", partner, sName, "MenuAutoClose", partner);

		gI_Partner[client] = 0;
		gI_Partner[partner] = 0;
	}
	else if(status == 3) // cancel
	{
		menu.SetTitle("%T\n%T\n ", "RequestCanceled", partner, sName, "MenuAutoClose", partner);

		gI_Partner[client] = 0;
		gI_Partner[partner] = 0;
	}
	else // abort
	{
		menu.SetTitle("%T\n%T\n ", "RequestAborted", partner, sName, "MenuAutoClose", partner);
		
		gI_Partner[client] = 0;
		gI_Partner[partner] = 0;
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
		char sValue[64];
		gI_PlayerPaintSize[param1] = param2;
		IntToString(param2, sValue, sizeof(sValue));
		gH_PlayerPaintSize.Set(param1, sValue);

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

stock void TraceEye(int client, float pos[3])
{
	float vAngles[3], vOrigin[3];
	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);

	TR_TraceRayFilter(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

	if (TR_DidHit())
	{
		TR_GetEndPosition(pos);
	}
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
