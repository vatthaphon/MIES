#pragma rtGlobals=3		// Use modern global access method and strict wave access.

Function ITC_DataAcq(DeviceType, DeviceNum, panelTitle)
	variable DeviceType, DeviceNum
	string panelTitle
	string cmd
	variable i = 0
	//variable StopCollectionPoint = (DC_CalculateITCDataWaveLength(panelTitle)/4 // + DC_ReturnTotalLengthIncrease(PanelTitle)/4)
	variable ADChannelToMonitor = (DC_NoOfChannelsSelected("DA", "Check", panelTitle))
	string WavePath = HSU_DataFullFolderPathString(PanelTitle)
	NVAR ITCDeviceIDGlobal = $WavePath + ":ITCDeviceIDGlobal"
	wave ITCDataWave = $WavePath + ":ITCDataWave", ITCFIFOAvailAllConfigWave = $WavePath + ":ITCFIFOAvailAllConfigWave"//, ChannelConfigWave, UpdateFIFOWave, RecordedWave
	variable stopCollectionPoint = dimsize(ITCDataWave, 0) / 4
	string ITCDataWavePath = WavePath + ":ITCDataWave", ITCFIFOAvailAllConfigWavePath= WavePath + ":ITCFIFOAvailAllConfigWave"
	string ITCChanConfigWavePath = WavePath + ":ITCChanConfigWave"
	string ITCFIFOPositionAllConfigWavePth = WavePath + ":ITCFIFOPositionAllConfigWave"
	string oscilloscopeSubwindow = panelTitle + "#oscilloscope"
	string ResultsWavePath = WavePath + ":ResultsWave"
	make /O /I /N = 4 $ResultsWavePath 
	doupdate
	// open ITC device
	//sprintf cmd, "ITCOpenDevice %d, %d", DeviceType, DeviceNum
	//Execute cmd
	
	sprintf cmd, "ITCSelectDevice %d" ITCDeviceIDGlobal
	execute cmd
		
	sprintf cmd, "ITCconfigAllchannels, %s, %s" ITCChanConfigWavePath, ITCDataWavePath
	execute cmd
	do

		sprintf cmd, "ITCUpdateFIFOPositionAll , %s" ITCFIFOPositionAllConfigWavePth // I have found it necessary to reset the fifo here, using the /r=1 with start acq doesn't seem to work
		execute cmd// this also seems necessary to update the DA channel data to the board!!
		sprintf cmd, "ITCStartAcq"// /f/r=0/z=0 -1,0,1,1"//   
		Execute cmd	
			do
				sprintf cmd, "ITCFIFOAvailableALL/z=0 , %s" ITCFIFOAvailAllConfigWavePath
				Execute cmd	
				ITCDataWave[0][0] += 0
				doupdate /w = $oscilloscopeSubwindow
				//doxopidle
			while (ITCFIFOAvailAllConfigWave[ADChannelToMonitor][2] < StopCollectionPoint)// 
		//Check Status
		sprintf cmd, "ITCGetState /R /O /C /E %s" ResultsWavePath
		Execute cmd
		sprintf cmd, "ITCStopAcq /z = 0"
		Execute cmd
		itcdatawave[0][0] += 0//runs arithmatic on data wave to force onscreen update 
		doupdate
		sprintf cmd, "ITCConfigChannelUpload /f /z = 0"//AS Long as this command is within the do-while loop the number of cycles can be repeated		
		Execute cmd
		i += 1
	while (i < 1)// 
	
	//sprintf cmd, "ITCCloseAll" 
	//execute cmd

	ControlInfo /w = $panelTitle Check_Settings_SaveData
	If(v_value == 0)
		DM_SaveITCData(panelTitle)
	endif
	
	 DM_ScaleITCDataWave(panelTitle)
End

