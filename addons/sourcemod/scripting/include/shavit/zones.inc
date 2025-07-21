/*
 * shavit's Timer - zones.inc file
 * by: shavit,
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

#if defined _shavit_zones_included
	#endinput
#endif
#define _shavit_zones_included

#define MAX_ZONES 128
#define MAX_STAGES 64

enum
{
	Zone_Start, 			// starts timer
	Zone_End, 				// stops timer
	Zone_Stage,				// as a start zone in stageed map
	Zone_Checkpoint,		// shows time when entering zone	
	Zone_Autobhop,			// forces autobhop for the player
	Zone_NoJump,			// blocks the player from jumping while inside the zone	
	Zone_Respawn, 			// respawns the player
	Zone_Stop,				// stops the player's timer
	Zone_Slay,				// slays (kills) players which come to this zone
	Zone_Freestyle,			// ignores style physics when at this zone. e.g. WASD when SWing
	Zone_CustomSpeedLimit,	// overwrites velocity limit in the zone
	Zone_Teleport,			// teleports to a defined point
	Zone_CustomSpawn,		// spawn position for a track. not a physical zone.
	Zone_Easybhop,			// forces easybhop whether if the player is in non-easy styles or if the server has different settings
	Zone_Slide,				// allows players to slide, in order to fix parts like the 5th stage of bhop_arcane
	Zone_Airaccelerate,		// custom sv_airaccelerate inside this,
	Zone_NoTimerGravity,	// prevents the timer from setting gravity while inside this zone
	Zone_Gravity,			// lets you set a specific gravity while inside this zone
	Zone_Speedmod,			// creates a player_speedmod
	Zone_Output,			// outputs a targetname / classname when player enter or leave this zone
	ZONETYPES_SIZE
};

enum
{
	ZF_ForceRender  = (1 << 0),
	ZF_Hammerid     = (1 << 1), // used by ZoneForm_{trigger_{multiple, teleport}, func_[rot_]button} sometimes
	ZF_Solid        = (1 << 2), // forces the zone to block people...
	ZF_DrawAsBox    = (1 << 3), // Draw trigger_multiple as box	
	ZF_Origin       = (1 << 4), // sTarget is the entity's origin formatted as "%X %X %X"
	// zone filter bit flags
	ZF_FilterIgnore = (1 << 5), // ignore the filter when the zone is triggered
	ZF_FilterMatchPass = (1 << 6), // trigger zone logic when targetname matches
	ZF_FilterMisMatchPass = (1 << 7), // trigger zone logic when targetname dismatches
	ZF_FilterClassname = (1 << 8), // use classname as filter
	ZF_OutputTargetname = (1 << 9), // output a targetname
	ZF_OutputClassname = (1 << 10), // output a classname
	ZF_OutputEndTouch = (1 << 11), // output on EndTouch
};

enum // Zone speed limit flag. Used by specify prestrafe limit to each stage zone. 
{
	ZSLF_LimitSpeed   = (1 << 0), // limit horizontal velocity
	ZSLF_BlockBhop    = (1 << 1), // stop players when they try to bhop  
	ZSLF_BlockJump    = (1 << 2), // block jump
	ZSLF_ReduceSpeed  = (1 << 3), // reduce speed when exceeding speed limit
	ZSLF_NoVerticalSpeed = (1 << 4), // work as the same behaviour of convar "shavit_core_nozaxisspeed": dont start timer if vertical speed exists
	ZSLF_ResetSpeedAfterTeleported = (1 << 5), // reset speed after teleported by a teleport zone
};

#define DEFAULT_SPEEDLIMITFLAG (ZSLF_LimitSpeed|ZSLF_BlockBhop)

// Zone Display type
enum
{
	ZoneDisplay_Default,
	ZoneDisplay_Flat,
	ZoneDisplay_Box,
	ZoneDisplay_None,
	ZoneDisplay_Size
};

// Zone Color, maybe we just let the user decide what color they actually want..? maybe store rgba as hex string but that would be mega long for each track
enum
{
	ZoneColor_Default,
	ZoneColor_White,
	ZoneColor_Red,
	ZoneColor_Orange,
	ZoneColor_Yellow,
	ZoneColor_Green,
	ZoneColor_Cyan,
	ZoneColor_Blue,
	ZoneColor_Purple,
	ZoneColor_Pink,
	ZoneColor_Size
};

enum
{
	ZoneWidth_Default,
	ZoneWidth_UltraThin,
	ZoneWidth_Thin,
	ZoneWidth_Normal,
	ZoneWidth_Thick,
	ZoneWidth_Size
};

enum
{
	ZoneForm_Box,
	ZoneForm_trigger_multiple,
	ZoneForm_trigger_teleport,
	ZoneForm_func_button,
	ZoneForm_AreasAndClusters,
};

enum struct zone_cache_t
{
	int iType; // The type of zone. Zone_Start, Zone_End, etc...
	int iTrack; // 0 - main, 1 - bonus1 etc
	int iEntity; // Filled by Shavit_GetZone() if applicable.
	int iDatabaseID; // Can be the database ID (> 0) for "sql" sources. Non-sql sources can fill this with whatever.
	int iFlags; // The ZF_* flags.
	int iData; // Depends on the zone. Zone_Stage stores the stage number in this for example.
	int iSpeedLimitFlags; // A bitfalg for each start zone. track start zone speed limit will be overridden by higher level speed limit if there are two start zone in same track.
	float fCorner1[3]; // the hull mins. (or unused if ZoneForm_AreasAndClusters) // TODO, maybe reuse for cluster & areas?
	float fCorner2[3]; // the hull maxs. (or unused if ZoneForm_AreasAndClusters)
	float fDestination[3]; // Used by Zone_CustomSpawn, Zone_Teleport, and Zone_Stage.
	int iForm; // ZoneForm_*
	char sSource[16]; // "sql", "autobutton", "autozone", "sourcejump", "http", etc...
	char sTarget[64]; // either the hammerid or the targetname or used for box form zone filter and output.
}

stock void GetZoneName(int client, int zoneType, char[] output, int size)
{
	static char sTranslationStrings[ZONETYPES_SIZE][] = {
		"Zone_Start",
		"Zone_End",
		"Zone_Stage",	
		"Zone_Checkpoint",
		"Zone_Autobhop",
		"Zone_NoJump",
		"Zone_Respawn",
		"Zone_Stop",
		"Zone_Slay",
		"Zone_Freestyle",
		"Zone_CustomSpeedLimit",
		"Zone_Teleport",
		"Zone_CustomSpawn",
		"Zone_Easybhop",
		"Zone_Slide",
		"Zone_Airaccelerate",
		"Zone_NoTimerGravity",
		"Zone_Gravity",
		"Zone_Speedmod",
		"Zone_Output",
	};

	if (zoneType < 0 || zoneType >= ZONETYPES_SIZE)
		FormatEx(output, size, "%T", "Zone_Unknown", client);
	else
		FormatEx(output, size, "%T", sTranslationStrings[zoneType], client);
}

// Please follow something like this:
//   mod_zone_start
//   mod_zone_end
//   mod_zone_stage_X
//   mod_zone_checkpoint_X
//   mod_zone_bonus_X_start
//   mod_zone_bonus_X_end
//
//   climb_startbutton
//   climb_endbutton
//   climb_bonusX_startbutton
//   climb_bonusX_endbutton
//
//   climb_startzone
//   climb_endzone
//   climb_bonusX_startzone
//   climb_bonusX_endzone
stock bool Shavit_ParseZoneTargetname(const char[] targetname, bool button, int& type, int& track, int& data, const char[] mapname_for_log="")
{
	track = Track_Main;
	type = -1;
	data = 0;

	int index = -1;

	if (strncmp(targetname, "climb_", 6) != 0
	&&  (button || strncmp(targetname, "mod_zone_", 9) != 0))
	{
		return false;
	}

	if (StrContains(targetname, "start") != -1)
	{
		type = Zone_Start;
	}
	else if (StrContains(targetname, "end") != -1)
	{
		type = Zone_End;
	}
	else if(StrContains(targetname, "stage") != -1)
	{
		type = Zone_Stage;
	}
	else if(StrContains(targetname, "checkpoint") != -1)
	{
		type = Zone_Checkpoint;
	}
	
	if (type == -1)
	{
		if (mapname_for_log[0]) 
			LogError("invalid zone type in prebuilt map zone (%s) on %s", targetname, mapname_for_log);
		return false;
	}

	if(type == Zone_Start || type == Zone_End)
	{
		index = StrContains(targetname, "bonus");
		if(index != -1)
		{
			index += 5;
			if (targetname[index] == '_') 
				index += 1;

			if ('1' <= targetname[index] <= '9')
				track = StringToInt(targetname[index]);

			if (track < Track_Bonus || track > Track_Bonus_Last)
			{
				if (mapname_for_log[0]) 
					LogError("invalid track in prebuilt map zone (%s) on %s", targetname, mapname_for_log);
				return false;
			}
		}
		else
		{
			track = Track_Main;
		}
	}
	else if(type == Zone_Stage || type == Zone_Checkpoint)
	{
		if (button)
		{
			if (mapname_for_log[0]) 
				LogError("invalid button (%s) (has checkpoint) on %s", targetname, mapname_for_log);

			return false;
		}

		track = Track_Main;

		if(type == Zone_Stage)
		{
			index = StrContains(targetname, "stage");
			index += 5;
		}
		else
		{
			index = StrContains(targetname, "checkpoint");
			index += 10;
		}

		if(targetname[index] == '_')
			index += 1;

		if ('1' <= targetname[index] <= '9')
		{
			data = StringToInt(targetname[index]);
		}

		if ((type == Zone_Stage && data < 2) || (type == Zone_Checkpoint && data < 1) || data > MAX_STAGES)
		{
			if (mapname_for_log[0]) 
				LogError("invalid %s number in prebuilt map zone (%s) on %s", type == Zone_Stage ? "stage":"checkpoint", targetname, mapname_for_log);
			return false;
		}
	}

	return true;
}

stock bool IsValidPattern(const char[] str)
{
	int len = strlen(str);
	for (int i = 0; i < len; i++)
	{
		if (!((str[i] >= 'a' && str[i] <= 'z') || (str[i] >= 'A' && str[i] <= 'Z') || (str[i] >= '0' && str[i] <= '9') || str[i] == '_'))
		{
			return false;
		}
	}

	return true;
}

/**
 * Called when a player enters a zone.
 *
 * @param client                    Client index.
 * @param type                      Zone type.
 * @param track                     Zone track.
 * @param id                        Zone ID.
 * @param entity                    Zone trigger entity index.
 * @param data                      Zone data if any.
 * @noreturn
 */
