#pragma rtGlobals=3

/// @file TJ_MIES_MiesUtilities.ipf
/// This file holds utility functions which need to know about MIES internals.

static StrConstant LABNOTEBOOK_BOTTOM_AXIS_TIME  = "Timestamp (a. u.)"
static StrConstant LABNOTEBOOK_BOTTOM_AXIS_SWEEP = "Sweep Number (a. u.)"

static StrConstant AXIS_BASE_NAME                = "col"

static Constant GRAPH_DIV_SPACING                = 0.03

/// @brief Extracts the date/time column of the settingsHistory wave
///
/// This is useful if you want to plot values against the time and let
/// Igor do the formatting of the date/time values
Function/WAVE GetSettingsHistoryDateTime(settingsHistory)
	WAVE settingsHistory

	DFREF dfr = GetWavesDataFolderDFR(settingsHistory)
	WAVE/Z/SDFR=dfr settingsHistoryDat

	if(!WaveExists(settingsHistoryDat))
		Duplicate/R=[0, DimSize(settingsHistory, ROWS)][1][-1][-1] settingsHistory, dfr:settingsHistoryDat/Wave=settingsHistoryDat
		// we want to have a pure 1D wave without any columns or layers, this is currently not possible with Duplicate
		Redimension/N=-1 settingsHistoryDat
		// redimension has the odd behaviour to change a wave with zero rows to one with 1 row and then initializes that point to zero
		// we need to fix that
		if(DimSize(settingsHistoryDat, ROWS) == 1)
			settingsHistoryDat = NaN
		endif
		SetScale d, 0, 0, "dat" settingsHistoryDat
		SetDimLabel ROWS, -1, TimeStamp, settingsHistoryDat
	endif

	return settingsHistoryDat
End

/// @brief Returns a list of all active DA channels
/// @todo change function to return a numeric wave of variable length
/// and merge with GetADCListFromConfig
Function/S GetDACListFromConfig(ITCChanConfigWave)
	Wave ITCChanConfigWave

	return RefToPullDatafrom2DWave(1, 0, 1, ITCChanConfigWave)
End

/// @brief Returns a list of all active AD channels
Function/S GetADCListFromConfig(ITCChanConfigWave)
	Wave ITCChanConfigWave

	return RefToPullDatafrom2DWave(0, 0, 1, ITCChanConfigWave)
End

/// @brief Returns the data from the data column based on matched values in the ref column
///
/// For ITCDataWave 0 (value) in Ref column = AD channel, 1 = DA channel
static Function/s RefToPullDatafrom2DWave(refValue, refColumn, dataColumn, twoDWave)
	wave twoDWave
	variable refValue, refColumn, dataColumn

	variable i, numRows
	string list = ""

	numRows = DimSize(twoDWave, ROWS)
	for(i = 0; i < numRows; i += 1)
		if(TwoDwave[i][refColumn] == refValue)
			list = AddListItem(num2str(TwoDwave[i][DataColumn]), list, ";", i)
		endif
	endfor

	return list
End

/// @brief Returns the name of a control from the DA_EPHYS panel
///
/// Constants are defined at @ref ChannelTypeAndControlConstants
Function/S GetPanelControl(panelTitle, idx, channelType, controlType)
	string panelTitle
	variable idx, channelType, controlType

	string ctrl

	if(channelType == CHANNEL_TYPE_DAC)
		ctrl = "DA"
	elseif(channelType == CHANNEL_TYPE_ADC)
		ctrl = "AD"
	elseif(channelType == CHANNEL_TYPE_TTL)
		ctrl = "TTL"
	else
		ASSERT(0, "Invalid channelType")
	endif

	if(controlType == CHANNEL_CONTROL_WAVE)
		ctrl = "Wave_" + ctrl
	elseif(controlType == CHANNEL_CONTROL_INDEX_END)
		ctrl = "Popup_" + ctrl + "_IndexEnd"
	elseif(controlType == CHANNEL_CONTROL_UNIT)
		ctrl = "Unit_" + ctrl
	elseif(controlType == CHANNEL_CONTROL_GAIN)
		ctrl = "Gain_" + ctrl
	elseif(controlType == CHANNEL_CONTROL_SCALE)
		ctrl = "Scale_" + ctrl
	elseif(controlType == CHANNEL_CONTROL_CHECK)
		ctrl = "Check_" + ctrl
	else
		ASSERT(0, "Invalid controlType")
	endif

	ASSERT(idx >= 0 && idx < 100, "invalid idx")
	sprintf ctrl, "%s_%02d", ctrl, idx

	return ctrl