//======================================================================================
Function ITC_BkrdDataAcq(DeviceType, DeviceNum, panelTitle)
	variable DeviceType, DeviceNum
	string panelTitle
	string cmd
	variable i = 0
	//variable /G StopCollectionPoint = (DC_CalculateITCDataWaveLength(panelTitle)/4) + DC_ReturnTotalLengthIncrease(PanelTitle)
	variable /G ADChannelToMonitor = (DC_NoOfChannelsSelected("DA", "Check", panelTitle))
	string /G panelTitleG = panelTitle
	doupdate
	string WavePath = HSU_DataFullFolderPathString(PanelTitle)
	wave ITCDataWave = $WavePath+ ":ITCDataWave"
	variable /G StopCollectionPoint = dimsize(ITCDataWave, 0) / 5 
	wave ITCFIFOAvailAllConfigWave = $WavePath + ":ITCFIFOAvailAllConfigWave"//, ChannelConfigWave, UpdateFIFOWave, RecordedWave
	
	string ITCDataWavePath = WavePath + ":ITCDataWave", ITCFIFOAvailAllConfigWavePath = WavePath + ":ITCFIFOAvailAllConfigWave"
	string ITCChanConfigWavePath = WavePath + ":ITCChanConfigWave"
	string ITCFIFOPositionAllConfigWavePth = WavePath + ":ITCFIFOPositionAllConfigWave"
	// open ITC device
	
	//sprintf cmd, "ITCOpenDevice %d, %d", DeviceType, DeviceNum
		//Execute cmd	
	NVAR ITCDeviceIDGlobal = $WavePath + ":ITCDeviceIDGlobal"
	sprintf cmd, "ITCSelectDevice %d" ITCDeviceIDGlobal
	execute cmd	
		
	sprintf cmd, "ITCconfigAllchannels, %s, %s" ITCChanConfigWavePath, ITCDataWavePath
		execute cmd
	sprintf cmd, "ITCUpdateFIFOPositionAll , %s" ITCFIFOPositionAllConfigWavePth// I have found it necessary to reset the fifo here, using the /r=1 with start acq doesn't seem to work
		execute cmd// this also seems necessary to update the DA channel data to the board!!
	sprintf cmd, "ITCStartAcq" 
		Execute cmd	
	ITC_StartBckgrdFIFOMonitor()
	
	End
//======================================================================================
Function ITC_StopDataAcq()
	variable DeviceType, DeviceNum
	string cmd
	NVAR StopCollectionPoint, ADChannelToMonitor
	SVAR panelTitleG
	string WavePath = HSU_DataFullFolderPathString(PanelTitleG)
	wave ITCDataWave = $WavePath + ":ITCDataWave"
	string CountPath = WavePath + ":count"

	sprintf cmd, "ITCStopAcq /z = 0"
	Execute cmd

	itcdatawave[0][0] += 0//runs arithmatic on data wave to force onscreen update 
	doupdate
	
	sprintf cmd, "ITCConfigChannelUpload /f /z = 0"//AS Long as this command is within the do-while loop the number of cycles can be repeated		
	Execute cmd	
	
	//sprintf cmd, "ITCCloseAll" 
	//execute cmd
	
	ControlInfo /w = $panelTitleG Check_Settings_SaveData
	If(v_value == 0)
		DM_SaveITCData(panelTitleG)// saving always comes before scaling - there are two independent scaling steps
	endif
	
	 DM_ScaleITCDataWave(panelTitleG)
	if(exists(CountPath) == 0)//If the global variable count does not exist, it is the first trial of repeated acquisition
	controlinfo /w = $panelTitleG Check_DataAcq1_RepeatAcq
		if(v_value == 1)//repeated aquisition is selected
			RA_Start(PanelTitleG)
		else
			DAP_StopButtonToAcqDataButton(panelTitleG)
			NVAR/z DataAcqState = $wavepath + ":DataAcqState"
			DataAcqState = 0
		endif
	else
		//print "about to initiate RA_BckgTPwithCallToRACounter(panelTitleG)"
		RA_BckgTPwithCallToRACounter(panelTitleG)//FUNCTION THAT ACTIVATES BCKGRD TP AND THEN CALLS REPEATED ACQ XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
	endif
	
	//killvariables /z StopCollectionPoint, ADChannelToMonitor
	//killvariables /z  ADChannelToMonitor
	//killstrings /z PanelTitleG