forward void Shavit_OnEnterZone(int client, int type, int track, int id, int entity, int data);

/**
 * Called when a player leaves a zone.
 *
 * @param client                    Client index.
 * @param type                      Zone type.
 * @param track                     Zone track.
 * @param id                        Zone ID.
 * @param entity                    Zone trigger entity index.
 * @param data                      Zone data if any.
 * @noreturn
 */
forward void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity, int data);

/**
 *
 */
forward void Shavit_LoadZonesHere();

/**
 * Called when a player reach next stage.
 *
 * @param client                    Client index.
 * @param track						Track index.
 * @param startStage				Stage number which client start.
 * @param endStage					Stage number which stage zone client touched.
 * @param stageStartTime			The time when player leave the start stage zone.
 * @param stageFinishTime			The time when player touch the stage zone.
 * 
 * @noreturn                        
 */
forward void Shavit_OnReachNextStage(int client, int track, int startStage, int endStage);

/**
 * Called when a player reach next cp.
 *
 * @param client                    Client index.
 * @param track						Track index.
 * @param checkpoint				Checkpoint number of zone which client entered.
 * @param time						Client's current time.
 * 
 * @noreturn                        
 */
forward void Shavit_OnReachNextCP(int client, int track, int checkpoint, float time);

/**
 * Called when a zone is created.
 *
 * @param entity                    Zone trigger entity index.
 * @param type                      Zone type.
 * @param track                     Zone track.
 * @param data                      Zone data if any.
 * @noreturn
 */
