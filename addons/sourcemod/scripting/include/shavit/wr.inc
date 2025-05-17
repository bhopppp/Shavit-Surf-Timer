/*
 * shavit's Timer - wr.inc file
 * by: shavit, SaengerItsWar, rtldg, KiD Fearless, rtldg, BoomShotKapow
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

#if defined _shavit_wr_included
	#endinput
#endif
#define _shavit_wr_included

/**
 * Like Shavit_OnFinishStage, but after the insertion query was called.
 * Called from shavit-wr
 *
 * @param client                    Client index.
 * @param style                     Style the record was done on.
 * @param time                      Record time.
 * @param jumps                     Jumps amount.
 * @param strafes                   Amount of strafes.
 * @param sync                      Sync percentage (0.0 to 100.0) or -1.0 when not measured.
 * @param rank                      Rank on map.
 * @param overwrite                 1 - brand new record. 2 - update.
 * @param stage                     Stage number.
 * @param oldtime                   The player's best time on the map before this finish.
 * @param perfs                     Perfect jump percentage (0.0 to 100.0) or 100.0 when not measured.
 * @param avgvel                    Player's average velocity throughout the run.
 * @param maxvel                    Player's highest reached velocity.
 * @param timestamp                 System time of when player finished.
 * @noreturn
 */
forward void Shavit_OnFinishStage_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int stage, float oldtime, float perfs, float avgvel, float maxvel, int timestamp);

/**
 * Called when there's a new WR on the map.
 *
 * @param client                    Client index.
 * @param style                     Style the record was done on.
 * @param time                      Record time.
 * @param jumps                     Jumps amount.
 * @param strafes                   Amount of strafes.
 * @param sync                      Sync percentage (0.0 to 100.0) or -1.0 when not measured.
 * @param track                     Timer track.
 * @param stage						Stage number.
 * @param oldwr                     Time of the old WR. 0.0 if there's none.
 * @param oldtime                   The player's best time on the map before this finish.
 * @param perfs                     Perfect jump percentage (0.0 to 100.0) or 100.0 when not measured.
 * @param avgvel                    Player's average velocity throughout the run.
 * @param maxvel                    Player's highest reached velocity.
 * @param timestamp                 System time of when player finished.
 * @noreturn
 */
forward void Shavit_OnWorldRecord(int client, int style, float time, int jumps, int strafes, float sync, int track, int stage, float oldwr, float oldtime, float perfs, float avgvel, float maxvel, int timestamp);

/**
 * Like Shavit_OnFinish, but after the insertion query was called.
 * Called from shavit-wr
 *
 * @param client                    Client index.
 * @param style                     Style the record was done on.
 * @param time                      Record time.
 * @param jumps                     Jumps amount.
 * @param strafes                   Amount of strafes.
 * @param sync                      Sync percentage (0.0 to 100.0) or -1.0 when not measured.
 * @param rank                      Rank on map.
 * @param overwrite                 1 - brand new record. 2 - update.
 * @param track                     Timer track.
 * @param oldtime                   The player's best time on the map before this finish.
 * @param perfs                     Perfect jump percentage (0.0 to 100.0) or 100.0 when not measured.
 * @param avgvel                    Player's average velocity throughout the run.
 * @param maxvel                    Player's highest reached velocity.
 * @param timestamp                 System time of when player finished.
 * @noreturn
 */
forward void Shavit_OnFinish_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp);


/**
 * Called when an admin deletes a WR.
 *
 * @param style                     Style the record was done on.
 * @param id                        Record ID. -1 if mass deletion.
 * @param track                     Timer track.
 * @param accountid                 The account ID of the wr holder
 * @param mapname                   The map name.
 * @noreturn
 */
forward void Shavit_OnWRDeleted(int style, int id, int track, int stage, int accountid, const char[] mapname);

/**
 * Called after shavit-wr caches the current map's WRs.
 *
 * @noreturn
 */