END
//======================================================================================
Function ITC_ZeroTheInstrutechDevice()
string cmd
sprintf cmd, "ITCSetDac /z =0 0, 0;ITCSetDac /z = 0 1, 0;ITCSetDac /z = 0 2, 0;ITCSetDac /z =0 3, 0;ITCSetDac /z = 0 4, 0;ITCSetDac /z = 0 5, 0;ITCSetDac /z = 0 6, 0;ITCSetDac /z = 0 7, 0"
execute cmd
END
//======================================================================================
Function ITC_StartBckgrdFIFOMonitor()
	CtrlNamedBackground ITC_FIFOMonitor, period = 2, proc = ITC_FIFOMonitor
	CtrlNamedBackground ITC_FIFOMonitor, start
End

Function ITC_FIFOMonitor(s)
	STRUCT WMBackgroundStruct &s
	NVAR StopCollectionPoint, ADChannelToMonitor
	SVAR panelTitleG
	String cmd
	string WavePath = HSU_DataFullFolderPathString(PanelTitleG)
	Wave ITCDataWave = $WavePath + ":ITCDataWave", ITCFIFOAvailAllConfigWave= $WavePath + ":ITCFIFOAvailAllConfigWave"
	string ITCFIFOAvailAllConfigWavePath = WavePath + ":ITCFIFOAvailAllConfigWave"
	sprintf cmd, "ITCFIFOAvailableALL /z = 0 , %s" ITCFIFOAvailAllConfigWavePath
	Execute cmd	
	ITCDataWave[0][0] += 0//forces on screen update
	string OscilloscopeSubWindow = panelTitleG + "#oscilloscope"
	doupdate /w = $OscilloscopeSubWindow
	if(ITCFIFOAvailAllConfigWave[ADChannelToMonitor][2] >= StopCollectionPoint)	
		print "stopped data acq"
		ITC_StopDataAcq()
		ITC_STOPFifoMonitor()
	endif
				
	return 0
End



Function ITC_STOPFifoMonitor()
CtrlNamedBackground ITC_FIFOMonitor, stop
End
//======================================================================================


Function ITC_StartBackgroundTimer(RunTimePassed,FunctionNameAPassedIn, FunctionNameBPassedIn,  FunctionNameCPassedIn, panelTitle)//Function name is the name of the function you want to run after run time has elapsed
	Variable RunTimePassed//how long you want the background timer to run in seconds
	String FunctionNameAPassedIn, FunctionNameBPassedIn, FunctionNameCPassedIn, panelTitle
	String /G FunctionNameA = FunctionNameAPassedIn
	String /G FunctionNameB = FunctionNameBPassedIn
	String /G FunctionNameC = FunctionNameCPassedIn
	String /G PanelTitleG = panelTitle
	Variable numTicks = 15		// Run every quarter second (15 ticks)
	Variable/G Start = ticks
	Variable/G RunTime = (RunTimePassed*60)
	CtrlNamedBackground ITC_Timer, period = 5, proc = ITC_Timer
	CtrlNamedBackground ITC_Timer, start
End

Function ITC_Timer(s)
	STRUCT WMBackgroundStruct &s
	SVAR panelTitleG
	NVAR Start, RunTime
	variable TimeLeft
	
	variable ElapsedTime = (ticks - Start)
	
	TimeLeft = abs(((RunTime - (ElapsedTime)) / 60))
	if(TimeLeft < 0)
		timeleft = 0
	endif
	ValDisplay valdisp_DataAcq_ITICountdown win = $panelTitleG, value = _NUM:TimeLeft
	
	if(ElapsedTime >= RunTime)
		ITC_StopBackgroundTimerTask()
	endif
	//printf "NextRunTicks %d", s.nextRunTicks
	return 0
End

Function ITC_StopBackgroundTimerTask()
	SVAR FunctionNameA
	SVAR FunctionNameB
	SVAR FunctionNameC
	CtrlNamedBackground ITC_Timer, stop // had incorrect background procedure name
	Execute FunctionNameA
 	Execute FunctionNameB
	//Execute FunctionNameC
	//killvariables/z Start, RunTime
	//Killstrings/z FunctionNameA, FunctionNameB, FunctionNameC