End

/// @brief Returns the numerical index for the sweep number column
/// in the settings history wave
Function GetSweepColumn(settingsHistory)
	Wave settingsHistory

	variable sweepCol

	// new label
	sweepCol = FindDimLabel(settingsHistory, COLS, "SweepNum")

	if(sweepCol >= 0)
		return sweepCol
	endif

	// Old label prior to 276b5cf6
	// was normally overwritten by SweepNum later in the code
	// but not always as it turned out
	sweepCol = FindDimLabel(settingsHistory, COLS, "SweepNumber")

	if(sweepCol >= 0)
		return sweepCol
	endif

	// text documentation waves
	sweepCol = FindDimLabel(settingsHistory, COLS, "Sweep #")

	if(sweepCol >= 0)
		return sweepCol
	endif

	DEBUGPRINT("Could not find sweep number dimension label, trying with column zero")

	return 0
End

/// @brief Returns a wave with the latest value of a setting from the history wave
/// for a given sweep number.
///
/// @returns a wave with the value for each headstage in a row. In case
/// the setting could not be found an invalid wave reference is returned.
Function/WAVE GetLastSetting(history, sweepNo, setting)
	Wave history
	variable sweepNo
	string setting

	variable settingCol, numLayers, i, sweepCol, numEntries
	variable first, last

	ASSERT(WaveType(history), "Can only work with numeric waves")
	numLayers = DimSize(history, LAYERS)
	settingCol = FindDimLabel(history, COLS, setting)

	if(settingCol <= 0)
		DEBUGPRINT("Could not find the setting", str=setting)
		return $""
	endif

	sweepCol = GetSweepColumn(history)
	FindRange(history, sweepCol, sweepNo, 0, first, last)

	if(!IsFinite(first) && !IsFinite(last)) // sweep number is unknown
		return $""
	endif

	Make/FREE/N=(numLayers) status

	for(i = last; i >= first; i -= 1)

		status[] = history[i][settingCol][p]
		WaveStats/Q/M=1 status

		// return if at least one entry is not NaN
		if(V_numNaNs != numLayers)
			return status
		endif
	endfor

	return $""
End

/// @brief Returns a wave with latest value of a setting from the history wave
/// for a given sweep number.
///
/// Text wave version of `GetLastSetting`.
///
/// @returns a wave with the value for each headstage in a row. In case
/// the setting could not be found an invalid wave reference is returned.
Function/WAVE GetLastSettingText(history, sweepNo, setting)
	Wave/T history
	variable sweepNo
	string setting

	variable settingCol, numLayers, i, sweepCol
	variable first, last

	ASSERT(!WaveType(history), "Can only work with text waves")
	numLayers = DimSize(history, LAYERS)
	settingCol = FindDimLabel(history, COLS, setting)

	if(settingCol <= 0)
		DEBUGPRINT("Could not find the setting", str=setting)
		return $""
	endif

	sweepCol = GetSweepColumn(history)
	FindRange(history, sweepCol, sweepNo, 0, first, last)

	if(!IsFinite(first) && !IsFinite(last)) // sweep number is unknown
		return $""
	endif

	Make/FREE/N=(numLayers)/T status
	Make/FREE/N=(numLayers) lengths

	for(i = last; i >= first; i -= 1)

		status[] = history[i][settingCol][p]
		lengths[] = strlen(status[p])

		// return if we have at least one non-empty entry
		if(Sum(lengths) > 0)
			return status
		endif
	endfor

	return $""
End

