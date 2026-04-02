enum
{
	HUD_Speedometer = 0,
	HUD_SpeedDifference,
	HUD_Energymeter,
	HUD_Timer,
	HUD_TimeDifference,
	HUD_ELEMENTCOUNTS,
};

enum
{ 
	// Speedometer
	Color_Speed_Default = 0,
	Color_SpeedGradient_Gain,
	Color_SpeedGradient_Lose,
	// Speed Difference
	Color_SpeedDifference_Default,
	Color_SpeedDifference_Higher,
	Color_SpeedDifference_Lower,
	// Energymeter
	Color_Energy_Default,
	Color_EnergyGradient_Gain,
	Color_EnergyGradient_Lose,
	Color_Energy_Higher,
	Color_Energy_Lower,
	// Timer
	Color_Timer_Default,
	Color_Timer_Start,	
	Color_Timer_Running,
	Color_Timer_Paused,
	Color_Timer_Practice,
	Color_Timer_Finished_Worse,	
	Color_Timer_Finished_PB,
	Color_Timer_Finished_WR,
	Color_Timer_Stopped,
	// Time Difference
	Color_TimeDifference_Defualt,
	Color_TimeDifference_Faster,
	Color_TimeDifference_Slower,
	Color_TimeDifference_Gain,
	Color_TimeDifference_Lose,
	Color_Size,	// 24
};

enum
{ 
	ColorLogic_None = 0,
	ColorLogic_First,
	ColorLogic_Second,
};

enum
{ 
	DisplayLogic_Default = 0,
	DisplayLogic_First,
	DisplayLogic_Second,
};

#define MAX_COLORS 30
#define MAX_ELEMENTS 5