End
//======================================================================================

Function ITC_StartBackgroundTestPulse(DeviceType, DeviceNum, panelTitle)
	variable DeviceType, DeviceNum	// ITC-1600
	string panelTitle
	string WavePath = HSU_DataFullFolderPathString(PanelTitle)
	string /G PanelTitleG //$WavePath + ":PanelTitleG" = panelTitle
	SVAR panelTitleG// = $WavePath + ":PanelTitleG"
	string cmd
	variable i = 0
	variable /G StopCollectionPoint = DC_CalculateITCDataWaveLength(panelTitle) / 5
	NVAR stopcollectionpoint
	variable /G ADChannelToMonitor = (DC_NoOfChannelsSelected("DA", "Check", panelTitle))
	variable /G BackgroundTPCount = 0
	doupdate
	wave ITCDataWave = $WavePath + ":ITCDataWave", ITCFIFOAvailAllConfigWave = $WavePath + ":ITCFIFOAvailAllConfigWave"//, ChannelConfigWave, UpdateFIFOWave, RecordedWave
	string  ITCDataWavePath = WavePath + ":ITCDataWave", ITCChanConfigWavePath = WavePath + ":ITCChanConfigWave"
	// open ITC device
	//sprintf cmd, "ITCOpenDevice %d, %d", DeviceType, DeviceNum
	//Execute cmd	
	NVAR ITCDeviceIDGlobal = $WavePath + ":ITCDeviceIDGlobal"
	sprintf cmd, "ITCSelectDevice %d" ITCDeviceIDGlobal
	execute cmd
	
	sprintf cmd, "ITCconfigAllchannels, %s, %s" ITCChanConfigWavePath, ITCDataWavePath
	execute cmd
	CtrlNamedBackground TestPulse, period = 2, proc = ITC_TestPulseFunc
	CtrlNamedBackground TestPulse, start

End
//======================================================================================

Function ITC_TestPulseFunc(s)
	STRUCT WMBackgroundStruct &s
	NVAR StopCollectionPoint, ADChannelToMonitor, BackgroundTPCount
	String cmd, Keyboard
	//string WavePath = HSU_DataFullFolderPathString(PanelTitle)
	SVAR PanelTitleG// = $WavePath + ":panelTitleG"
	string paneltitle = panelTitleG
	string WavePath = HSU_DataFullFolderPathString(PanelTitle)
	wave ITCDataWave = $WavePath + ":ITCDataWave", ITCFIFOAvailAllConfigWave = $WavePath + ":ITCFIFOAvailAllConfigWave"
	string  ITCFIFOPositionAllConfigWavePth = WavePath + ":ITCFIFOPositionAllConfigWave"
	string ITCFIFOAvailAllConfigWavePath = WavePath + ":ITCFIFOAvailAllConfigWave"
	string ResultsWavePath = WavePath + ":ResultsWave"
	string CountPath = WavePath + ":count"
	string oscilloscopeSubWindow = panelTitle + "#oscilloscope"
		sprintf cmd, "ITCUpdateFIFOPositionAll , %s" ITCFIFOPositionAllConfigWavePth // I have found it necessary to reset the fifo here, using the /r=1 with start acq doesn't seem to work
		execute cmd// this also seems necessary to update the DA channel data to the board!!
		sprintf cmd, "ITCStartAcq"
		Execute cmd	
		
		 //ITC_StartBckgrdFIFOMonitor()
			do
				sprintf cmd, "ITCFIFOAvailableALL /z = 0 , %s" ITCFIFOAvailAllConfigWavePath
				Execute cmd	
				//doxopidle
			while (ITCFIFOAvailAllConfigWave[ADChannelToMonitor][2] < StopCollectionPoint)// 5000 IS CHOSEN AS A POINT THAT IS A BIT LARGER THAN THE OUTPUT DATA
		//Check Status
		sprintf cmd, "ITCGetState /R /O /C /E %s" ResultsWavePath
		Execute cmd
		sprintf cmd, "ITCStopAcq /z = 0"
		Execute cmd
		sprintf cmd, "ITCConfigChannelUpload /f /z = 0"//AS Long as this command is within the do-while loop the number of cycles can be repeated		
		Execute cmd
		DM_CreateScaleTPHoldingWave(panelTitle)
		TP_ClampModeString(panelTitle)
		TP_Delta(panelTitle, WavePath + ":TestPulse") 
		//itcdatawave[0][0] += 0// runs arithmatic on data wave to force onscreen update 
		//doupdate	
		BackgroundTPCount += 1
		if(mod(BackgroundTPCount,30) == 0 || BackgroundTPCount == 1)
			ModifyGraph /w = $oscilloscopeSubWindow Live = 0
			ModifyGraph /w = $oscilloscopeSubWindow Live = 1
		endif
		if(exists(countPath) == 0)// uses the presence of a global variable that is created by the activation of repeated aquisition to determine if the space bar can turn off the TP
			Keyboard = KeyboardState("")
			if (cmpstr(Keyboard[9], " ") == 0)	// Is space bar pressed (note the space between the quotations)?
				beep 
				ITC_STOPTestPulse(panelTitle)
			endif
		endif
	return 0
	