/// @brief Returns a list of all devices, e.g. "ITC18USB_Dev_0;", with an existing datafolder returned by ´GetDevicePathAsString(device)´
Function/S GetAllActiveDevices()

	variable i, j, numTypes, numNumbers
	string type, number, device
	string path, list = ""

	path = GetITCDevicesFolderAsString()

	if(!DataFolderExists(path))
		return ""
	endif

	numTypes   = ItemsInList(DEVICE_TYPES)
	numNumbers = ItemsInList(DEVICE_NUMBERS)
	for(i = 0; i < numTypes; i += 1)
		type = StringFromList(i, DEVICE_TYPES)

		path = GetDeviceTypePathAsString(type)

		if(!DataFolderExists(path))
			continue
		endif

		for(j = 0; j < numNumbers ; j += 1)
			number = StringFromList(j, DEVICE_NUMBERS)
			device = BuildDeviceString(type, number)
			path   = GetDevicePathAsString(device)

			if(!DataFolderExists(path))
				continue
			endif

			list = AddListItem(device, list, ";", inf)
		endfor
	endfor

	return list
End

/// @brief Returns a list of all devices, e.g. "ITC18USB_Dev_0;", which have acquired data.
Function/S GetAllDevicesWithData()

	variable i, numDevices
	string deviceList, device, path
	string list = ""

	deviceList = GetAllActiveDevices()

	numDevices = ItemsInList(deviceList)
	for(i = 0; i < numDevices; i += 1)
		device = StringFromList(i, deviceList)
		path   = GetDeviceDataPathAsString(device)

		if(!DataFolderExists(path))
			continue
		endif

		if(CountObjects(path, COUNTOBJECTS_WAVES) == 0)
			continue
		endif

		list = AddListItem(device, list, ";", inf)
	endfor

	return list
End

/// @brief Delete a datafolder or wave. If this is not possible, because Igor
/// has locked the file, the wave or datafolder is moved into a unique folder
/// named `root:mies:trash_$digit`.
///
/// The trash folders will be removed, if possible, from KillTemporaries().
///
/// @param path absolute path to a datafolder or wave
Function KillOrMoveToTrash(path)
	string path

	string dest

	if(DataFolderExists(path))
		KillDataFolder/Z $path

		if(!V_flag)
			return NaN
		endif

		DFREF miesDFR = GetMiesPath()
		DFREF tmpDFR = UniqueDataFolder(miesDFR, TRASH_FOLDER_PREFIX)
		dest = RemoveEnding(GetDataFolder(1, tmpDFR), ":")
		MoveDataFolder $path, $dest
	elseif(WaveExists($path))
		KillWaves/F/Z $path

		WAVE/Z wv = $path
		if(!WaveExists(wv))
			return NaN
		endif

		DFREF miesDFR = GetMiesPath()
		DFREF tmpDFR = UniqueDataFolder(miesDFR, TRASH_FOLDER_PREFIX)
		MoveWave wv, tmpDFR
	else
		DEBUGPRINT("Ignoring the datafolder/wave as it does not exist", str=path)
	endif
End

/// @brief Returns the config wave for a given sweep wave
Function/Wave GetConfigWave(sweepWave)
	Wave sweepWave

	string name = "Config_" + NameOfWave(sweepWave)
	Wave/SDFR=GetWavesDataFolderDFR(sweepWave) config = $name
	ASSERT(DimSize(config,COLS)==4,"Unexpected number of columns")
	return config
End

/// @brief Returns the, possibly non existing, sweep data wave for the given sweep number
Function/Wave GetSweepWave(panelTitle, sweepNo)
	string panelTitle
	variable sweepNo

	Wave/Z/SDFR=GetDeviceDataPath(panelTitle) wv = $("Sweep_" + num2str(sweepNo))

	return wv
End

/// @brief Returns the sampling interval of the sweep
/// in microseconds (1e-6s)
Function GetSamplingInterval(sweepWave)
	Wave sweepWave

	Wave config = GetConfigWave(sweepWave)

	// from ITCConfigAllChannels help file:
	// Third Column  = SamplingInterval:  integer value for sampling interval in microseconds (minimum value - 5 us)
	Duplicate/D/R=[][2]/FREE config samplingInterval

	// The sampling interval is the same for all channels
	ASSERT(numpnts(samplingInterval),"Expected non-empty wave")
	ASSERT(WaveMax(samplingInterval) == WaveMin(samplingInterval),"Expected constant sample interval for all channels")
	return samplingInterval[0]
End

/// @brief Write the given property to the config wave
///
/// @note Please add new properties as required
/// @param config configuration wave
/// @param samplingInterval sampling interval in microseconds (1e-6s)
Function UpdateSweepConfig(config, [samplingInterval])
	Wave config
	variable samplingInterval

	ASSERT(IsFinite(samplingInterval), "samplingInterval must be finite")
	config[][2] = samplingInterval