forward void Shavit_OnZoneCreated(int entity, int type, int track, int data);

/**
 * Called when a zone is deleted.
 *
 * @param type                      Zone type.
 * @param track                     Zone track.
 * @param data                      Zone ID.
 * @noreturn
 */
forward void Shavit_OnZoneDeleted(int type, int track, int data);

/**
 * Called when all zones are deleted.
 */
forward void Shavit_OnAllZoneDeleted();

/**
 * Checks if a mapzone exists.
 *
 * @param type                      Mapzone type.
 * @param track                     Mapzone track, -1 to ignore track.
 * @return                          Boolean value.
 */
native bool Shavit_ZoneExists(int type, int track);

/**
 * Checks if a player is inside a mapzone.
 *
 * @param client                    Client index.
 * @param type                      Mapzone type.
 * @param track                     Mapzone track, -1 to ignore track.
 * @return                          Boolean value.
 */
native bool Shavit_InsideZone(int client, int type, int track);

/**
 * Gets the specified zone's data.
 *
 * @param zoneid                    ID of the zone we query the data of.
 * @return                          Zone data. 0 if none is specified.
 */
native int Shavit_GetZoneData(int zoneid);

/**
 * Gets the specified zone's flags.
 *
 * @param zoneid                    ID of the zone we query the flags of.
 * @return                          Zone flags. 0 if none is specified.
 */