End
//======================================================================================

Function ITC_STOPTestPulse(panelTitle)
	string panelTitle
	string cmd
	CtrlNamedBackground TestPulse, stop
	//sprintf cmd, "ITCCloseAll" 
	//execute cmd

	controlinfo /w = $panelTitle check_Settings_ShowScopeWindow
	if(v_value == 0)
		DAP_SmoothResizePanel(-340, panelTitle)
		setwindow $panelTitle + "#oscilloscope", hide = 1
	endif

	DAP_RestoreTTLState(panelTitle)
	//killwaves /z root:WaveBuilder:SavedStimulusSets:DA:TestPulse// this line generates an error. hence the /z. not sure why.
	ControlInfo /w = $panelTitle StartTestPulseButton
	if(V_disable == 2) // 0 = normal, 1 = hidden, 2 = disabled, visible
		Button StartTestPulseButton, win = $panelTitle, disable = 0
	endif
	if(V_disable == 3) // 0 = normal, 1 = hidden, 2 = disabled, visible
		V_disable = V_disable & ~0x2
		Button StartTestPulseButton, win = $panelTitle, disable =  V_disable
	endif
	killvariables /z  StopCollectionPoint, ADChannelToMonitor, BackgroundTaskActive
	killstrings /z PanelTitleG
End

//======================================================================================


//ITC_StartBackgroundTestPulse();ITC_StartBackgroundTimer(20, "ITC_STOPTestPulse()")  This line of code starts the tests pulse and runs it for 20 seconds