End

/// @brief Parse a device string of the form X_DEV_Y, where X is from @ref DEVICE_TYPES
/// and Y from @ref DEVICE_NUMBERS.
///
/// Returns the result in deviceType and deviceNumber.
/// Currently the parsing is successfull if X and Y are non-empty.
/// @param[in]  device       input device string X_DEV_Y
/// @param[out] deviceType   returns the device type X
/// @param[out] deviceNumber returns the device number Y
/// @returns one on successfull parsing, zero on error
Function ParseDeviceString(device, deviceType, deviceNumber)
	string device
	string &deviceType, &deviceNumber

	if(isEmpty(device))
		return 0
	endif

	deviceType   = StringFromList(0,device,"_")
	deviceNumber = StringFromList(2,device,"_")

	return !isEmpty(deviceType) && !isEmpty(deviceNumber)
End

/// @brief Builds the common device string X_DEV_Y, e.g. ITC1600_DEV_O and friends
Function/S BuildDeviceString(deviceType, deviceNumber)
	string deviceType, deviceNumber

	ASSERT(!isEmpty(deviceType) && !isEmpty(deviceNumber), "empty device type or number");
	return deviceType + "_Dev_" + deviceNumber
End

/// @brief Create a vertically tiled graph for displaying AD and DA channels
///
/// Passing in sweepWave assumes the old format of the sweep data (all data in one wave as received by the ITC XOP)
/// Passing in sweepDFR assumes the new format of split waves, one wave for each AD, DA, TTL channel, with one dimension
///
/// @param graph   window
/// @param config  ITC config wave
/// @param sweepNo number of the sweep
/// @param settingsHistory numerical labnotebook wave
/// @param displayDAC display the DA channel, yes or no
/// @param overlaySweep overlay the sweeps, yes or no
/// @param sweepDFR [optional] datafolder with 1D waves extraced from the sweep wave
/// @param sweepWave [optional] sweep wave with multiple columns
Function CreateTiledChannelGraph(graph, config, sweepNo, settingsHistory, displayDAC, overlaySweep, [sweepDFR, sweepWave])
	string graph
	WAVE config
	variable sweepNo
	WAVE settingsHistory
	variable displayDAC, overlaySweep
	DFREF sweepDFR
	WAVE/Z sweepWave

	ASSERT(!isEmpty(graph), "Empty graph")
	ASSERT(IsFinite(sweepNo), "Non-finite sweepNo")
	ASSERT(ParamIsDefault(sweepDFR) + ParamIsDefault(sweepWave), "Caller must supply exactly one of sweepDFR and sweepWave")

	string ADChannelList = GetADCListFromConfig(config)
	string DAChannelList = GetDACListFromConfig(config)
	variable NumberOfDAchannels = ItemsInList(DAChannelList)
	variable NumberOfADchannels = ItemsInList(ADChannelList)
	// the max allows for uneven number of AD and DA channels
	variable numChannels = max(NumberOfDAchannels, NumberOfADchannels)
	variable ADYaxisLow, ADYaxisHigh, ADYaxisSpacing, DAYaxisSpacing, DAYaxisLow, DAYaxisHigh, YaxisHigh, YaxisLow
	variable headstage, red, green, blue, i, axisIndex, splitSweepMode
	string axis, trace, adc, dac
	string configNote = note(config)
	string unit

	if(!ParamIsDefault(sweepDFR))
		splitSweepMode = 1
	endif

	WAVE ranges = GetAxesRanges(graph)

	if(!overlaySweep)
		RemoveTracesFromGraph(graph)
	endif

	if(displayDAC)
		ADYaxisSpacing = 0.8 / numChannels
		DAYaxisSpacing = 0.2 / numChannels
	else
		ADYaxisSpacing = 1 / NumberOfADchannels
	endif

	if(displayDAC)
		DAYaxisHigh = 1
		DAYaxisLow  = DAYaxisHigh - DAYaxisSpacing + GRAPH_DIV_SPACING
		ADYaxisHigh = DAYaxisLow - GRAPH_DIV_SPACING
		ADYaxisLow  = ADYaxisHigh - ADYaxisSpacing + GRAPH_DIV_SPACING
	else
		ADYaxisHigh = 1
		ADYaxisLow  = 1 - ADYaxisSpacing + GRAPH_DIV_SPACING
	endif

	WAVE/Z statusDAC = GetLastSetting(settingsHistory, sweepNo, "DAC")
	WAVE/Z statusADC = GetLastSetting(settingsHistory, sweepNo, "ADC")

	if(!WaveExists(statusDAC) && !WaveExists(statusADC))
		print "The DAC or ADC setting could not be found in the lab notebook."
		print "Is that a BUG or something we should handle gracefully?"
		return NaN
	endif

	for(i = 0; i < numChannels; i += 1)
		if(displayDAC && i < NumberOfDAchannels)
			YaxisHigh = DAYaxisHigh
			YaxisLow = DAYaxisLow
			dac = StringFromList(i, DAChannelList)

			axis = AXIS_BASE_NAME + num2str(axisIndex)
			axisIndex += 1

			trace = "DA" + dac

			if(splitSweepMode)
				WAVE/SDFR=sweepDFR wv = $("DA_" + dac)
				AppendToGraph/W=$graph/L=$axis wv/TN=$trace
			else
				AppendToGraph/W=$graph/L=$axis sweepWave[][i]/TN=$trace
			endif

			ModifyGraph/W=$graph axisEnab($axis) = {YaxisLow, YaxisHigh}
			unit = StringFromList(i, configNote)
			Label/W=$graph $axis, trace + "\r(" + unit + ")"
			ModifyGraph/W=$graph lblPosMode = 1
			ModifyGraph/W=$graph standoff($axis) = 0, freePos($axis) = 0

			headstage = GetRowIndex(statusDAC, str=dac)
			if(!IsFinite(headstage))
				// use a different color to tell the user that we can't query the headstage information
				GetTraceColor(NUM_HEADSTAGES, red, green, blue)
			else
				GetTraceColor(headstage, red, green, blue)
			endif

			ModifyGraph/W=$graph rgb($trace)=(red, green, blue)
		endif

		//AD wave to plot
		YaxisHigh = ADYaxisHigh
		YaxisLow  = ADYaxisLow

		if(i < NumberOfADchannels)
			adc = StringFromList(i, ADChannelList)
			axis = AXIS_BASE_NAME + num2str(axisIndex)
			axisIndex += 1
			trace = "AD" + adc

			if(splitSweepMode)
				WAVE/Z/SDFR=sweepDFR wv = $("AD_" + adc)
				if(WaveExists(wv))
					AppendToGraph/W=$graph/L=$axis wv/TN=$trace
				else
					printf "BUG: ADC %s to plot does not exist\r", adc
					continue
				endif
			else
				AppendToGraph/W=$graph/L=$axis sweepWave[][i + NumberOfDAchannels]/TN=$trace
			endif

			ModifyGraph/W=$graph axisEnab($axis) = {YaxisLow, YaxisHigh}
			unit = StringFromList(i + NumberOfDAchannels, configNote)
			Label/W=$graph $axis, trace + "\r(" + unit + ")"
			ModifyGraph/W=$graph lblPosMode = 1
			ModifyGraph/W=$graph standoff($axis) = 0, freePos($axis) = 0

			headstage = GetRowIndex(statusADC, str=adc)
			if(!IsFinite(headstage))
				// use a different color to tell the user that we can't query the headstage information
				GetTraceColor(NUM_HEADSTAGES, red, green, blue)
			else
				GetTraceColor(headstage, red, green, blue)
			endif

			ModifyGraph/W=$graph rgb($trace)=(red, green, blue)
		endif

		if(i >= NumberOfDAchannels)
			DAYaxisSpacing = 0
		endif

		if(i >= NumberOfADchannels)
			ADYaxisSpacing = 0
		endif

		if(displayDAC)
			DAYAxisHigh -= ADYaxisSpacing + DAYaxisSpacing
			DAYaxisLow  -= ADYaxisSpacing + DAYaxisSpacing
		endif

		ADYAxisHigh -= ADYaxisSpacing + DAYaxisSpacing
		ADYaxisLow  -= ADYaxisSpacing + DAYaxisSpacing
	endfor

	SetAxesRanges(graph, ranges)
