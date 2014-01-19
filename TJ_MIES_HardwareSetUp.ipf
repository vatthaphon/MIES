#pragma rtGlobals=3		// Use modern global access method and strict wave access.
//=====================================================================================
// ITC HARDWARE CONFIGURATION FUNCTIONS
Function HSU_QueryITCDevice(PanelTitle)
	string PanelTitle
	variable DeviceType, DeviceNumber
	string cmd
	controlinfo/w=$PanelTitle popup_MoreSettings_DeviceType
	DeviceType=v_value-1
	controlinfo/w=$PanelTitle popup_moreSettings_DeviceNo
	DeviceNumber=v_value-1
	
	sprintf cmd, "ITCOpenDevice %d, %d", DeviceType, DeviceNumber
	Execute cmd
	//sprintf cmd, "ITCGetState /E=1 ResultWave"
	//Execute cmd
	DoAlert/t="Ready light check"  0, "Click \"OK\" when finished checking device"
	
	sprintf cmd, "ITCCloseDevice" 
	execute cmd
End

Function HSU_ButtonProc_Settings_OpenDev(ctrlName) : ButtonControl
	String ctrlName
	getwindow kwTopWin wtitle
	HSU_QueryITCDevice(s_value)
End

Function HSU_ButtonProc_LockDev(ctrlName) : ButtonControl
	String ctrlName
	getwindow kwTopWin wtitle
	HSU_LockDevice(s_value)
End

Function HSU_LockDevice(panelTitle)
	string PanelTitle
	string deviceType
	variable deviceNo
	PopupMenu popup_MoreSettings_DeviceType win=$PanelTitle, disable=2
	PopupMenu popup_moreSettings_DeviceNo win=$PanelTitle, disable=2
	Button button_SettingsPlus_LockDevice win=$PanelTitle, disable=2
	HSU_DataFolderPathDisplay(PanelTitle)
	HSU_CreateDataFolderForLockdDev(PanelTitle)
	Button button_SettingsPlus_unLockDevic win=$PanelTitle, disable=0
	controlinfo /W = $panelTitle popup_MoreSettings_DeviceType
	deviceType=s_value
	controlinfo /W = $panelTitle popup_moreSettings_DeviceNo
	deviceNo=v_value-1
	dowindow /W = $panelTitle /C $DeviceType + "_Dev_" + num2str(DeviceNo)
	GlobalListStrngOfITCPanelTitles()//checks to see if list string of panel titles exists, if it doesn't in creates it (in the root: folder)
	ListOfITCPanels()
	MakeGlobalsAndWaves(DeviceType + "_Dev_" + num2str(DeviceNo))
End

Function HSU_DataFolderPathDisplay(PanelTitle)
	string PanelTitle
	groupbox group_SettingsPlus_FolderPath win=$PanelTitle, title="Data folder path = "+HSU_DataFullFolderPathString(PanelTitle)
End

Function HSU_CreateDataFolderForLockdDev(PanelTitle)
	string PanelTitle
	string FullFolderPath=HSU_DataFullFolderPathString(PanelTitle)
	string BaseFolderPath=HSU_BaseFolderPathString(PanelTitle)
	Newdatafolder/o $BaseFolderPath
	Newdatafolder/o $FullFolderPath
	Newdatafolder/o $FullFolderPath+":Data"
	Newdatafolder/o $FullFolderPath+":TestPulse"
End

Function/t HSU_BaseFolderPathString(PanelTitle)
	string PanelTitle
	string DeviceTypeList = "ITC16;ITC18;ITC1600;ITC00;ITC16USB;ITC18USB"  
	variable DeviceType
	string BaseFolderPath
	controlinfo/w=$PanelTitle popup_MoreSettings_DeviceType
	DeviceType=v_value-1
	BaseFolderPath="root:"+stringfromlist(DeviceType,DeviceTypeList,";")
	return BaseFolderPath
End

Function/t HSU_DataFullFolderPathString(PanelTitle)
	string PanelTitle
	string DeviceTypeList = "ITC16;ITC18;ITC1600;ITC00;ITC16USB;ITC18USB"  
	variable DeviceType, DeviceNumber
	string FolderPath
	controlinfo/w=$PanelTitle popup_MoreSettings_DeviceType
	DeviceType=v_value-1
	controlinfo/w=$PanelTitle popup_moreSettings_DeviceNo
	DeviceNumber=v_value-1
	FolderPath="root:"+stringfromlist(DeviceType,DeviceTypeList,";")+":Device"+num2str(DeviceNumber)
	return FolderPath
End

Function HSU_ButProc_Hrdwr_UnlckDev(ctrlName) : ButtonControl
	String ctrlName
	getwindow kwTopWin wtitle
	HSU_UnlockDevSelection(s_value)
End

Function HSU_UnlockDevSelection(PanelTitle)
	string PanelTitle
	PopupMenu popup_MoreSettings_DeviceType win=$PanelTitle, disable=0
	PopupMenu popup_moreSettings_DeviceNo win=$PanelTitle, disable=0
	Button button_SettingsPlus_LockDevice win=$PanelTitle, disable=0
	Button button_SettingsPlus_unLockDevic win=$PanelTitle, disable=2
	GroupBox group_SettingsPlus_FolderPath win=$PanelTitle, title="Lock device to set data folder path"
End

Function HSU_DeviceLockCheck(PanelTitle)
	string PanelTitle
	variable DeviceLockStatus
	controlinfo /W = $PanelTitle button_SettingsPlus_LockDevice
	if(V_disable==1)
	DoAlert/t="Hardware Status"  0, "A ITC device must be locked (see Hardware tab) to proceed"
	DeviceLockStatus=1
	else
	DeviceLockStatus=0	
	endif
	return DeviceLockStatus
End

Function PopMenuProc_Hrdwr_DevTypeCheck(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	getwindow kwTopWin wtitle
	HSU_IsDeviceTypeConnected(s_value)
End

Function HSU_IsDeviceTypeConnected(PanelTitle)
	string PanelTitle
	string cmd
	controlinfo/w=$panelTitle popup_MoreSettings_DeviceType
	variable DeviceType=v_value-1
	make  /O /I /N=1 localwave
	sprintf cmd, "ITCGetDevices /Z=0 %d, localWave" DeviceType
	execute cmd
	if(LocalWave[0]==0)
		button button_SettingsPlus_PingDevice win=$PanelTitle, disable=2
	else
		button button_SettingsPlus_PingDevice win=$PanelTitle, disable=0
	endif
	killwaves localwave
End
// below functions are used to create a list of the ITC panels. This list is will be used by functions that need to update items that are common to different panels.
// for example: DAC popup lists, TTL popup lists
Function GlobalListStrngOfITCPanelTitles()
	If(exists("ITCPanelTitleList")==0)
	String/G root:ITCPanelTitleList
	endif
End


Function ListOfITCPanels()
SVAR ITCPanelTitleList = root:ITCPanelTitleList
ITCPanelTitleList = winlist("ITC*",";", "WIN:64") 
End

Function MakeGlobalsAndWaves(panelTitle)// makes the necessary parameters for the locked device to function.
	string panelTitle
	string WavePath=HSU_DataFullFolderPathString(PanelTitle)
	string ChanAmpAssignPath = WavePath + ":ChanAmpAssign"
	make /o /n = (12,8) $ChanAmpAssignPath = nan
End
//=====================================================================================
// MULTICLAMP HARDWARE CONFIGURATION FUNCTION BELOW
//=====================================================================================