Function ITC_StartTestPulse(DeviceType, DeviceNum, panelTitle)
	variable DeviceType, DeviceNum
	string panelTitle
	string cmd
	variable i = 0
	variable StopCollectionPoint = DC_CalculateITCDataWaveLength(panelTitle)/5
	variable ADChannelToMonitor = (DC_NoOfChannelsSelected("DA", "Check", panelTitle))
	string oscilloscopeSubWindow = panelTitle + "#oscilloscope"
	//ModifyGraph /w = $oscilloscopeSubWindow Live =0
	//doupdate /w = $oscilloscopeSubWindow
	//ModifyGraph /w = $oscilloscopeSubWindow Live =1
	string WavePath = HSU_DataFullFolderPathString(PanelTitle)
	
	//wave ITCChanConfigWave = $WavePath + ":ITCChanConfigWave"
	string ITCChanConfigWavePath = WavePath + ":ITCChanConfigWave"
	
	//wave ITCDataWave = $WavePath + ":ITCDataWave"
	string ITCDataWavePath = WavePath + ":ITCDataWave"
	
	wave ITCFIFOAvailAllConfigWave = $WavePath+ ":ITCFIFOAvailAllConfigWave"//, ChannelConfigWave, UpdateFIFOWave, RecordedWave
	string ITCFIFOAvailAllConfigWavePath = WavePath+ ":ITCFIFOAvailAllConfigWave"
	
	//wave ITCFIFOPositionAllConfigWave = $WavePath + ":ITCFIFOPositionAllConfigWave"
	string ITCFIFOPositionAllConfigWavePth = WavePath + ":ITCFIFOPositionAllConfigWave"
	
	//wave ResultsWave = $WavePath + ":ResultsWave"
	string ResultsWavePath = WavePath + ":ResultsWave"
	
	string Keyboard

	make /O /I /N = 4 $ResultsWavePath 
	doupdate
	// open ITC device
	//sprintf cmd, "ITCOpenDevice %d, %d", DeviceType, DeviceNum
	//Execute cmd	
	
	NVAR ITCDeviceIDGlobal = $WavePath + ":ITCDeviceIDGlobal"
	sprintf cmd, "ITCSelectDevice %d" ITCDeviceIDGlobal
	execute cmd
	
	sprintf cmd, "ITCconfigAllchannels, %s, %s" ITCChanConfigWavePath, ITCDataWavePath
	execute cmd
	do

		sprintf cmd, "ITCUpdateFIFOPositionAll , %s" ITCFIFOPositionAllConfigWavePth// I have found it necessary to reset the fifo here, using the /r=1 with start acq doesn't seem to work
		execute cmd // this also seems necessary to update the DA channel data to the board!!
		sprintf cmd, "ITCStartAcq"// /f/r=0/z=0 -1,0,1,1"//   
		Execute cmd	
			do
				sprintf cmd, "ITCFIFOAvailableALL /z = 0 , %s" ITCFIFOAvailAllConfigWavePath
				Execute cmd	
				//doxopidle
			while (ITCFIFOAvailAllConfigWave[ADChannelToMonitor][2] < StopCollectionPoint)// 
		//Check Status
		sprintf cmd, "ITCGetState /R /O /C /E %s" ResultsWavePath
		Execute cmd
		sprintf cmd, "ITCStopAcq /z = 0"
		Execute cmd
		DM_CreateScaleTPHoldingWave(panelTitle)
		TP_ClampModeString(panelTitle)
		TP_Delta(panelTitle, WavePath + ":TestPulse") 
		doupdate
		//itcdatawave[0][0] += 0//runs arithmatic on data wave to force onscreen update 
		//doupdate
		sprintf cmd, "ITCConfigChannelUpload /f /z = 0"//AS Long as this command is within the do-while loop the number of cycles can be repeated		
		Execute cmd
		if(mod(i, 50) == 0)
			ModifyGraph /w = $oscilloscopeSubWindow Live = 0
			ModifyGraph /w = $oscilloscopeSubWindow Live = 1
		endif
		i += 1	
		Keyboard = KeyboardState("")
	while (cmpstr(Keyboard[9], " ") != 0)// 
	
	//sprintf cmd, "ITCCloseAll" 
	//execute cmd

	DAP_RestoreTTLState(panelTitle)
	
	ControlInfo /w = $panelTitle StartTestPulseButton
	if(V_disable == 2)
		Button StartTestPulseButton, win = $panelTitle, disable = 0
	endif

END
//======================================================================================

Function ITC_SingleADReading(Channel, panelTitle)//channels 16-23 are asynch channels on ITC1600
	variable Channel
	string panelTitle
	variable ChannelValue
	string cmd
	string WavePath = HSU_DataFullFolderPathString(PanelTitle)
	make /o /n = 1 $WavePath + ":AsyncChannelData"
	string AsyncChannelDataPath = WavePath+":AsyncChannelData"
	wave AsyncChannelData = $AsyncChannelDataPath
	sprintf cmd, "ITCReadADC /V = 1 %d, %s" Channel, AsyncChannelDataPath
	execute cmd
	ChannelValue = AsyncChannelData[0]
	print channelValue
	killwaves /f AsyncChannelData
	return ChannelValue
End 

//======================================================================================