End

/// @brief Return a sorted list of all keys in the labnotebook key wave
Function/S GetLabNotebookSortedKeys(keyWave)
	WAVE/Z/T keyWave

	string list = ""
	variable numCols, i

	if(!WaveExists(keyWave))
		return list
	endif

	numCols = DimSize(keyWave, COLS)
	for(i = INITIAL_KEY_WAVE_COL_COUNT; i < numCols; i += 1)
		list = AddListItem(keyWave[%Parameter][i], list, ";", Inf)
	endfor

	return SortList(list)
End

/// @brief Check if the x wave belonging to the first trace in the
/// graph has a date/time scale. Returns true if no traces have been found.
Function CheckIfXAxisIsTime(graph)
	string graph

	string list, trace, dataUnits

	list = TraceNameList(graph, ";", 0 + 1)

	// default is time axis
	if(isEmpty(list))
		return 1
	endif

	trace = StringFromList(0, list)
	dataUnits = WaveUnits(XWaveRefFromTrace(graph, trace), -1)

	return !cmpstr(dataUnits, "dat")
End

/// @brief Queries the parameter and unit from a labnotebook key wave
///
/// @param keyWave   labnotebook key wave
/// @param key       key to look for
/// @param parameter name of the result [empty if not found]
/// @param unit      unit of the result [empty if not found]
/// @param col       column of the result into the keyWave [NaN if not found]
/// @returns one on error, zero otherwise
Function GetKeyWaveParameterAndUnit(keyWave, key, parameter, unit, col)
	WAVE/T/Z keyWave
	string key
	string &parameter, &unit
	variable &col

	variable row, numRows
	string device

	parameter = ""
	unit      = ""
	col       = NaN

	if(!WaveExists(keyWave))
		return 1
	endif

	FindValue/TXOP=4/TEXT=key keyWave

	numRows = DimSize(keywave, ROWS)
	col     = floor(V_value / numRows)
	row     = V_value - col * numRows

	if(V_Value == -1 || row != FindDimLabel(keyWave, ROWS, "Parameter"))
		printf "Could not find %s in keyWave\r", key
		col = NaN
		return 1
	endif

	parameter = keyWave[%Parameter][col]
	unit      = keyWave[%Units][col]

	return 0