native int Shavit_GetZoneFlags(int zoneid);

/**
 * Deletes all map zones for the specified map.
 * Plugin will refresh if map is currently on.
 *
 * @param map                       Map name.
 * @noreturn
 */
native void Shavit_Zones_DeleteMap(const char[] map);

/**
 * Checks if a player is inside a stage zone.
 *
 * @param client                    Client index.
 * @param stage                     Reference to variable that will hold the zone's stage.
 * @param limitspeed				Reference to variable that will hold whether the stage zone liimit prespeed.
 * @return                          Boolean value.
 */
native bool Shavit_InsideZoneStage(int client, int &stage, int &limitspeed = true);

/**
 * Checks if a player is inside a mapzone.
 *
 * @param client                    Client index.
 * @param type                      Mapzone type.
 * @param track                     Mapzone track, -1 to ignore track.
 * @param zoneid                    Reference to variable that will hold the zone's ID.
 * @return                          Boolean value.
 */
native bool Shavit_InsideZoneGetID(int client, int type, int track, int &zoneid);

/**
 * Teleport a player to specific start zone in standard way.
 *
 * @param client                    Client index.
 * @param track                     Mapzone track.
 * @param stage                     Mapzone stage.
 * @noreturn
 */
native void Shavit_TeleportToStartZone(int client, int track, int stage)

/**
 * Checks if a player is in the process of creating a mapzone.
 *
 * @param client                    Client index.
 * @return                          Boolean value.
 */
native bool Shavit_IsClientCreatingZone(int client);

/**
 * Retrieve the highest stage number for a given track.
 *
 * @param track                     Track number.
 * @return                          Number of stages.
 */
native int Shavit_GetStageCount(int track);

/**
 * Retrieve the highest checkpoint number for a given track.
 *
 * @param track                     Track number.
 * @return                          Number of stages.
 */
native int Shavit_GetCheckpointCount(int track);

/**
 * Returns the zone index for the entity if available.
 *
 * @param entity                    Client index.
 * @return                          -1 if not a zone entity. >=0 for a zone index.
 */
native int Shavit_GetZoneID(int entity);

/**
 * Returns the zone track.
 *
 * @param zoneid                    Zone index.
 * @return                          Zone track.
 */
native int Shavit_GetZoneTrack(int zoneid);

/**
 * Returns how many tracks in current map.
 * 
 * @param bonus						Whether to count bonus only.
 * @param mask						Return track mask if true, else return number of tracks count.
 * @return 							Result of specific parameters.
 */
native int Shavit_GetMapTracks(bool bonus, bool mask);

/**
 * Returns the zone type.
 *
 * @param zoneid                    Zone index.
 * @return                          Zone type.
 */
native int Shavit_GetZoneType(int zoneid);

/**
 * Returns the prespeed limit bitflag of a zone.
 *
 * @param zoneid                    Zone index.
 * @return                          Int value, bit flag of zone speed limit.
 */
native int Shavit_GetZoneSpeedLimitFlags(int zoneid);