Function ITC_ADDataBasedWaveNotes(DataWave, DeviceType, DeviceNum,panelTitle)
	Wave DataWave
	variable DeviceType, DeviceNum
	string panelTitle
	// This function takes about 0.9 seconds to run
	// this is the wave that the note gets appended to. The note contains the async ad channel value and info
	//variable starttime=ticks
	string AsyncChannelState = DC_ControlStatusListString("AsyncAD", "check", panelTitle)
	variable i
	variable TotAsyncChannels = itemsinlist(AsyncChannelState,";")
	variable RawChannelValue
	string cmd
	string SetVar_Title, Title
	string SetVar_gain, Measurement
	string SetVar_Unit, Unit
	string WaveNote = ""
	
	controlinfo /w = $PanelTitle popup_MoreSettings_DeviceType // "ITC16" (0), "ITC18" (1), "ITC1600" (2), "ITC00" (3), "ITC16USB" (4), "ITC18USB" (5) 
	DeviceType = v_value - 1
	variable DeviceChannelOffset // used to select asych ad channels on itc 1600 and standard ad channels on other itc devices.
	If(DeviceType == 2)
		DeviceChannelOffset = 15
	else
		DeviceChannelOffset = 0
	endif
	
	sprintf cmd, "ITCOpenDevice %d, %d", DeviceType, DeviceNum
	Execute cmd	
	
	do
		if(str2num(stringfromlist(i, AsyncChannelState,";")) == 1)
		RawChannelValue=ITC_SingleADReading(i +DeviceChannelOffset, panelTitle)//Async channels start at channel 16 on ITC 1600, needs to be a diff value constant for ITC18
		
			if(i < 10)
				 SetVar_title = "SetVar_Async_Title_0" + num2str(i)
				 SetVar_gain = "SetVar_AsyncAD_Gain_0" + num2str(i)
				 SetVar_Unit = "SetVar_Async_Unit_0" + num2str(i)
			else
				 SetVar_title = "SetVar_Async_Title_" + num2str(i)
				 SetVar_gain = "SetVar_AsyncAD_Gain_" + num2str(i)
				 SetVar_Unit = "SetVar_Async_Unit_" + num2str(i)
			endif 
			
			controlInfo /w = $panelTitle $SetVar_title
			title = s_value
			controlInfo /w = $panelTitle $SetVar_gain
			Measurement = num2str(RawChannelValue / v_value)//(v_value * RawChannelValue)
			ITC_SupportSystemAlarm(i, v_value * RawChannelValue, title, panelTitle)
			controlInfo /w = $panelTitle $SetVar_Unit
			Unit = s_value
			WaveNote = title + " " + Measurement + " " + Unit
			note DataWave, WaveNote
		endif
		i += 1 
	while(i < TotAsyncChannels)
	
	sprintf cmd, "ITCCloseAll" 
	execute cmd
	//print (ticks - starttime) / 60

End
//======================================================================================
Function ITC_SupportSystemAlarm(Channel, Measurement, MeasurementTitle, panelTitle)
variable Channel, Measurement
string MeasurementTitle, panelTitle
String CheckAlarm, SetVarTitle, SetVarMin, SetVarMax, Title
variable ParamMin, ParamMax

if(channel < 10)
	CheckAlarm = "check_Async_Alarm_0" + num2str(channel)
	SetVarMin = "setvar_Async_min_0" + num2str(channel)	
	SetVarMax = "setvar_Async_max_0" + num2str(channel)	
else
	CheckAlarm = "check_Async_Alarm_" + num2str(channel)
	SetVarMin = "setvar_Async_min_" + num2str(channel)				
	SetVarMax = "setvar_Async_max_" + num2str(channel)
endif

ControlInfo /W = $panelTitle $CheckAlarm
if(v_value == 1)
	ControlInfo /W = $panelTitle $SetVarMin
	ParamMin = v_value
	ControlInfo /W = $panelTitle $SetVarMax
	ParamMax = v_value
	print measurement
	if(Measurement >= ParamMax || Measurement <= ParamMin)
		beep
		print time() + " !!!!!!!!!!!!! " + MeasurementTitle + " has exceeded max/min settings" + " !!!!!!!!!!!!!"
		beep
	endif
endif

End