forward void Shavit_OnWorldRecordsCached();

/**
 * Called after shavit-wr caches the current map's stage WRs.
 *
 * @noreturn
 */
forward void Shavit_OnStageWorldRecordsCached();

/**
 * Called before the timer finish message is printed to the users.
 *
 * @param client                    Client index.
 * @param everyone                  Is the message printed to everyone, or just the client?
 * @param snapshot                  A snapshot of the client's timer when printing the message.
 * @param overwrite                 Modify the database? 0 - no. 1 - brand new record. 2 - new personal best.
 * @param rank                      Rank on map.
 * @param message                   The finish message.
 * @param maxlen                    Buffer size of message.
 * @param message2                  A second line of info that is printed on finish.
 * @param maxlen2                   Buffer size of message2.
 *
 * @return                          Plugin_Handled or Plugin_Stop to stop the message. Anything else to use new values.
 */
forward Action Shavit_OnFinishMessage(int client, bool &everyone, timer_snapshot_t snapshot, int overwrite, int rank, char[] message, int maxlen, char[] message2, int maxlen2);

/**
 * Retrieves the world record for the given style/track.
 *
 * @param style                     Style to get the WR for.
 * @param track                     Timer track.
 * @return                          World record for the specified settings.
 */
native float Shavit_GetWorldRecord(int style, int track);

/**
 * Reloads WR leaderboards cache for the current map.
 *
 * @noreturn
 */
native void Shavit_ReloadLeaderboards();

/**
 * Retrieves the world record start veloctiy for the given style/track.
 *
 * @param style                     Style to get the WR for.
 * @param track                     Timer track.
 * @return                          Start velocity for the specified settings.
 */
native float Shavit_GetWRStartVelocity(int style, int track);

/**
 * Retrieves the world record end veloctiy for the given style/track.
 *
 * @param style                     Style to get the WR for.
 * @param track                     Timer track.
 * @return                          End velocity for the specified settings.
 */
native float Shavit_GetWREndVelocity(int style, int track);

/**
 * Saves the WR's record ID for the current map on a variable.
 * Unused in base plugins, as of pre-1.4b.
 *
 * @param style                     Style to get the WR for.
 * @param time                      Reference to the time variable. 0.0 will be returned if no records.
 * @param track                     Timer track.
 * @noreturn
 */
native void Shavit_GetWRRecordID(int style, int &recordid, int track);

/**
 * Saves the WR's player name on the map on a variable.
 *
 * @param style                     Style to get the WR for.
 * @param wrname                    Reference to the name variable.
 * @param wrmaxlength               Max length for the string.
 * @param track                     Timer track.
 * @return                          Returns true if the player's name has been cached. False if it hasn't. `wrname` is filled with the player's name if available, otherwise the steamid if the name isn't cached, and lastly the string "none" if neither the name or steamid is available.
 */
native bool Shavit_GetWRName(int style, char[] wrname, int wrmaxlength, int track);

/**
 * Retrieves the best time of a player.
 *
 * @param client                    Client index.
 * @param style                     Style to get the PB for.
 * @param track                     Timer track.
 * @return                          Floating number of the player's best time for given style/track.
 */
native float Shavit_GetClientPB(int client, int style, int track);

/**
 * Sets the cached pb directly for the given client, style and track.
 *
 * @param client                    Client index.
 * @param style                     Style to get the PB for.
 * @param track                     Timer track.
 * @param time                      Time to set
 * @noreturn
 */
native void Shavit_SetClientPB(int client, int style, int track, float time);

/**
 * Retrieves the completions of a player.
 *
 * @param client                    Client index.
 * @param style                     Style to get the Completions for.
 * @param track                     Timer track.
 * @return                          Number of the player's Completions for given style/track.
 */
native int Shavit_GetClientCompletions(int client, int style, int track);