End

/// @brief Set the appropriate label for the bottom axis of the graph created by CreateTiledChannelGraph
///
/// Assumes that wave data units are equal for all traces
Function SetLabNotebookBottomLabel(graph, isTimeAxis)
	string graph
	variable isTimeAxis

	if(isTimeAxis)
		Label/W=$graph bottom LABNOTEBOOK_BOTTOM_AXIS_TIME
	else
		Label/W=$graph bottom LABNOTEBOOK_BOTTOM_AXIS_SWEEP
	endif
End

/// @brief Space the matching axis in an equal manner
Function EquallySpaceAxis(graph, axisBaseName)
	string graph, axisBaseName

	variable numAxes, axisInc, axisStart, axisEnd, i
	string axes, axis

	axes    = ListMatch(AxisList(graph), axisBaseName + "*")
	numAxes = ItemsInList(axes)

	if(numAxes == 0)
		return NaN
	endif

	axisInc = 1 / numAxes

	for(i = numAxes - 1; i >= 0; i -= 1)
		axis = StringFromList(i, axes)
		axisStart = GRAPH_DIV_SPACING + axisInc * i
		axisEnd   = (i == numAxes - 1 ? 1 : axisInc * (i + 1) - GRAPH_DIV_SPACING)
		ModifyGraph/W=$graph axisEnab($axis) = {axisStart, axisEnd}
	endfor
End

/// @brief Update the legend in the labnotebook graph
///
/// Passing traceList is required if you just added traces
/// to the graph as these can not be immediately queried using
/// `TraceNameList` as that would require an `DoUpdate` call before.
///
/// @param graph       name of the graph
/// @param traceList   list of traces in the graph
Function UpdateLBGraphLegend(graph, [traceList])
	string graph, traceList

	string str
	variable numEntries, i

	if(!windowExists(graph))
		return NaN
	endif

	ASSERT(FindListItem("text0", AnnotationList(graph)) != -1, "Could not find text0 annotation")

	if(ParamIsDefault(traceList) || ItemsInList(traceList) == 0)
		TextBox/C/W=$graph/N=text0/F=0 ""
		return NaN
	endif

	str = "\\JCHeadstage\r"

	numEntries = ItemsInList(traceList)
	for(i = 0 ; i < numEntries; i += 1)
		str += "\\s(" + PossiblyQuoteName(StringFromList(i, traceList)) + ") " + num2str(i + 1)
		if(mod(i, 2))
			str += "\r"
		endif
	endfor

	str = RemoveEnding(str, "\r")
	TextBox/C/W=$graph/N=text0/F=2 str
