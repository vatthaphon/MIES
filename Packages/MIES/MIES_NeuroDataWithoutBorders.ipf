#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.
#pragma rtFunctionErrors=1

#ifdef AUTOMATED_TESTING
#pragma ModuleName=MIES_NWB
#endif

/// @file MIES_NeuroDataWithoutBorders.ipf
/// @brief __NWB__ Functions related to MIES data export into the NeuroDataWithoutBorders format

/// @brief Return the starting time, in fractional seconds since Igor Pro epoch in UTC, of the given sweep
///
/// For existing sweeps with #HIGH_PREC_SWEEP_START_KEY labnotebook entries we use the sweep wave's modification time.
/// The sweep wave can be either an `ITCDataWave` or a `Sweep_$num` wave. Passing the `ITCDataWave` is more accurate.
static Function NWB_GetStartTimeOfSweep(panelTitle, sweepNo, sweepWave)
	string panelTitle
	variable sweepNo
	WAVE sweepWave

	variable startingTime
	string timestamp

	WAVE/T textualValues = GetLBTextualValues(panelTitle)
	timestamp = GetLastSettingTextIndep(textualValues, sweepNo, HIGH_PREC_SWEEP_START_KEY, DATA_ACQUISITION_MODE)

	if(!isEmpty(timestamp))
		return ParseISO8601TimeStamp(timestamp)
	endif

	// fallback mode for old sweeps
	ASSERT(!cmpstr(WaveUnits(sweepWave, ROWS), "ms"), "Expected ms as wave units")
	// last time the wave was modified (UTC)
	startingTime  = NumberByKeY("MODTIME", WaveInfo(sweepWave, 0)) - date2secs(-1, -1, -1)
	// we want the timestamp of the beginning of the measurement
	startingTime -= DimSize(sweepWave, ROWS) * DimDelta(sweepWave, ROWS) / 1000

	return startingTime
End

/// @brief Return the creation time, in seconds since Igor Pro epoch in UTC, of the oldest sweep wave for all devices
///
/// Return NaN if no sweeps could be found
static Function NWB_FirstStartTimeOfAllSweeps()

	string devicesWithData, panelTitle, list, name
	variable numEntries, numWaves, sweepNo, i, j
	variable oldest = Inf

	devicesWithData = GetAllDevicesWithContent()

	if(isEmpty(devicesWithData))
		return NaN
	endif

	numEntries = ItemsInList(devicesWithData)
	for(i = 0; i < numEntries; i += 1)
		panelTitle = StringFromList(i, devicesWithData)

		DFREF dfr = GetDeviceDataPath(panelTitle)
		list = GetListOfObjects(dfr, DATA_SWEEP_REGEXP)
		numWaves = ItemsInList(list)
		for(j = 0; j < numWaves; j += 1)
			name = StringFromList(j, list)
			sweepNo = ExtractSweepNumber(name)
			ASSERT(IsValidSweepNumber(sweepNo), "Could not extract sweep number")
			WAVE/SDFR=dfr sweepWave = $name

			oldest = min(oldest, NWB_GetStartTimeOfSweep(panelTitle, sweepNo, sweepWave))
		endfor
	endfor

	return oldest
End