/**
 * Get the client's pb start velocity of specific track.
 * 
 * @param client					Client index.
 * @param style						Style index. 
 * @param track						Track number for completions.
 * @return							Start velocity.						
 */
native float Shavit_GetClientStartVelocity(int client, int style, int track);

/**
 * Get the client's pb end velocity of specific track.
 * 
 * @param client					Client index.
 * @param style						Style index. 
 * @param track						Track number.
 * @return							End velocity.						
 */
native float Shavit_GetClientEndVelocity(int client, int style, int track);

/**
 * Set the client's start velocity of specific track.
 * 
 * @param client					Client index.
 * @param style						Style index. 
 * @param track						Track number.
 * @param vel						Velocity value to set.
 * @noreturn					
 */
native void Shavit_SetClientStartVelocity(int client, int style, int track, float vel);

/**
 * Set the client's end velocity of specific track.
 * 
 * @param client					Client index.
 * @param style						Style index. 
 * @param track						Track number.
 * @param vel						Velocity value to set.
 * @noreturn
 */
native void Shavit_SetClientEndVelocity(int client, int style, int track, float vel);

/**
 * Get the amount of records on the current map/style on a track.
 *
 * @param style                     Style.
 * @param track                     Timer track.
 * @return                          Amount of records.
 */
native int Shavit_GetRecordAmount(int style, int track);

/**
 * Calculate potential rank for a given style and time.
 *
 * @param style                     Style.
 * @param time                      Time to check for.
 * @param track                     Timer track.
 * @return                          Map rank.
 */
native int Shavit_GetRankForTime(int style, float time, int track);

/**
 * Retrieves the time of a record from a specified rank.
 *
 * @param style                     Style.
 * @param rank                      Rank to retrieve the time from.
 * @param track                     Timer track.
 * @return                          Record time. 0.0 if none.
 */
native float Shavit_GetTimeForRank(int style, int rank, int track);

/**
 * Retrieve the WR's stage time.
 *
 * @param track                     Track index.
 * @param style                     Style index.
 * @param stage                     Stage number.
 * @return                          The stage time of the WR run. Can be 0.0 if the WR run didn't hit the stage or if the stage doesn't exist.
 */
native float Shavit_GetStageCPWR(int track, int style, int stage);

/**
 * Retrieve the client's PB stage time.
 *
 * @param client                    Client index.
 * @param track                     Track index.
 * @param style                     Style index.
 * @param stage                     Stage number.
 * @return                          The stage time of the PB run. Can be 0.0 if the PB run didn't hit the stage or if the stage doesn't exist.
 *									-1.0 if stage out of index (it will be happened when server reload the plugin)
 */
native float Shavit_GetStageCPPB(int client, int track, int style, int stage);

/*
 * Used to delete a WR. Used to ensure Shavit_OnWRDeleted is ran.
 *
 * @param style                     Record style.
 * @param track                     Record track.
 * @param map                       Record map.
 * @param accountid                 -1 if recordid is -1. Otherwise you need the WR holder's Steam account ID. ([U:1:x])
 * @param recordid                  -1 to pull ID & accountid from the database.
 * @param delete_sql                If this function should delete the record from the database. False might be useful if you're deleting things in bulk like sm_wipeplayer does.
 * @param update_cache              If this function should update the WR cache & record info. False might be useful if you're deleting things in bulk like sm_wipeplayer does.
 * @noreturn
 */
native void Shavit_DeleteWR(int style, int track, const char[] map, int accountid, int recordid, bool delete_sql, bool update_cache);

/*
 * Used to delete a stage WR. Used to ensure Shavit_OnWRDeleted is ran.
 *
 * @param style                     Record style.
 * @param track                     Record track (should be Track_Main). 
 * @param stage						Record stage.
 * @param map                       Record map.
 * @param accountid                 -1 if recordid is -1. Otherwise you need the WR holder's Steam account ID. ([U:1:x])
 * @param recordid                  -1 to pull ID & accountid from the database.
 * @param delete_sql                If this function should delete the record from the database. False might be useful if you're deleting things in bulk like sm_wipeplayer does.
 * @param update_cache              If this function should update the WR cache & record info. False might be useful if you're deleting things in bulk like sm_wipeplayer does.
 * @noreturn
 */