End

/// @brief Add a trace to the labnotebook graph
///
/// @param graph name of the graph
/// @param settingsKey labnotebook numerical key wave
/// @param settingsHistory labnotebook numerical wave
/// @param key name of the key to add
Function AddTraceToLBGraph(graph, settingsKey, settingsHistory, key)
	string graph
	WAVE/T settingsKey
	WAVE settingsHistory
	string key

	string unit, lbl, axis, trace, panelTitle, device
	string traceList = ""
	variable sweepNo, i, numEntries, row, col
	variable red, green, blue, isTimeAxis, sweepCol

	if(GetKeyWaveParameterAndUnit(settingsKey, key, lbl, unit, col))
		return NaN
	endif

	lbl = LineBreakingIntoParWithMinWidth(lbl)

	WAVE settingsHistoryDat = GetSettingsHistoryDateTime(settingsHistory)
	isTimeAxis = CheckIfXAxisIsTime(graph)
	sweepCol   = GetSweepColumn(settingsHistory)

	axis = GetNextFreeAxisName(graph, AXIS_BASE_NAME)

	numEntries = DimSize(settingsHistory, LAYERS)
	for(i = 0; i < numEntries; i += 1)

		trace = CleanupName(lbl + " (" + num2str(i + 1) + ")", 1) // +1 because the headstage number is 1-based
		traceList = AddListItem(trace, traceList, ";", inf)

		if(isTimeAxis)
			AppendToGraph/W=$graph/L=$axis settingsHistory[][col][i]/TN=$trace vs settingsHistoryDat
		else
			AppendToGraph/W=$graph/L=$axis settingsHistory[][col][i]/TN=$trace vs settingsHistory[][sweepCol][0]
		endif

		ModifyGraph/W=$graph userData($trace)={key, 0, key}

		GetTraceColor(i, red, green, blue)
		ModifyGraph/W=$graph rgb($trace)=(red, green, blue)
	endfor

	if(!isEmpty(unit))
		lbl += "\r(" + unit + ")"
	endif

	Label/W=$graph $axis lbl

	ModifyGraph/W=$graph lblPosMode = 1, standoff($axis) = 0, freePos($axis) = 0
	ModifyGraph/W=$graph mode = 3
	ModifyGraph/W=$graph nticks(bottom) = 10

	SetLabNotebookBottomLabel(graph, isTimeAxis)
	EquallySpaceAxis(graph, AXIS_BASE_NAME)
	UpdateLBGraphLegend(graph, traceList=traceList)
End

/// @brief Switch the labnotebook graph x axis type (time <-> sweep numbers)
Function SwitchLBGraphXAxis(graph, settingsHistory)
	string graph
	WAVE settingsHistory

	string trace, dataUnits, list
	variable i, numEntries, isTimeAxis, sweepCol

	list = TraceNameList(graph, ";", 0 + 1)

	if(isEmpty(list))
		return NaN
	endif

	isTimeAxis = CheckIfXAxisIsTime(graph)
	sweepCol   = GetSweepColumn(settingsHistory)

	numEntries = ItemsInList(list)
	for(i = 0; i < numEntries; i += 1)
		trace = StringFromList(i, list)

		// change from timestamps to sweepNums
		if(isTimeAxis)
			ReplaceWave/W=$graph/X trace=$trace, settingsHistory[][sweepCol][0]
		else // other direction
			Wave xWave = GetSettingsHistoryDateTime(settingsHistory)
			ReplaceWave/W=$graph/X trace=$trace, xWave
		endif
	endfor

	SetLabNotebookBottomLabel(graph, !isTimeAxis)

	// autoscale all axis after a switch
	list = AxisList(graph)

	numEntries = ItemsInList(list)
	for(i = 0; i < numEntries; i += 1)
		SetAxis/W=$graph/A $StringFromList(i, list)
	endfor
End
