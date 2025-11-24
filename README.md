# Shavit Surf timer (CS:S ONLY) 

#### 　[ Version 1.0.6 ](https://github.com/bhopppp/Shavit-Surf-Timer/releases/tag/v1.0.6)
#### 　[( click to download )](https://github.com/bhopppp/Shavit-Surf-Timer/releases/download/v1.0.6/Shavit-SurfTimer-v1.0.6.zip)

## About this surf timer
- This timer is based on [Shavit BhopTimer](https://github.com/shavitush/bhoptimer).

# Requirements:
- [Sourcemod v1.12](https://www.sourcemod.net/downloads.php?branch=stable) or higher version required.
- [Metamod v1.11](https://www.sourcemm.net/downloads.php?branch=stable) or higher version required.
- MySQL 8.0, MariaDB 10.2, SQLite 3.25 or higher version required.
- Extension `sm_closestpos` for shavit-ghost2 plugin. [Github](https://github.com/rtldg/sm_closestpos)
- Extension `sm-ripext` for shavit-wrsh plugin. [Github](https://github.com/ErikMinekus/sm-ripext)
- Extension `eventqueuefix` to make surf EndTouch event clean properly. [Github](https://github.com/srcwr/eventqueuefixfix)


## Whats different from shavit bhop timer?

### - Multi-functionality stage system for staged maps
- Save stage replay separately for WR
- Save stage record, and calculate every data separately
- Use stage zone as a start zone, which allow player finish each stage separately
　
### - Checkpoint zone for linear maps
- Save checkpoint times
- Enable to check checkpoint time for each record

### - Advance zone prespeed limit control system
- Sperately control speed limit style to each start zone

### - Zone filter system for better map zoning
- Zones are capble to handle map with complex gameplay 

### - No fail staged map replay & backup system
- Trim failure attempts frames & AFK frames
- Automatically backup old replay when a new one is going to save

 
### - More feature for better surf experience
- Track timer repeat feature: Repeat player's timer in a single stage or bonus
- Center Speed HUD: Fully customize and work with surf timer
- Ramp speed HUD: Show speed when player touch / leave a ramp
- Teleport player back to stage start zone: Use command `!back` to back to stage start
- Customize noclip speed: Use `!noclipspeed` to change noclip speed
- Allow to set max velocity for each map
- Datail Comparison between personal best and world record by using command `!cpr`
- shavit-wrsh plugin to see top records in surfheaven
- shavit-ghost2 plugin to display route with customize options
- Create zone in 3 point (xyz)
- Control most of chat message in a menu. use `sm_message` to open it. 
- shavit-personalreplay plugin to save 5 replays in cache for players
- plugin `shavit-savestate` Allow player to save / load thier timer for each style pre map

## Appreciate that if someone can send me some suggestion or feedback

### See change logs in [CHANGELOG.md](https://github.com/bhopppp/Shavit-Surf-Timer/blob/master/CHANGELOG.md)