native void Shavit_DeleteStageWR(int style, int track, int stage, const char[] map, int accountid, int recordid, bool delete_sql, bool update_cache);

/**
 * Deletes all map records for the specified map.
 * Plugin will refresh if map is currently on.
 *
 * @param map                       Map name.
 * @noreturn
 */
native void Shavit_WR_DeleteMap(const char[] map);

/**
 * Get the stage world record time.
 * 
 * @param style						Style to get the WR for.
 * @param stage						Record stage.
 * @return							Stage world record for the specified settings.
 */
native float Shavit_GetStageWorldRecord(int style, int stage);

/**
 * Get the stage world record start velocity.
 * 
 * @param style						Style to get the WR for.
 * @param stage						Record stage.
 * @return							Velocity for the specified settings.
 */
native float Shavit_GetStageWRStartVelocity(int style, int stage);

/**
 * Get the stage world record end velocity.
 * 
 * @param style						Style to get the WR for.
 * @param stage						Record stage.
 * @return							Velocity for the specified settings.
 */
native float Shavit_GetStageWREndVelocity(int style, int stage);

/**
 * Get stage's world record ID in database.
 * 
 * @param style						Style to get the WR for.
 * @param recordid					If record exist, the ID will assign to recordid.
 * @param stage						Record stage.	
 * @noreturn			
 */
native void Shavit_GetStageWRRecordID(int style, int& recordid, int stage);

/**
 * Get the WR's player name on the map on a variable.
 *
 * @param style                     Style to get the WR for.
 * @param wrname                    Reference to the name variable.
 * @param wrmaxlength               Max length for the string.
 * @param stage                     Record stage.
 * @return                          Returns true if the player's name has been cached. False if it hasn't. `wrname` is filled with the player's name if available, otherwise the steamid if the name isn't cached, and lastly the string "none" if neither the name or steamid is available.
 */
native bool Shavit_GetStageWRName(int style, char[] wrname, int wrmaxlength, int stage);

/**
 * Get the stage record time of client.
 * 
 * @param client					Client index.
 * @param style						Style to get the WR for.
 * @param stage						Record stage.
 * @return							Client's stage record for the specified settings.
 */
native float Shavit_GetClientStagePB(int client, int style, int stage);

/**
 * Get the stage world record time.
 * 
 * @param client					Client index.
 * @param style						Style to get the WR for.
 * @param stage						Record stage.
 * @param time						The time assign to client's pb cache. 
 * @noreturn						
 */
native void Shavit_SetClientStagePB(int client, int style, int stage, float time);

/**
 * Get the stage record amount of specific track.
 * 
 * @param style						Style to get the WR for.
 * @param stage						Record stage.
 * @return							Number of rank for specified settings.	
 */
native int Shavit_GetStageRecordAmount(int style, int stage);

/**
 * Get stage rank for a specific time.
 * 
 * @param style						Style to get the WR for.
 * @param time						The time for stage rank. 
 * @param stage						Record stage.
 * @return							The rank for time.						
 */
native int Shavit_GetStageRankForTime(int style, float time, int stage);

/**
 * Get stage record time of specific rank.
 * 
 * @param style						Style to get the WR for.
 * @param rank						Rank to retrieve the time from. 
 * @param stage						Record stage.
 * @return							Time for rank.						
 */
native float Shavit_GetStageTimeForRank(int style, int rank, int stage);

/**
 * Get client's stage completion times.
 * 
 * @param client					Client index.
 * @param style						Style index. 
 * @param stage						Stage number for completions.
 * @return							Numbers of completions.						
 */
native int Shavit_GetClientStageCompletions(int client, int style, int stage);