/// @brief Return the HDF5 file identifier referring to an open NWB file
///        for export
///
/// Open one if it does not exist yet.
///
/// @param[in] overrideFilePath    [optional] file path for new files to override the internal
///                                generation algorithm
/// @param[out] createdNewNWBFile  [optional] a new NWB file was created (1) or an existing opened (0)
static Function NWB_GetFileForExport([overrideFilePath, createdNewNWBFile])
	string overrideFilePath
	variable &createdNewNWBFile

	string expName, fileName, filePath
	variable fileID, refNum, oldestData

	NVAR fileIDExport = $GetNWBFileIDExport()

	if(IPNWB#H5_IsFileOpen(fileIDExport))
		return fileIDExport
	endif

	NVAR sessionStartTimeReadBack = $GetSessionStartTimeReadBack()

	SVAR filePathExport = $GetNWBFilePathExport()
	filePath = filePathExport

	if(!ParamIsDefault(overrideFilePath))
		filePath = overrideFilePath
	elseif(isEmpty(filePath)) // need to derive a new NWB filename
		expName = GetExperimentName()

		if(!cmpstr(expName, UNTITLED_EXPERIMENT))
			fileName = "_" + GetTimeStamp() + ".nwb"
			Open/D/M="Save as NWB file"/F="NWB files (*.nwb):.nwb;" refNum as fileName

			if(isEmpty(S_fileName))
				return NaN
			endif
			filePath = S_fileName
		else
			PathInfo home
			filePath = S_path + CleanupExperimentName(expName) + ".nwb"
		endif
	endif

	GetFileFolderInfo/Q/Z filePath
	if(!V_flag)
		fileID = IPNWB#H5_OpenFile(filePath, write = 1)

		sessionStartTimeReadBack = NWB_ReadSessionStartTime(fileID)

		fileIDExport   = fileID
		filePathExport = filePath

		if(!ParamIsDefault(createdNewNWBFile))
			createdNewNWBFile = 0
		endif
	else // file does not exist
		HDF5CreateFile/Z fileID as filePath
		if(V_flag)
			// invalidate stored path and ID
			filePathExport = ""
			fileIDExport   = NaN
			DEBUGPRINT("Could not create HDF5 file")
			// and retry
			return NWB_GetFileForExport()
		endif

		STRUCT IPNWB#ToplevelInfo ti
		IPNWB#InitToplevelInfo(ti)

		NVAR sessionStartTime = $GetSessionStartTime()

		if(!IsFinite(sessionStartTime))
			sessionStartTime = DateTimeInUTC()
		endif

		oldestData = NWB_FirstStartTimeOfAllSweeps()

		// adjusting the session start time, as older sweeps than the
		// timestamp of the last device locking are to be exported
		// not adjusting it would result in negative starting times for the lastest sweep
		if(IsFinite(oldestData))
			ti.session_start_time = min(sessionStartTime, floor(oldestData))
		endif

		IPNWB#CreateCommonGroups(fileID, toplevelInfo=ti)

		NWB_AddGeneratorString(fileID)

		sessionStartTimeReadBack = NWB_ReadSessionStartTime(fileID)

		fileIDExport   = fileID
		filePathExport = filePath

		if(!ParamIsDefault(createdNewNWBFile))
			createdNewNWBFile = 1
		endif
	endif

	DEBUGPRINT("fileIDExport", var=fileIDExport, format="%15d")
	DEBUGPRINT("filePathExport", str=filePathExport)

	return fileIDExport
End

static Function NWB_AddGeneratorString(fileID)
	variable fileID

	Make/FREE/T/N=(5, 2) props

	props[0][0] = "Program"
#if defined(IGOR64)
	props[0][1] = "Igor Pro 64bit"
#else
	props[0][1] = "Igor Pro 32bit"
#endif

	props[1][0] = "Program Version"
	props[1][1] = StringByKey("IGORFILEVERSION", IgorInfo(3))

	props[2][0] = "Package"
	props[2][1] = "MIES"

	props[3][0] = "Package Version"
	SVAR miesVersion = $GetMiesVersion()
	props[3][1] = miesVersion

	props[4][0] = "Labnotebook Version"
	props[4][1] = num2str(LABNOTEBOOK_VERSION)

	IPNWB#H5_WriteTextDataset(fileID, "/general/generated_by", wvText=props)
	IPNWB#MarkAsCustomEntry(fileID, "/general/generated_by")
End

static Function NWB_ReadSessionStartTime(fileID)
	variable fileID

	string str = IPNWB#ReadTextDataSetAsString(fileID, "/session_start_time")

	ASSERT(cmpstr(str, "PLACEHOLDER"), "Could not read session_start_time back from the NWB file")

	return ParseISO8601TimeStamp(str)
End

static Function/S NWB_GenerateDeviceDescription(panelTitle)
	string panelTitle

	string deviceType, deviceNumber, desc

	ASSERT(ParseDeviceString(panelTitle, deviceType, deviceNumber), "Could not parse panelTitle")

	sprintf desc, "Harvard Bioscience (formerly HEKA/Instrutech) Model: %s", deviceType

	return desc
End

static Function NWB_AddDeviceSpecificData(locationID, panelTitle, [chunkedLayout, writeStoredTestPulses])
	variable locationID
	string panelTitle
	variable chunkedLayout, writeStoredTestPulses

	variable groupID, i, numEntries, refTime
	string path, list, name, contents

	refTime = DEBUG_TIMER_START()

	if(ParamIsDefault(writeStoredTestPulses))
		writeStoredTestPulses = 0
	else
		writeStoredTestPulses = !!writeStoredTestPulses
	endif

	chunkedLayout = ParamIsDefault(chunkedLayout) ? 0 : !!chunkedLayout

	IPNWB#AddDevice(locationID, panelTitle, NWB_GenerateDeviceDescription(panelTitle))

	WAVE numericalValues = GetLBNumericalValues(panelTitle)
	WAVE/T numericalKeys = GetLBNumericalKeys(panelTitle)
	WAVE/T textualValues = GetLBTextualValues(panelTitle)
	WAVE/T textualKeys   = GetLBTextualKeys(panelTitle)

	path = "/general/labnotebook/" + panelTitle
	IPNWB#H5_CreateGroupsRecursively(locationID, path, groupID=groupID)

	IPNWB#MarkAsCustomEntry(locationID, "/general/labnotebook")

	IPNWB#H5_WriteDataset(groupID, "numericalValues", wv=numericalValues, writeIgorAttr=1, overwrite=1, chunkedLayout=chunkedLayout)
	IPNWB#H5_WriteTextDataset(groupID, "numericalKeys", wvText=numericalKeys, writeIgorAttr=1, overwrite=1, chunkedLayout=chunkedLayout)
	IPNWB#H5_WriteTextDataset(groupID, "textualValues", wvText=textualValues, writeIgorAttr=1, overwrite=1, chunkedLayout=chunkedLayout)
	IPNWB#H5_WriteTextDataset(groupID, "textualKeys", wvText=textualKeys, writeIgorAttr=1, overwrite=1, chunkedLayout=chunkedLayout)

	HDF5CloseGroup/Z groupID
	DEBUGPRINT_ELAPSED(refTime)

	path = "/general/user_comment/" + panelTitle
	IPNWB#H5_CreateGroupsRecursively(locationID, path, groupID=groupID)

	IPNWB#MarkAsCustomEntry(locationID, "/general/user_comment")

	SVAR userComment = $GetUserComment(panelTitle)
	IPNWB#H5_WriteTextDataset(groupID, "userComment", str=userComment, overwrite=1, chunkedLayout=chunkedLayout)

	HDF5CloseGroup/Z groupID
	DEBUGPRINT_ELAPSED(refTime)

	path = "/general/testpulse/" + panelTitle
	IPNWB#H5_CreateGroupsRecursively(locationID, path, groupID=groupID)

	IPNWB#MarkAsCustomEntry(locationID, "/general/testpulse")

	DFREF dfr = GetDeviceTestPulse(panelTitle)
	list = GetListOfObjects(dfr, TP_STORAGE_REGEXP)
	numEntries = ItemsInList(list)
	for(i = 0; i < numEntries; i += 1)
		name = StringFromList(i, list)
		WAVE/SDFR=dfr wv = $name
		IPNWB#H5_WriteDataset(groupID, name, wv=wv, writeIgorAttr=1, overwrite=1, chunkedLayout=chunkedLayout)
	endfor

	if(writeStoredTestPulses)
		NWB_AppendStoredTestPulses(panelTitle, groupID)
	endif

	HDF5CloseGroup/Z groupID
	DEBUGPRINT_ELAPSED(refTime)
End

Function NWB_ExportAllData([overrideFilePath, writeStoredTestPulses])
	string overrideFilePath
	variable writeStoredTestPulses

	string devicesWithContent, panelTitle, list, name
	variable i, j, numEntries, locationID, sweep, numWaves, firstCall
	string stimsetList = ""

	devicesWithContent = GetAllDevicesWithContent(contentType = CONTENT_TYPE_ALL)

	if(IsEmpty(devicesWithContent))
		print "No devices with acquired content found for NWB export"
		ControlWindowToFront()
		return NaN
	endif

	if(ParamIsDefault(writeStoredTestPulses))
		writeStoredTestPulses = 0
	else
		writeStoredTestPulses = !!writeStoredTestPulses
	endif

	if(!ParamIsDefault(overrideFilePath))
		locationID = NWB_GetFileForExport(overrideFilePath=overrideFilePath)
	else
		locationID = NWB_GetFileForExport()
	endif

	if(!IsFinite(locationID))
		return NaN
	endif

	IPNWB#AddModificationTimeEntry(locationID)

	print "Please be patient while we export all existing acquired content of all devices to NWB"
	ControlWindowToFront()

	firstCall = 1
	numEntries = ItemsInList(devicesWithContent)
	for(i = 0; i < numEntries; i += 1)
		panelTitle = StringFromList(i, devicesWithContent)
		NWB_AddDeviceSpecificData(locationID, panelTitle, chunkedLayout=1, writeStoredTestPulses = writeStoredTestPulses)

		DFREF dfr = GetDeviceDataPath(panelTitle)
		list = GetListOfObjects(dfr, DATA_SWEEP_REGEXP)
		numWaves = ItemsInList(list)
		for(j = 0; j < numWaves; j += 1)
			if(firstCall)
				IPNWB#CreateIntraCellularEphys(locationID)
				firstCall = 0
			endif

			name = StringFromList(j, list)
			WAVE/SDFR=dfr sweepWave = $name
			WAVE configWave = GetConfigWave(sweepWave)
			sweep = ExtractSweepNumber(name)
			NWB_AppendSweepLowLevel(locationID, panelTitle, sweepWave, configWave, sweep, chunkedLayout=1)
			stimsetList += NWB_GetStimsetFromPanel(panelTitle, sweep)
		endfor
	endfor

	NWB_AppendStimset(locationID, stimsetList)
End

Function NWB_ExportAllStimsets([overrideFilePath])
	string overrideFilePath

	variable locationID
	string stimsets

	stimsets = ReturnListOfAllStimSets(CHANNEL_TYPE_DAC, CHANNEL_DA_SEARCH_STRING) + ReturnListOfAllStimSets(CHANNEL_TYPE_TTL, CHANNEL_TTL_SEARCH_STRING)

	if(IsEmpty(stimsets))
		print "No stimsets found for NWB export"
		ControlWindowToFront()
		return NaN
	endif

	if(!ParamIsDefault(overrideFilePath))
		locationID = NWB_GetFileForExport(overrideFilePath=overrideFilePath)
	else
		locationID = NWB_GetFileForExport()
	endif

	if(!IsFinite(locationID))
		return NaN
	endif

	IPNWB#AddModificationTimeEntry(locationID)

	print "Please be patient while we export all existing stimsets to NWB"
	ControlWindowToFront()

	NWB_AppendStimset(locationID, stimsets)
End

/// @brief Export all data into NWB using compression
///
/// Ask the file location from the user
///
/// @param exportType Export all data and referenced stimsets (#NWB_EXPORT_DATA) or all stimsets (#NWB_EXPORT_STIMSETS)
Function NWB_ExportWithDialog(exportType)
	variable exportType

	string expName, path, filename
	variable refNum, pathNeedsKilling

	expName = GetExperimentName()

	if(!cmpstr(expName, UNTITLED_EXPERIMENT))
		PathInfo Desktop
		if(!V_flag)
			NewPath/Q Desktop, SpecialDirPath("Desktop", 0, 0, 0)
		endif
		path = "Desktop"
		pathNeedsKilling = 1

		filename = "UntitledExperiment-" + GetTimeStamp()
	else
		path     = "home"
		filename = expName
	endif

	filename += "-compressed.nwb"

	Open/D/M="Export into NWB"/F="NWB Files:.nwb;"/P=$path refNum as filename

	if(pathNeedsKilling)
		KillPath/Z $path
	endif

	if(isEmpty(S_filename))
		return NaN
	endif

	// user already acknowledged the overwriting
	CloseNWBFile()
	DeleteFile/Z S_filename

	if(exportType == NWB_EXPORT_DATA)
		NWB_ExportAllData(overrideFilePath=S_filename, writeStoredTestPulses = 1)
	elseif(exportType == NWB_EXPORT_STIMSETS)
		NWB_ExportAllStimsets(overrideFilePath=S_filename)
	else
		ASSERT(0, "unexpected exportType")
	endif

	CloseNWBFile()
End

/// @brief Write the stored test pulses to the NWB file
static Function NWB_AppendStoredTestPulses(panelTitle, locationID)
	string panelTitle
	variable locationID

	variable index, numZeros, i
	string name

	WAVE/WAVE storedTP = GetStoredTestPulseWave(panelTitle)
	index = GetNumberFromWaveNote(storedTP, NOTE_INDEX)

	if(!index)
		// nothing to store
		return NaN
	endif

	for(i = 0; i < index; i += 1)
		sprintf name, "StoredTestPulses_%d", i
		IPNWB#H5_WriteDataset(locationID, name, wv = storedTP[i], chunkedLayout = 1, overwrite = 1, writeIgorAttr = 1)
	endfor
End

/// @brief Export given stimsets to NWB file
///
/// @param locationID	Identifier of open hdf5 group or file
/// @param stimsets		single stimset as string
///                     or list of stimsets sparated by ;
static Function NWB_AppendStimset(locationID, stimsets)
	variable locationID
	string stimsets

	variable i, numStimsets, numWaves

	// process stimsets and dependent stimsets
	stimsets = WB_StimsetRecursionForList(stimsets)
	numStimsets = ItemsInList(stimsets)
	for(i = 0; i < numStimsets; i += 1)
		NWB_WriteStimsetTemplateWaves(locationID, StringFromList(i, stimsets), 1)
	endfor

	// process custom waves
	WAVE/Z/WAVE wv = WB_CustomWavesFromStimSet(stimsetList = stimsets)
	numWaves = DimSize(wv, ROWS)
	for(i = 0; i < numWaves; i += 1)
		NWB_WriteStimsetCustomWave(locationID, wv[i], 1)
	endfor
End

/// @brief Prepare everything for sweep-by-sweep NWB export
Function NWB_PrepareExport([createdNewNWBFile])
	variable &createdNewNWBFile

	variable locationID, createdNewNWBFileLocal

	locationID = NWB_GetFileForExport(createdNewNWBFile = createdNewNWBFileLocal)

	if(!ParamIsDefault(createdNewNWBFile))
		createdNewNWBFile = createdNewNWBFileLocal
	endif

	if(!IsFinite(locationID))
		return NaN
	endif

	if(createdNewNWBFileLocal)
		NWB_ExportAllData()
	endif

	return locationID
End

Function NWB_AppendSweep(panelTitle, ITCDataWave, ITCChanConfigWave, sweep)
	string panelTitle
	WAVE ITCDataWave, ITCChanConfigWave
	variable sweep

	variable locationID, createdNewNWBFile
	string stimsets

	locationID = NWB_PrepareExport(createdNewNWBFile = createdNewNWBFile)

	// in case we created a new NWB file we already exported everyting so we are done
	if(!IsFinite(locationID) || createdNewNWBFile)
		return NaN
	endif

	IPNWB#AddModificationTimeEntry(locationID)
	IPNWB#CreateIntraCellularEphys(locationID)
	NWB_AddDeviceSpecificData(locationID, panelTitle)
	NWB_AppendSweepLowLevel(locationID, panelTitle, ITCDataWave, ITCChanConfigWave, sweep)
	stimsets = NWB_GetStimsetFromPanel(panelTitle, sweep)
	NWB_AppendStimset(locationID, stimsets)
End

/// @brief Get stimsets by analysing currently loaded sweep
///
/// numericalValues and textualValues are generated from panelTitle
///
/// @returns list of stimsets
static Function/S NWB_GetStimsetFromPanel(panelTitle, sweep)
	string panelTitle
	variable sweep

	WAVE numericalValues = GetLBNumericalValues(panelTitle)
	WAVE/T textualValues = GetLBTextualValues(panelTitle)

	return NWB_GetStimsetFromSweepGeneric(sweep, numericalValues, textualValues)
End

/// @brief Get stimsets by analysing dataFolder of loaded sweep
///
/// numericalValues and textualValues are generated from previously loaded data.
/// used in the context of loading from a stored experiment file.
/// on load a sweep is stored in a device/dataFolder hierarchy.
///
/// @returns list of stimsets
Function/S NWB_GetStimsetFromSpecificSweep(dataFolder, device, sweep)
	string dataFolder, device
	variable sweep

	DFREF dfr = GetAnalysisLabNBFolder(dataFolder, device)
	WAVE/SDFR=dfr   numericalValues
	WAVE/SDFR=dfr/T textualValues

	return NWB_GetStimsetFromSweepGeneric(sweep, numericalValues, textualValues)
End

/// @brief Get related Stimsets by corresponding sweep
///
/// input numerical and textual values storage waves for current sweep
///
/// @returns list of stimsets
static Function/S NWB_GetStimsetFromSweepGeneric(sweep, numericalValues, textualValues)
	variable sweep
	WAVE numericalValues
	WAVE/T textualValues

	variable i, j, numEntries
	string ttlList, name
	string stimsetList = ""

	WAVE/Z/T stimsets = GetLastSettingText(textualValues, sweep, STIM_WAVE_NAME_KEY, DATA_ACQUISITION_MODE)
	if(!WaveExists(stimsets))
		return ""
	endif

	// handle AD/DA channels
	for(i = 0; i < NUM_HEADSTAGES; i += 1)
		name = stimsets[i]
		if(isEmpty(name))
			continue
		endif
		stimsetList = AddListItem(name, stimsetList)
	endfor

	// handle TTL channels
	for(i = 0; i < NUM_DA_TTL_CHANNELS; i += 1)
		ttlList = GetTTLstimSets(numericalValues, textualValues, sweep, i)
		numEntries = ItemsInList(ttlList)
		for(j = 0; j < numEntries; j += 1)
			name = StringFromList(j, ttlList)

			// work around empty TTL stim set bug in labnotebook
			if(isEmpty(name))
				continue
			endif

			stimsetList = AddListItem(name, stimsetList)
		endfor
	endfor

	return stimsetList
End

static Function NWB_AppendSweepLowLevel(locationID, panelTitle, ITCDataWave, ITCChanConfigWave, sweep, [chunkedLayout])
	variable locationID
	string panelTitle
	WAVE ITCDataWave, ITCChanConfigWave
	variable sweep, chunkedLayout

	variable groupID, numEntries, i, j, ttlBits, dac, adc, col, refTime
	string group, path, list, name
	string channelSuffix, listOfStimsets, contents

	refTime = DEBUG_TIMER_START()

	chunkedLayout = ParamIsDefault(chunkedLayout) ? 0 : !!chunkedLayout

	NVAR session_start_time = $GetSessionStartTimeReadBack()

	WAVE numericalValues = GetLBNumericalValues(panelTitle)
	WAVE/T numericalKeys = GetLBNumericalKeys(panelTitle)
	WAVE/T textualValues = GetLBTextualValues(panelTitle)
	WAVE/T textualKeys   = GetLBTextualKeys(panelTitle)

	Make/FREE/N=(DimSize(ITCDataWave, COLS)) writtenDataColumns = 0

	// comment denotes the introducing comment of the labnotebook entry
	// 9b35fdad (Add the clamp mode to the labnotebook for acquired data, 2015-04-26)
	WAVE/Z clampMode = GetLastSetting(numericalValues, sweep, "Clamp Mode", DATA_ACQUISITION_MODE)

	if(!WaveExists(clampMode))
		WAVE/Z clampMode = GetLastSetting(numericalValues, sweep, "Operating Mode", DATA_ACQUISITION_MODE)
		ASSERT(WaveExists(clampMode), "Labnotebook is too old for NWB export.")
	endif

	// 3a94d3a4 (Modified files: DR_MIES_TangoInteract:  changes recommended by Thomas ..., 2014-09-11)
	WAVE/Z ADCs = GetLastSetting(numericalValues, sweep, "ADC", DATA_ACQUISITION_MODE)
	ASSERT(WaveExists(ADCs), "Labnotebook is too old for NWB export.")

	// dito
	WAVE DACs = GetLastSetting(numericalValues, sweep, "DAC", DATA_ACQUISITION_MODE)
	ASSERT(WaveExists(DACs), "Labnotebook is too old for NWB export.")

	// 9c8e1a94 (Record the active headstage in the settingsHistory, 2014-11-04)
	WAVE/Z statusHS = GetLastSetting(numericalValues, sweep, "Headstage Active", DATA_ACQUISITION_MODE)
	if(!WaveExists(statusHS))
		Duplicate/FREE ADCs, statusHS

		statusHS = (IsFinite(ADCs[p]) && IsFinite(DACs[p]))
		ASSERT(sum(statusHS) >= 1, "Headstage active workaround failed as there are no active headstages")
	endif

	// 296097c2 (Changes to Tango Interact, 2014-09-03)
	WAVE/T stimSets = GetLastSettingText(textualValues, sweep, STIM_WAVE_NAME_KEY, DATA_ACQUISITION_MODE)
	ASSERT(WaveExists(stimSets), "Labnotebook is too old for NWB export.")

	// 95402da6 (NWB: Allow documenting the physical electrode, 2016-08-05)
	WAVE/Z/T electrodeNames = GetLastSettingText(textualValues, sweep, "Electrode", DATA_ACQUISITION_MODE)
	if(!WaveExists(electrodeNames))
		Make/FREE/T/N=(NUM_HEADSTAGES) electrodeNames = GetDefaultElectrodeName(p)
	else
		WAVE/Z nonEmptyElectrodes = FindIndizes(electrodeNames, col=0, prop=PROP_NON_EMPTY)
		if(!WaveExists(nonEmptyElectrodes)) // all are empty
			electrodeNames[] = GetDefaultElectrodeName(p)
		endif
	endif

	STRUCT IPNWB#WriteChannelParams params
	IPNWB#InitWriteChannelParams(params)

	params.sweep         = sweep
	params.device        = panelTitle
	params.channelSuffix = ""

	// starting time of the dataset, relative to the start of the session
	params.startingTime = NWB_GetStartTimeOfSweep(panelTitle, sweep, ITCDataWave) - session_start_time
	ASSERT(params.startingTime > 0, "TimeSeries starting time can not be negative")

	params.samplingRate = ConvertSamplingIntervalToRate(GetSamplingInterval(ITCChanConfigWave)) * 1000

	DEBUGPRINT_ELAPSED(refTime)

	for(i = 0; i < NUM_HEADSTAGES; i += 1)

		if(!statusHS[i])
			continue
		endif

		STRUCT IPNWB#TimeSeriesProperties tsp

		sprintf contents, "Headstage %d", i
		IPNWB#AddElectrode(locationID, electrodeNames[i], contents, panelTitle)

		adc                    = ADCs[i]
		dac                    = DACs[i]
		params.electrodeName   = electrodeNames[i]
		params.clampMode       = clampMode[i]
		params.stimset         = stimSets[i]

		if(IsFinite(adc))
			path                    = "/acquisition/timeseries"
			params.channelNumber    = ADCs[i]
			params.channelType      = ITC_XOP_CHANNEL_TYPE_ADC
			col                     = AFH_GetITCDataColumn(ITCChanConfigWave, params.channelNumber, params.channelType)
			writtenDataColumns[col] = 1
			WAVE params.data        = ExtractOneDimDataFromSweep(ITCChanConfigWave, ITCDataWave, col)
			NWB_GetTimeSeriesProperties(params, tsp)
			params.groupIndex    = IsFinite(params.groupIndex) ? params.groupIndex : IPNWB#GetNextFreeGroupIndex(locationID, path)
			IPNWB#WriteSingleChannel(locationID, path, params, tsp, chunkedLayout=chunkedLayout)
		endif

		DEBUGPRINT_ELAPSED(refTime)

		if(IsFinite(dac))
			path                    = "/stimulus/presentation"
			params.channelNumber    = DACs[i]
			params.channelType      = ITC_XOP_CHANNEL_TYPE_DAC
			col                     = AFH_GetITCDataColumn(ITCChanConfigWave, params.channelNumber, params.channelType)
			writtenDataColumns[col] = 1
			WAVE params.data        = ExtractOneDimDataFromSweep(ITCChanConfigWave, ITCDataWave, col)
			NWB_GetTimeSeriesProperties(params, tsp)
			params.groupIndex    = IsFinite(params.groupIndex) ? params.groupIndex : IPNWB#GetNextFreeGroupIndex(locationID, path)
			IPNWB#WriteSingleChannel(locationID, path, params, tsp, chunkedLayout=chunkedLayout)
		endif

		ClearWriteChannelParams(params)

		DEBUGPRINT_ELAPSED(refTime)
	endfor

	ClearWriteChannelParams(params)

	DEBUGPRINT_ELAPSED(refTime)

	for(i = 0; i < NUM_DA_TTL_CHANNELS; i += 1)

		ttlBits = GetTTLBits(numericalValues, sweep, i)
		if(!IsFinite(ttlBits))
			continue
		endif

		listOfStimsets = GetTTLstimSets(numericalValues, textualValues, sweep, i)

		params.clampMode        = NaN
		params.channelNumber    = i
		params.channelType      = ITC_XOP_CHANNEL_TYPE_TTL
		params.electrodeNumber  = NaN
		params.electrodeName    = ""
		col                     = AFH_GetITCDataColumn(ITCChanConfigWave, params.channelNumber, params.channelType)
		writtenDataColumns[col] = 1

		WAVE data = ExtractOneDimDataFromSweep(ITCChanConfigWave, ITCDataWave, col)
		DFREF dfr = NewFreeDataFolder()
		SplitTTLWaveIntoComponents(data, ttlBits, dfr, "_")

		list = GetListOfObjects(dfr, ".*")
		numEntries = ItemsInList(list)
		for(j = 0; j < numEntries; j += 1)
			name = StringFromList(j, list)
			WAVE/SDFR=dfr params.data = $name
			path                 = "/stimulus/presentation"
			params.channelSuffix = name[1, inf]
			params.channelSuffixDesc = NWB_SOURCE_TTL_BIT
			params.stimset       = StringFromList(str2num(name[1,inf]), listOfStimsets)
			NWB_GetTimeSeriesProperties(params, tsp)
			params.groupIndex    = IsFinite(params.groupIndex) ? params.groupIndex : IPNWB#GetNextFreeGroupIndex(locationID, path)
			IPNWB#WriteSingleChannel(locationID, path, params, tsp, chunkedLayout=chunkedLayout)
		endfor

		ClearWriteChannelParams(params)
	endfor

	ClearWriteChannelParams(params)

	DEBUGPRINT_ELAPSED(refTime)

	numEntries = DimSize(writtenDataColumns, ROWS)
	for(i = 0; i < numEntries; i += 1)

		if(writtenDataColumns[i])
			continue
		endif

		// unassociated channel data
		// can currently be ADC only or for buggy
		// data, where a headstage is turned off but
		// actually active, also all other channels
		path                   = "/acquisition/timeseries"
		params.clampMode       = NaN
		params.electrodeNumber = NaN
		params.electrodeName   = ""
		params.channelType     = ITCChanConfigWave[i][0]
		params.channelNumber   = ITCChanConfigWave[i][1]
		params.stimSet         = ""
		NWB_GetTimeSeriesProperties(params, tsp)
		WAVE params.data       = ExtractOneDimDataFromSweep(ITCChanConfigWave, ITCDataWave, i)
		params.groupIndex      = IsFinite(params.groupIndex) ? params.groupIndex : IPNWB#GetNextFreeGroupIndex(locationID, path)
		IPNWB#WriteSingleChannel(locationID, path, params, tsp, chunkedLayout=chunkedLayout)
		ClearWriteChannelParams(params)
	endfor

	DEBUGPRINT_ELAPSED(refTime)
End

/// @brief Clear all entries which are channel specific
static Function ClearWriteChannelParams(s)
	STRUCT IPNWB#WriteChannelParams &s

	string device
	variable sweep, startingTime, samplingRate, groupIndex

	// all entries except device and sweep will be cleared
	if(strlen(s.device) > 0)
		device = s.device
	endif

	sweep        = s.sweep
	startingTime = s.startingTime
	samplingRate = s.samplingRate
	groupIndex   = s.groupIndex

	STRUCT IPNWB#WriteChannelParams defaultValues

	s = defaultValues

	if(strlen(device) > 0)
		s.device = device
	endif

	s.sweep        = sweep
	s.startingTime = startingTime
	s.samplingRate = samplingRate
	s.groupIndex   = groupIndex
End

/// @brief Save Custom Wave (from stimset) in NWB file
///
/// @param locationID		open HDF5 group or file identifier
/// @param custom_wave		wave reference to the wave that is to be saved
/// @param chunkedLayout 	use chunked layout with compression and shuffling
static Function NWB_WriteStimsetCustomWave(locationID, custom_wave, chunkedLayout)
	variable locationID, chunkedLayout
	WAVE custom_wave

	variable groupID
	string pathInNWB, custom_wave_name

	// build path for NWB file
	pathInNWB = GetWavesDataFolder(custom_wave, 1)
	pathInNWB = RemoveEnding(pathInNWB, ":")
	pathInNWB = RemovePrefix(pathInNWB, startStr = "root")
	pathInNWB = ReplaceString(":", pathInNWB, "/")
	pathInNWB = "/general/stimsets/referenced" + pathInNWB

	custom_wave_name = NameOfWave(custom_wave)

	IPNWB#H5_CreateGroupsRecursively(locationID, pathInNWB, groupID = groupID)
	IPNWB#H5_WriteDataset(groupID, custom_wave_name, wv=custom_wave, chunkedLayout=chunkedLayout, overwrite=1, writeIgorAttr=1)

	HDF5CloseGroup groupID
End

static Function NWB_WriteStimsetTemplateWaves(locationID, stimSet, chunkedLayout)
	variable locationID
	string stimSet
	variable chunkedLayout

	variable groupID
	string name

	IPNWB#H5_CreateGroupsRecursively(locationID, "/general/stimsets", groupID = groupID)

	// write also the stim set parameter waves if all three exist
	WAVE/Z WP  = WB_GetWaveParamForSet(stimSet)
	WAVE/Z WPT = WB_GetWaveTextParamForSet(stimSet)
	WAVE/Z SegWvType = WB_GetSegWvTypeForSet(stimSet)

	if(!WaveExists(WP) && !WaveExists(WPT) && !WaveExists(SegWvType))
		// third party stim sets need to be written as we don't have parameter waves
		WAVE stimSetWave = WB_CreateAndGetStimSet(stimSet)
		stimset = NameOfWave(stimSetWave)
		IPNWB#H5_WriteDataset(groupID, stimset, wv=stimSetWave, chunkedLayout=chunkedLayout, overwrite=1, writeIgorAttr=1)
		// @todo remove once IP7 64bit is mandatory
		// save memory by deleting the stimset again
		KillOrMoveToTrash(wv=stimSetWave)

		HDF5CloseGroup groupID
		return NaN
	endif

	ASSERT(WaveExists(WP) && WaveExists(WPT) && WaveExists(SegWvType) , "Some stim set parameter waves are missing")

	stimset = RemovePrefix(NameOfWave(WP), startStr = "WP_")
	name = WB_GetParameterWaveName(stimset, STIMSET_PARAM_WP, nwbFormat = 1)
	IPNWB#H5_WriteDataset(groupID, name, wv=WP, chunkedLayout=chunkedLayout, overwrite=1, writeIgorAttr=1)

	name = WB_GetParameterWaveName(stimset, STIMSET_PARAM_WPT, nwbFormat = 1)
	IPNWB#H5_WriteDataset(groupID, name, wv=WPT, chunkedLayout=chunkedLayout, overwrite=1, writeIgorAttr=1)

	name = WB_GetParameterWaveName(stimset, STIMSET_PARAM_SEGWVTYPE, nwbFormat = 1)
	IPNWB#H5_WriteDataset(groupID, name, wv=SegWVType, chunkedLayout=chunkedLayout, overwrite=1, writeIgorAttr=1)

	HDF5CloseGroup groupID
End

/// @brief Load specified stimset from Stimset Group
///
/// @param locationID   id of an open hdf5 group containing the stimsets
/// @param stimset      string of stimset
/// @param verbose      [optional] set to get more output to the command line
/// @param overwrite    indicate whether the stored stimsets should be deleted if they exist
///
/// @return 1 on error
static Function NWB_LoadStimset(locationID, stimset, overwrite, [verbose])
	variable locationID, overwrite, verbose
	string stimset

	variable stimsetType
	string NWBstimsets, WP_name, WPT_name, SegWvType_name

	if(ParamIsDefault(verbose))
		verbose = 0
	endif

	// check if parameter waves exist
	if(!overwrite && WB_ParameterWavesExist(stimset))
		if(verbose > 0)
			printf "stimmset %s exists with parameter waves\r", stimset
			ControlWindowToFront()
		endif
		return 0
	endif

	// check if custom stimset exists
	if(!overwrite && WB_StimsetExists(stimset))
		WB_KillParameterWaves(stimset)
		if(verbose > 0)
			printf "stimmset %s exists as third party stimset\r", stimset
			ControlWindowToFront()
		endif
		return 0
	endif

	WB_KillParameterWaves(stimset)
	WB_KillStimset(stimset)

	// load stimsets with parameter waves
	stimsetType = GetStimSetType(stimset)
	DFREF paramDFR = GetSetParamFolder(stimsetType)

	// convert stimset name to upper case
	NWBstimsets = IPNWB#H5_ListGroupMembers(locationID, "./")
	WP_name = WB_GetParameterWaveName(stimset, STIMSET_PARAM_WP, nwbFormat = 1)
	WP_name = StringFromList(WhichListItem(WP_name, NWBstimsets, ";", 0, 0), NWBstimsets)
	WPT_name = WB_GetParameterWaveName(stimset, STIMSET_PARAM_WPT, nwbFormat = 1)
	WPT_name = StringFromList(WhichListItem(WPT_name, NWBstimsets, ";", 0, 0), NWBstimsets)
	SegWvType_name = WB_GetParameterWaveName(stimset, STIMSET_PARAM_SEGWVTYPE, nwbFormat = 1)
	SegWvType_name = StringFromList(WhichListItem(SegWvType_name, NWBstimsets, ";", 0, 0), NWBstimsets)

	WAVE/Z   WP        = IPNWB#H5_LoadDataset(locationID, WP_name)
	WAVE/Z/T WPT       = IPNWB#H5_LoadDataset(locationID, WPT_name)
	WAVE/Z   SegWVType = IPNWB#H5_LoadDataset(locationID, SegWvType_name)
	if(WaveExists(WP) && WaveExists(WPT) && WaveExists(SegWvType))
		MoveWave WP,        paramDFR:$(WB_GetParameterWaveName(stimset, STIMSET_PARAM_WP))
		MoveWave WPT,       paramDFR:$(WB_GetParameterWaveName(stimset, STIMSET_PARAM_WPT))
		MoveWave SegWVType, paramDFR:$(WB_GetParameterWaveName(stimset, STIMSET_PARAM_SEGWVTYPE))
	endif

	if(WB_ParameterWavesExist(stimset))
		return 0
	endif

	// load custom stimset if previous load failed
	WB_KillParameterWaves(stimset)

	if(IPNWB#H5_DatasetExists(locationID, stimset))
		WAVE/Z wv = IPNWB#H5_LoadDataset(locationID, stimset)
		if(!WaveExists(wv))
			DFREF setDFR = GetSetParamFolder(stimsetType)
			MoveWave wv setDFR
			return 0
		endif
	endif

	printf "Could not load stimset %s from NWB file.\r", stimset
	ControlWindowToFront()

	return 1
End

/// @brief Load a custom wave from NWB file
///
/// loads waves that were saved by NWB_WriteStimsetCustomWave
///
/// @param locationID  open file or group from nwb file
/// @param fullPath    full Path in igor notation to custom wave
/// @param overwrite   indicate whether the stored custom wave should be deleted if it exists
///
/// @return 1 on error and 0 on success
Function NWB_LoadCustomWave(locationID, fullPath, overwrite)
	variable locationID, overwrite
	string fullPath

	string pathInNWB

	WAVE/Z wv = $fullPath
	if(WaveExists(wv))
		if(overwrite)
			KillOrMoveToTrash(wv=wv)
		else
			return 0
		endif
	endif

	pathInNWB = RemovePrefix(fullPath, startStr = "root:")
	pathInNWB = ReplaceString(":", pathInNWB, "/")
	pathInNWB = "/general/stimsets/referenced/" + pathInNWB

	if(!IPNWB#H5_DatasetExists(locationID, pathInNWB))
		printf "custom wave \t%s not found in current NWB file on location \t%s\r", fullPath, pathInNWB
		return 1
	endif

	WAVE wv = IPNWB#H5_LoadDataset(locationID, pathInNWB)
	DFREF dfr = createDFWithAllParents(GetFolder(fullPath))
	MoveWave wv dfr

	return 0
End

/// @brief Load all stimsets from specified HDF5 file.
///
/// @param fileName		[optional] provide full file name/path for loading stimset
/// @param overwrite   [optional] indicate if the stored stimset should be deleted before the load.
/// @return 1 on error and 0 on success
Function NWB_LoadAllStimsets([overwrite, fileName])
	variable overwrite
	string fileName

	variable fileID, groupID, error, numStimsets, i, refNum
	string stimsets, stimset, suffix, fullPath

	if(ParamIsDefault(overwrite))
		overwrite = 0
	else
		overwrite = !!overwrite
	endif
	
	if(ParamIsDefault(fileName))
		Open/D/R/M="Load all stimulus sets"/F="NWB Files:*.nwb;All Files:.*;" refNum

		if(IsEmpty(S_fileName))
			return NaN
		endif

		fullPath = S_fileName
	else
		fullPath = fileName
	endif

	fileID = IPNWB#H5_OpenFile(fullPath)

	if(!IPNWB#StimsetPathExists(fileID))
		printf "no stimsets present in %s\r", fullPath
		IPNWB#H5_CloseFile(fileID)
		return 1
	endif

	stimsets = IPNWB#ReadStimsets(fileID)
	if(ItemsInList(stimsets) == 0)
		IPNWB#H5_CloseFile(fileID)
		return 0
	endif

	// merge stimset Parameter Waves to one unique entry in stimsets list
	sprintf suffix, "_%s;", GetWaveBuilderParameterTypeName(STIMSET_PARAM_WP)
	stimsets = ReplaceString(suffix, stimsets, ";")
	sprintf suffix, "_%s;", GetWaveBuilderParameterTypeName(STIMSET_PARAM_WPT)
	stimsets = ReplaceString(suffix, stimsets, ";")
	sprintf suffix, "_%s;", GetWaveBuilderParameterTypeName(STIMSET_PARAM_SEGWVTYPE)
	stimsets = ReplaceString(suffix, stimsets, ";")
	WAVE/T wv = ListToTextWave(stimsets, ";")
	stimsets = TextWaveToList(GetUniqueTextEntries(wv, caseSensitive = 0), ";")

	groupID = IPNWB#OpenStimset(fileID)
	numStimsets = ItemsInList(stimsets)
	for(i = 0; i < numStimsets; i += 1)
		stimset = StringFromList(i, stimsets)
		if(NWB_LoadStimset(groupID, stimset, overwrite, verbose = 1))
			printf "error loading stimset %s\r", stimset
			error = 1
		endif
	endfor
	NWB_LoadCustomWaves(groupID, stimsets, overwrite)
	HDF5CloseGroup/Z groupID
	IPNWB#H5_CloseFile(fileID)
	return error
End

/// @brief Load specified stimsets and their dependencies from NWB file
///
/// see AB_LoadStimsets() for similar structure
///
/// @param groupID           Open Stimset Group of HDF5 File. See IPNWB#OpenStimset()
/// @param stimsets          ";" separated list of all stimsets of the current sweep.
/// @param processedStimsets [optional] the list indicates which stimsets were already loaded.
///                          on recursion this parameter avoids duplicate circle references.
/// @param overwrite         indicate whether the stored stimsets should be deleted if they exist
///
/// @return 1 on error and 0 on success
Function NWB_LoadStimsets(groupID, stimsets, overwrite, [processedStimsets])
	variable groupID, overwrite
	string stimsets, processedStimsets

	string stimset, totalStimsets, newStimsets, oldStimsets
	variable numBefore, numMoved, numAfter, numNewStimsets, i

	if(ParamIsDefault(processedStimsets))
		processedStimsets = ""
	endif

	totalStimsets = stimsets + processedStimsets
	numBefore = ItemsInList(totalStimsets)

	// load first order stimsets
	numNewStimsets = ItemsInList(stimsets)
	for(i = 0; i < numNewStimsets; i += 1)
		stimset = StringFromList(i, stimsets)
		if(NWB_LoadStimset(groupID, stimset, overwrite))
			if(ItemsInList(processedStimsets) == 0)
				continue
			endif
			return 1
		endif
		numMoved += WB_StimsetFamilyNames(totalStimsets, parent = stimset)
	endfor
	numAfter = ItemsInList(totalStimsets)

	// load next order stimsets
	numNewStimsets = numAfter - numBefore + numMoved
	if(numNewStimsets > 0)
		newStimsets = ListFromList(totalStimsets, 0, numNewStimsets - 1)
		oldStimsets = ListFromList(totalStimsets, numNewStimsets, inf)
		return NWB_LoadStimsets(groupID, newStimsets, overwrite, processedStimsets = oldStimsets)
	endif

	return 0
End

/// @brief Load custom waves for specified stimset from Igor experiment file
///
/// see AB_LoadCustomWaves() for similar structure
///
/// @return 1 on error and 0 on success
Function NWB_LoadCustomWaves(groupID, stimsets, overwrite)
	variable groupID, overwrite
	string stimsets

	string custom_waves
	variable numWaves, i

	stimsets = WB_StimsetRecursionForList(stimsets)
	WAVE/T cw = WB_CustomWavesPathFromStimSet(stimsetList = stimsets)

	numWaves = DimSize(cw, ROWS)
	for(i = 0; i < numWaves; i += 1)
		if(NWB_LoadCustomWave(groupID, cw[i], overwrite))
			return 1
		endif
	endfor

	return 0
End

static Function NWB_GetTimeSeriesProperties(p, tsp)
	STRUCT IPNWB#WriteChannelParams &p
	STRUCT IPNWB#TimeSeriesProperties &tsp

	WAVE numericalValues = GetLBNumericalValues(p.device)

	IPNWB#InitTimeSeriesProperties(tsp, p.channelType, p.clampMode)

	// unassociated channel
	if(!IsFinite(p.clampMode))
		return NaN
	endif

	if(strlen(tsp.missing_fields) > 0)
		ASSERT(IsFinite(p.electrodeNumber), "Expected finite electrode number with non empty \"missing_fields\"")
	endif

	if(p.channelType == ITC_XOP_CHANNEL_TYPE_ADC)
		if(p.clampMode == V_CLAMP_MODE)
			// VoltageClampSeries: datasets
			NWB_AddSweepDataSets(numericalValues, p.sweep, "Fast compensation capacitance", "capacitance_fast", p.electrodeNumber, tsp)
			NWB_AddSweepDataSets(numericalValues, p.sweep, "Slow compensation capacitance", "capacitance_slow", p.electrodeNumber, tsp)
			NWB_AddSweepDataSets(numericalValues, p.sweep, "RsComp Bandwidth", "resistance_comp_bandwidth", p.electrodeNumber, tsp, factor=1e3, enabledProp="RsComp Enable")
			NWB_AddSweepDataSets(numericalValues, p.sweep, "RsComp Correction", "resistance_comp_correction", p.electrodeNumber, tsp, enabledProp="RsComp Enable")
			NWB_AddSweepDataSets(numericalValues, p.sweep, "RsComp Prediction", "resistance_comp_prediction", p.electrodeNumber, tsp, enabledProp="RsComp Enable")
			NWB_AddSweepDataSets(numericalValues, p.sweep, "Whole Cell Comp Cap", "whole_cell_capacitance_comp", p.electrodeNumber, tsp, factor=1e-12, enabledProp="Whole Cell Comp Enable")
			NWB_AddSweepDataSets(numericalValues, p.sweep, "Whole Cell Comp Resist", "whole_cell_series_resistance_comp", p.electrodeNumber, tsp, factor=1e6, enabledProp="Whole Cell Comp Enable")
		elseif(p.clampMode == I_CLAMP_MODE)
			// CurrentClampSeries: datasets
			NWB_AddSweepDataSets(numericalValues, p.sweep, "I-Clamp Holding Level", "bias_current", p.electrodeNumber, tsp, enabledProp="I-Clamp Holding Enable")
			NWB_AddSweepDataSets(numericalValues, p.sweep, "Bridge Bal Value", "bridge_balance", p.electrodeNumber, tsp, enabledProp="Bridge Bal Enable")
			NWB_AddSweepDataSets(numericalValues, p.sweep, "Neut Cap Value", "capacitance_compensation", p.electrodeNumber, tsp, enabledProp="Neut Cap Enabled")
		endif

		NWB_AddSweepDataSets(numericalValues, p.sweep, "AD Gain", "gain", p.electrodeNumber, tsp)
	elseif(p.channelType == ITC_XOP_CHANNEL_TYPE_DAC)
		NWB_AddSweepDataSets(numericalValues, p.sweep, "DA Gain", "gain", p.electrodeNumber, tsp)

		WAVE/Z values = GetLastSetting(numericalValues, p.sweep, "Stim Scale Factor", DATA_ACQUISITION_MODE)
		if(WaveExists(values) || IsFinite(values[p.electrodeNumber]))
			IPNWB#AddCustomProperty(tsp, "scale", values[p.electrodeNumber])
		endif
	endif
End

static Function NWB_AddSweepDataSets(numericalValues, sweep, settingsProp, nwbProp, headstage, tsp, [factor, enabledProp])
	WAVE numericalValues
	variable sweep
	string settingsProp, nwbProp
	variable headstage
	STRUCT IPNWB#TimeSeriesProperties &tsp
	variable factor
	string enabledProp

	if(ParamIsDefault(factor))
		factor = 1
	endif

	if(!ParamIsDefault(enabledProp))
		WAVE/Z enabled = GetLastSetting(numericalValues, sweep, enabledProp, DATA_ACQUISITION_MODE)
		if(!WaveExists(enabled) || !enabled[headstage])
			return NaN
		endif
	endif

	WAVE/Z values = GetLastSetting(numericalValues, sweep, settingsProp, DATA_ACQUISITION_MODE)
	if(!WaveExists(values) || !IsFinite(values[headstage]))
		return NaN
	endif

	IPNWB#AddProperty(tsp, nwbProp, values[headstage] * factor)
End

/// @brief function saves contents of specified notebook to data folder
///
/// @param locationID id of nwb file or notebooks folder
/// @param notebook name of notebook to be loaded
/// @param dfr igor data folder where data should be loaded into
Function NWB_LoadLabNoteBook(locationID, notebook, dfr)
	Variable locationID
	String notebook
	DFREF dfr

	String deviceList, path

	if(!DataFolderExistsDFR(dfr))
		return 0
	endif

	path = "/general/labnotebook/" + notebook
	if(IPNWB#H5_GroupExists(locationID, path))
		HDF5LoadGroup/Z/IGOR=-1 dfr, locationID, path
		if(!V_flag)
			return ItemsInList(S_objectPaths)
		endif
	endif

	return 0
End

/// @brief Flushes the contents of the NWB file to disc
Function NWB_Flush()
	SVAR filePathExport = $GetNWBFilePathExport()
	NVAR fileIDExport   = $GetNWBFileIDExport()

	if(!IsFinite(fileIDExport))
		return NaN
	endif

	fileIDExport = IPNWB#H5_FlushFile(fileIDExport, filePathExport, write = 1)
End