/**
 * Returns the prespeed limit bitflag of a track.
 *
 * @param track                    	Timer track.
 * @return                          Int value, bit flag of zone speed limit.
 */
native int Shavit_GetTrackSpeedLimitFlags(int zoneid);

/**
 * Sets the player's current location as their spawn location for the specified track.
 *
 * @param client                    Client index.
 * @param track                     Timer track.
 * @param stage						Stage number.
 * @param anglesonly                Whether to save angles only.
 * @noreturn
 */
native void Shavit_SetStart(int client, int track, int stage, bool anglesonly);

/**
 * Deletes the player's current set start position for the specified track.
 *
 * @param client                    Client index.
 * @param track                     Timer track.
 * @param stage						Stage number.
 * @noreturn
 */
native void Shavit_DeleteSetStart(int client, int track, int stage);

/**
 * Removes all zones from memory and then reloads zones from the database & any plugins.
 * @noreturn
 */
native void Shavit_ReloadZones();

/**
 * Removes all zones from memory and unhooks any zones and kills any created entities.
 * @noreturn
 */
native void Shavit_UnloadZones();

/**
 * Returns the number of zones that are currently loaded in memory.
 *
 * @return                          The number of zones currently loaded in memory.
 */
native int Shavit_GetZoneCount();


/**
 * Retrieves the zone_cache_t for a zone.
 *
 * @param index                     The zone index. 0 through Shavit_GetZoneCount()-1.
 * @param zonecache                 The zone_cache_t struct that is retrieved from the zone.
 * @param size                      sizeof(zone_cache_t) to make sure the caller has a matching struct version.
 *
 * @noreturn
 */
native void Shavit_GetZone(int index, any[] zonecache, int size = sizeof(zone_cache_t));

/**
 * Adds a zone to memory. (Does NOT insert into DB).
 *
 * @param zonecache                 The zone_cache_t struct that is used to create or hook a zone.
 * @param size                      sizeof(zone_cache_t) to make sure the caller has a matching struct version.
 *
 * @return                          The zone index on success (index for a particular zone can change). <0 on failure.
 */
native int Shavit_AddZone(any[] zonecache, int size = sizeof(zone_cache_t));

/**
 * Removes a zone from memory. (Does NOT delete from DB).
 * WARNING: If there are zones after `index`, then they will be moved down in memory to fill this slot after removal.
 * This unhooks the zone's entity too.
 *
 * @param index                     The zone's index.
 *
 * @noreturn
 */
native void Shavit_RemoveZone(int index);


public SharedPlugin __pl_shavit_zones =
{
	name = "shavit-zones",
	file = "shavit-zones.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_zones_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_GetZoneData");
	MarkNativeAsOptional("Shavit_GetZoneFlags");
	MarkNativeAsOptional("Shavit_GetStageCount");
	MarkNativeAsOptional("Shavit_InsideZone");
	MarkNativeAsOptional("Shavit_InsideZoneGetID");
	MarkNativeAsOptional("Shavit_IsClientCreatingZone");
	MarkNativeAsOptional("Shavit_ZoneExists");
	MarkNativeAsOptional("Shavit_GetMapTracks");
	MarkNativeAsOptional("Shavit_Zones_DeleteMap");
	MarkNativeAsOptional("Shavit_SetStart");
	MarkNativeAsOptional("Shavit_DeleteSetStart");
	MarkNativeAsOptional("Shavit_GetZoneTrack");
	MarkNativeAsOptional("Shavit_GetZoneType");
	MarkNativeAsOptional("Shavit_GetZoneID");
	MarkNativeAsOptional("Shavit_ReloadZones");
	MarkNativeAsOptional("Shavit_UnloadZones");
	MarkNativeAsOptional("Shavit_GetZoneCount");
	MarkNativeAsOptional("Shavit_GetZone");
	MarkNativeAsOptional("Shavit_AddZone");
	MarkNativeAsOptional("Shavit_RemoveZone");
	MarkNativeAsOptional("Shavit_InsideZoneStage");
	MarkNativeAsOptional("Shavit_TeleportToStartZone");
	MarkNativeAsOptional("Shavit_GetZoneSpeedLimitFlags");
	MarkNativeAsOptional("Shavit_GetTrackSpeedLimitFlags");
}
#endif