/**
 * Get the client's stage pb start velocity.
 * 
 * @param client					Client index.
 * @param style						Style index. 
 * @param stage						Stage number for completions.
 * @return							Start velocity.						
 */
native float Shavit_GetClientStageStartVelocity(int client, int style, int stage);

/**
 * Get the client's stage pb end velocity.
 * 
 * @param client					Client index.
 * @param style						Style index. 
 * @param stage						Stage number.
 * @return							End velocity.						
 */
native float Shavit_GetClientStageEndVelocity(int client, int style, int stage);

/**
 * Set the client's stage pb start velocity.
 * 
 * @param client					Client index.
 * @param style						Style index. 
 * @param stage						Stage number.
 * @param vel						Velocity value to set.
 * @noreturn					
 */
native void Shavit_SetClientStageStartVelocity(int client, int style, int stage, float vel);

/**
 * Set the client's stage pb end velocity.
 * 
 * @param client					Client index.
 * @param style						Style index. 
 * @param stage						Stage number.
 * @param vel						Velocity value to set.
 * @noreturn
 */
native void Shavit_SetClientStageEndVelocity(int client, int style, int stage, float vel);


public SharedPlugin __pl_shavit_wr =
{
	name = "shavit-wr",
	file = "shavit-wr.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_wr_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_GetClientCompletions");
	MarkNativeAsOptional("Shavit_GetClientPB");
	MarkNativeAsOptional("Shavit_SetClientPB");
	MarkNativeAsOptional("Shavit_GetRankForTime");
	MarkNativeAsOptional("Shavit_GetRecordAmount");
	MarkNativeAsOptional("Shavit_GetWorldRecord");
	MarkNativeAsOptional("Shavit_GetWRName");
	MarkNativeAsOptional("Shavit_GetWRRecordID");
	MarkNativeAsOptional("Shavit_ReloadLeaderboards");
	MarkNativeAsOptional("Shavit_WR_DeleteMap");
	MarkNativeAsOptional("Shavit_GetTimeForRank");
	MarkNativeAsOptional("Shavit_DeleteWR");
	MarkNativeAsOptional("Shavit_GetStageCPWR");
	MarkNativeAsOptional("Shavit_GetStageCPPB");
	MarkNativeAsOptional("Shavit_GetStageWorldRecord");
	MarkNativeAsOptional("Shavit_GetStageWRRecordID");
	MarkNativeAsOptional("Shavit_GetStageWRName");
	MarkNativeAsOptional("Shavit_GetClientStagePB");
	MarkNativeAsOptional("Shavit_SetClientStagePB");
	MarkNativeAsOptional("Shavit_GetClientStageStartVelocity");
	MarkNativeAsOptional("Shavit_GetClientStageEndVelocity");
	MarkNativeAsOptional("Shavit_SetClientStageStartVelocity");
	MarkNativeAsOptional("Shavit_SetClientStageEndVelocity");
	MarkNativeAsOptional("Shavit_GetClientStageCompletions");
	MarkNativeAsOptional("Shavit_GetClientStartVelocity");
	MarkNativeAsOptional("Shavit_GetClientEndVelocity");
	MarkNativeAsOptional("Shavit_SetClientStartVelocity");
	MarkNativeAsOptional("Shavit_SetClientEndVelocity");
	MarkNativeAsOptional("Shavit_GetWRStartVelocity");
	MarkNativeAsOptional("Shavit_GetWREndVelocity");
	MarkNativeAsOptional("Shavit_GetStageWRStartVelocity");
	MarkNativeAsOptional("Shavit_GetStageWREndVelocity");
	MarkNativeAsOptional("Shavit_DeleteStageWR");
	MarkNativeAsOptional("Shavit_GetStageRankForTime");
	MarkNativeAsOptional("Shavit_GetStageTimeForRank");
	MarkNativeAsOptional("Shavit_GetStageRecordAmount");
}
#endif
