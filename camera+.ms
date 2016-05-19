--Copyright 2011 Eric Mehl (eric@thinkhypothetical.com)
--Version: 1.1
--History:
--2012-07-05 | v1.0 | initial release | Eric Mehl
--2012-08-03 | v1.01 | 	fixed bug when renaming objects would give error message, 
--							fixed bug where changing camera field of view while in offset mode didn't work
--							added exposure feature
--2012-10-30 | v1.1 | added viewport region corrections while in offset mode
--2013-08-05 | v1.2 | updated code to fix bug in 3ds Max with popup sizes
--2013-08-19 | v2.0 | added vray support
--2013-12-13 | v2.1 | tried to fix bug with max UI

--Warning: Use at your own risk!  I try hard to make the scripts as bug free as possible, but I can't be held responsible for
--any problems resulting from their use.  
--Use special caution with mixing alpha/beta/release candidate scripts with production environments.

struct emCamPlus (updateOffsetRegion,updateCamera,camPlusRollout,offsetRollout,isOffsetOpen,exposureRollout,isExposureOpen,iniFileName,dockState,curCam)

debug = true

if debug==true or emCamPlus == undefined then (
	global emCamPlus = emCamPlus()
	emCamPlus.isOffsetOpen = false
	emCamPlus.isExposureOpen = false
)

fn roundTo val n = 
(
	local mult = 10.0 ^ n
	(floor ((val * mult) + 0.5)) / mult
)

fn logBase x b = (
	return (log10 x) / (log10 b)
)
--calculate the EV value for a given fStop and shutter speed - shutter is assumed to be the reciprocal of the actual value
--so a real shutter speed of 1/60 second would be passed as '60'
fn calcEV shutter fstop iso = (
	--gives ev relative to ISO 100
	v1 = (logBase ((fStop * fStop) / (1.0 / shutter)) 2.0)
	v2 = v1 - (logBase ((iso as float) / 100) 2.0)
	v2
)

function linToLog val linMin linMax logMin logMax=
(
	vlog = log val
	if linMin > 0 then (linRange = (log linMax - log linMin))
	else (linRange = log linMax)
	((logMax - logMin) * vlog) / linRange
)

function logToLin val linMin linMax logMin logMax =
(
	if linMin > 0 then (linRange = (log linMax - log linMin))
	else (linRange = log linMax)
	exp ((val * linRange) / (logMax - logMin))
)

function snapVal val places =
(
	mult = pow 10 places
	(((((val as float) * mult) as integer) as float) / mult)
)

--this function is called every time something changes that requires the region to be updated.
--it needs to be accessible from callbacks, so it is part of the emCamPlus struct
function updateRegion =
(
	if superclassof emCamPlus.curCam != camera then (return 0)
	if classof renderers.current != MaxwellRenderer then (return 0)
	
	--vpHeight & vpWidth are the user's original viewport, without any offset applied
	vpHeight = emCamPlus.camPlusRollout.newHeight as float
	vpWidth = emCamPlus.camPlusRollout.newWidth as float
	
	yoff = abs emCamPlus.curCam.sl_yoffset
	xoff = abs emCamPlus.curCam.sl_xoffset
		
	--adjust the temporary (offset) viewport dimensions to account for the camera offset
	renderHeight = (1.0 + ((yoff / 100.0) * 2.0)) * vpHeight
	renderWidth = (1.0 + ((xoff / 100.0) * 2.0)) * vpWidth
	
	yoff_norm = emCamPlus.curCam.sl_yoffset / 100.0
	xoff_norm = emCamPlus.curCam.sl_xoffset / 100.0
	
	--first, adjust the fov for the xoffset
	tempFov = 2.0 * atan ((renderWidth / 2.0) / emCamPlus.camPlusRollout.focalDist)
	
	emCamPlus.curCam.fov = tempFov
	
	--the [w,h]Virtual is the width of an imaginary image plane at planeDist from viewpoint, WITHOUT any offset applied
	--planeDist is arbitrary, it just needs to be consistent throughout
	wVirtual = 2.0 * emCamPlus.camPlusRollout.planeDist * tan (tempFov / 2)
	
	--wTrue is an adjustment of wVirtual to account for the offset
	wTrue = wVirtual * (vpWidth / renderWidth)
	
	--calculate the y offset masking plane	
	emCamPlus.curCam.fovType = 2
	vfov = cameraFOV.FOVtoCurFOV emCamPlus.curCam tempFov
	hVirtual = 2 * emCamPlus.camPlusRollout.planeDist * tan (vfov / 2)
	hTrue = hVirtual * (vpHeight / renderheight)
	
	if debug then (print ("tempFOV=" + (tempFov as string) + " wVirtual=" + (wVirtual as string) + " hVirtual=" + (hVirtual as string) + " vfov=" + (vfov as string) + " oldfov=" + (emCamPlus.camPlusRollout.oldFov as string)))
	
	--set up the y plane mask
	emCamPlus.camPlusRollout.yPlane.length = hVirtual - hTrue
	emCamPlus.camPlusRollout.yPlane.width = 2.0 * emCamPlus.camPlusRollout.planeDist * tan (tempFov / 2)
	ymult = 1.0
	if yoff_norm < 0 then (ymult = -1)
	ypos = (hTrue / 2) * ymult
	xpos = 0.0
	zpos = emCamPlus.camPlusRollout.planeDist
	pt = transMatrix (point3 xpos ypos -zpos)
	pt = pt * emCamPlus.curCam.transform
	emCamPlus.camPlusRollout.yPlane.transform = pt
			
	--set up the x plane mask
	emCamPlus.camPlusRollout.xPlane.length = hVirtual
	emCamPlus.camPlusRollout.xPlane.width = wVirtual - wTrue
	ypos = 0.0
	xmult = -1.0
	if xoff_norm < 0 then (xmult = 1.0)
	xpos = (wTrue / 2.0) * xmult
	pt = transMatrix (point3 xpos ypos -zpos)
	pt = pt * emCamPlus.curCam.transform
	emCamPlus.camPlusRollout.xPlane.transform = pt
	
	--now adjust the viewport region if needed
	renderType = getRenderType()
	if rendertype == #region or renderType == #blowup or renderType == #regionCrop then (
		--the original, unoffset region is stored in the originalRegion variable when the offset goes into effect
		--take that region and scale and move it as needed to fit the new, offset render dimensions
		struct box2f (x, y, w, h)
		nrmRegion = box2f()
		nrmBlowup = box2f()
		nrmRegion.x = (emCamPlus.camPlusRollout.originalRegion.x as float) / vpWidth
		nrmRegion.w = (emCamPlus.camPlusRollout.originalRegion.w as float) / vpWidth
		nrmRegion.y = (emCamPlus.camPlusRollout.originalRegion.y as float) / vpHeight
		nrmRegion.h = (emCamPlus.camPlusRollout.originalRegion.h as float) / vpHeight
		nrmBlowup.x = (emCamPlus.camPlusRollout.originalBlowup.x as float) / vpWidth
		nrmBlowup.w = (emCamPlus.camPlusRollout.originalBlowup.w as float) / vpWidth
		nrmBlowup.y = (emCamPlus.camPlusRollout.originalBlowup.y as float) / vpHeight
		nrmBlowup.h = (emCamPlus.camPlusRollout.originalBlowup.h as float) / vpHeight
		
		--if debug then (print nrmRegion)
		
		wScale = vpWidth / renderWidth
		hScale = vpHeight / renderHeight
		
		xTemp = 1 / wScale
		xRegionOffset = 0.0
		if xMult == -1 then (xRegionOffset = 1.0 - wScale)
		nrmRegion.x =  (xRegionOffset + (nrmRegion.x - (((xTemp - 1) / xTemp) * nrmRegion.x))) * renderWidth
		nrmBlowup.x =  (xRegionOffset + (nrmBlowup.x - (((xTemp - 1) / xTemp) * nrmBlowup.x))) * renderWidth
		yTemp = 1 / hScale
		yRegionOffset = 0.0
		if yMult == 1 then (yRegionOffset = 1.0 - hScale)
		nrmRegion.y = (yRegionOffset + (nrmRegion.y - (((yTemp - 1) / yTemp) * nrmRegion.y))) * renderHeight
		nrmBlowup.y = (yRegionOffset + (nrmBlowup.y - (((yTemp - 1) / yTemp) * nrmBlowup.y))) * renderHeight
		nrmRegion.w = nrmRegion.w * wScale * renderWidth
		nrmBlowup.w = nrmBlowup.w * wScale * renderWidth
		nrmRegion.h = nrmRegion.h * hScale * renderHeight
		nrmBlowup.h = nrmBlowup.h * hScale * renderHeight
		
		--if debug then (print ("yMult: " + (yMult as string)))
		--if debug then (print ("original region: " + (emCamPlus.camPlusRollout.originalRegion as string)))
		--if debug then (print ("vpHeight: " + (vpHeight as string) + "hScale: " + (hScale as string) + "offset region: " + (nrmRegion as string)))
		
		nregion = box2 nrmRegion.x nrmRegion.y nrmRegion.w nrmRegion.h
		nblowup = box2 nrmBlowup.x nrmBlowup.y nrmBlowup.w nrmBlowup.h
		viewport.setRegionRect viewport.activeViewport nRegion
		viewport.setBlowupRect viewport.activeViewport nBlowup
	)
)

emCamPlus.updateOffsetRegion = updateRegion

function updateCam =
(
	if superclassof emCamPlus.curCam != camera then (return 0)
	if classof renderers.current != MaxwellRenderer then (return 0)
	
	--first, adjust the fov for the xoffset
	tempFov = 2.0 * atan ((renderWidth / 2.0) / emCamPlus.camPlusRollout.focalDist)
		
	--find the difference between what the user has currently selected and what it used to be = user's desired change
	--then add that difference to the oldFov to get the new "base" fov, before offset is applied
	if emCamPlus.curCam.fov != tempFov then (
		emCamPlus.camPlusRollout.oldFov = emCamPlus.camPlusRollout.oldFov + emCamPlus.curCam.fov - tempFov
		emCamPlus.camPlusRollout.focalDist = ((emCamPlus.camPlusRollout.newWidth as float) / 2.0) / (tan (emCamPlus.camPlusRollout.oldFov / 2.0))
		if debug then (print ("delta fov=" + (emCamPlus.curCam.fov - tempFov) as string))
	)
	emCamPlus.updateOffsetRegion()
)
emCamPlus.updateCamera = updateCam


--this rollout shouldn't even be able to open if renderer is not Maxwell, so not much needs to be done to add VRay support
rollout emCamOffset "Maxwell Camera Offset" width:304 height:92
(
	label lbl4 "X Offset" pos:[16,12] width:48 height:16
	label lbl5 "Y Offset" pos:[16,44] width:48 height:16
	slider sldXOffset "" pos:[64,4] width:176 height:25 range:[-100,100,0]
	slider sldYOffset "" pos:[64,32] width:176 height:25 range:[-100,100,0]
	spinner spnXOffset "" pos:[240,12] width:56 height:16 range:[-100,100,0] type:#float scale:0.1
	spinner spnYOffset "" pos:[240,44] width:56 height:16 range:[-100,100,0] type:#float scale:0.1
	button btnLevelCamera "Level Camera" pos:[16,64] width:280 height:24 toolTip:"Reset Camera Target Height to Match Camera Height"
		
	function updateUI =
	(
		if superclassof emCamPlus.curCam != camera then (return 0)
		
		--if the camera is just being created, this function may be called before Maxwell applies its camera info
		--so test to make sure the x / y offset variables are there or else reset to zero
		if isProperty emCamPlus.curCam #sl_xoffset then (
			emCamPlus.offsetRollout.spnXOffset.value = emCamPlus.curCam.sl_xoffset
			emCamPlus.offsetRollout.spnYOffset.value = emCamPlus.curCam.sl_yoffset
		)
		else (
			emCamPlus.offsetRollout.spnXOffset.value = 0
			emCamPlus.offsetRollout.spnYOffset.value = 0
		)
		sldXOffset.value = spnXOffset.value
		sldYOffset.value = spnYOffset.value
	)
	
	----------------------------------------------------------------------------------------------------------------------------
	--OFFSET CALLBACKS
	----------------------------------------------------------------------------------------------------------------------------
	on emCamOffset open do
	(
		emCamPlus.isOffsetOpen = true
		dockState = getINISetting emCamPlus.iniFileName "OffsetDialog" "dockState"
		
		--move the dialog to the old position if it's a floater
		xp = getINISetting emCamPlus.iniFileName "OffsetDialog" "xpos"
		yp = getINISetting emCamPlus.iniFileName "OffsetDialog" "ypos"
		print xp
		print yp
		print dockstate
		if xp != "" and yp != "" then (
			p2 = point2 (xp as float) (yp as float)
			setDialogPos emCamOffset p2
		)
		--cui.RegisterDialogBar emCamOffset minSize:[304, 92] maxSize:[304, 92] style:#(#cui_dock_all, #cui_floatable)
		--if dockState!="" and dockState != "floating" then (
			--cui.DockDialogBar emCamOffset (dockState as name)
		--)
		
		updateUI()
	)
	on emCamOffset close do
	(
		emCamPlus.isOffsetOpen = false
		--record dialog state
		if emCamOffset.dialogBar then (
			dockState = (cui.getdockState emCamOffset)
		) 
		else (dockState = "floating")
		setINISetting emCamPlus.iniFileName "OffsetDialog" "dockState" dockState
		pos = getDialogPos emCamOffset
		setINISetting emCamPlus.iniFileName "OffsetDialog" "xpos" (pos.x as string)
		setINISetting emCamPlus.iniFileName "OffsetDialog" "ypos" (pos.y as string)
	)
	
	on sldXOffset changed val do
	(
		print "x changed"
		if superclassof emCamPlus.curCam != camera then (return 0)
		
		val = snapVal val 1
		spnXOffset.value = val
		emCamPlus.curCam.sl_xoffset = val
	)
	on sldYOffset changed val do
	(
		if superclassof emCamPlus.curCam != camera then (return 0)
		
		val = snapVal val 1
		spnYOffset.value = val
		emCamPlus.curCam.sl_yoffset = val
	)
	on spnXOffset changed val do
	(
		if superclassof emCamPlus.curCam != camera then (return 0)
		
		val = snapVal val 1
		sldXOffset.value = val
		emCamPlus.curCam.sl_xoffset = val
	)
	on spnYOffset changed val do
	(
		if superclassof emCamPlus.curCam != camera then (return 0)
		
		val = snapVal val 1
		sldYOffset.value = val
		emCamPlus.curCam.sl_yoffset = val
	)
	
	on btnLevelCamera pressed do
	(
		if superclassof emCamPlus.curCam != camera then (return 0)
		
		emCamPlus.curCam.target.position.z = emCamPlus.curCam.position.z
	)
)
emCamPlus.offsetRollout = emCamOffset
	
rollout emCamExposure "Maxwell Exposure" width:366 height:144
(
	checkbox chkLockShutter pos:[16,16] checked:false
	checkbox chkLockFstop pos:[16,48] checked:false
	checkbox chkLockISO pos:[16,80] checked:false
	label lbl1 "Shutter" pos:[46,16] width:40 height:12
	label lbl2 "f-Stop" pos:[46,48] width:40 height:16
	label lbl3 "ISO" pos:[46,80] width:40 height:16
	slider sldShutter "" pos:[94,16] width:212 height:25 range:[0,100,50]
	slider sldFstop "" pos:[94,44] width:212 height:25 range:[0,100,50]
	slider sldISO "" pos:[94,76] width:212 height:25 range:[0,100,50]
	spinner spnShutter "" pos:[306,16] width:56 height:16 range:[0.02,16000,0] type:#float
	spinner spnFstop "" pos:[306,48] width:56 height:16 range:[1,64,5.6] type:#float
	spinner spnISO "" pos:[306,80] width:56 height:16 range:[1,32000,100] type:#float
	checkbutton btnExposureLock "Lock Exposure" pos:[16,112] width:346 height:20 checked:true
	
	function updateUI =
	(
		if superclassof emCamPlus.curCam != camera then (return 0)
		
		spnShutter.value = emCamPlus.curCam.shutterSpeed
		spnFstop.value = emCamPlus.curCam.fstop
		spnISO.value = emCamPlus.curCam.filmISO
		
		sldShutter.value = linToLog spnShutter.value spnShutter.range[1] spnShutter.range[2] 0.0 100.0
		sldFstop.value = linToLog spnFstop.value spnFstop.range[1] spnFStop.range[2] 0.0 100.0
		sldISO.value = linToLog spnISO.value spnISO.range[1] spnISO.range[2] 0.0 100.0
		
		if btnExposureLock.checked == true then (
			chkLockShutter.enabled = true
			chkLockFstop.enabled = true
			chkLockISO.enabled = true
			
			spnShutter.enabled = not chkLockShutter.checked
			sldShutter.enabled = not chkLockShutter.checked
			spnFstop.enabled = not chkLockFstop.checked
			sldFstop.enabled = not chkLockFstop.checked
			spnISO.enabled = not chkLockISO.checked
			sldISO.enabled = not chkLockISO.checked
		)
		else (
			chkLockShutter.enabled = false
			chkLockFstop.enabled = false
			chkLockISO.enabled = false
			
			spnShutter.enabled = true
			sldShutter.enabled = true
			spnFstop.enabled = true
			sldFstop.enabled = true
			spnISO.enabled = true
			sldISO.enabled = true
		)
	)
	----------------------------------------------------------------------------------------------------------------------------
	--EXPOSURE FUNCTIONS
	----------------------------------------------------------------------------------------------------------------------------
	
	--for a given exposure value (ev) solve for another parameter (solveFor)
	function calcExposure solveFor ev shutter fstop iso =
	(
		iso = iso as float
		fstop = fstop as float
		shutter = shutter as float
		ev = ev as float
		tmpEv = logBase (iso / 100) 2.0
		if solveFor == #shutter then (ret = 1.0 / ((fstop * fstop) / (pow 2.0 (ev + tmpEv))))
		else if solveFor == #fstop then (ret = sqrt((pow 2.0 (ev + tmpEv)) * (1.0 / shutter)))
		else if solveFor == #iso then (
			newEV = logBase ((fstop * fstop) / (1.0 / shutter)) 2.0
			--ret = (roundTo ((pow 2.0 (newEV - ev)) * 100) 0) as integer
			ret = ((pow 2.0 (newEV - ev)) * 100)
		)
		else (return undefined)
		return ret
	)

	--given the shutter, fstop and iso, and one parameter to lock, return which other paramter is closest to its middle range
-- 	function getBestExposureChoice lockParam shutter fstop iso =
-- 	(
-- 		--priority list of changing (most changeable to least) = ISO, shutter, fstop
-- 		
-- 		--get the middle of the logarithmic range, which is probalby more intuitive
-- 		deltaShutter = abs ((linToLog shutter spnShutter.range[1] spnShutter.range[2] 0.0 100.0) - 50)
-- 		deltaFstop = abs ((linToLog fstop spnFstop.range[1] spnFStop.range[2] 0.0 100.0) - 50)
-- 		deltaISO = abs ((linToLog iso spnISO.range[1] spnISO.range[2] 0.0 100.0) - 50)
-- 		
-- 		if lockParam == #shutter then (
-- 			if (iso >= spnISO.range[1]) and (iso <= spnISO.range[2]) then (return #iso)
-- 			return #fstop
-- 		)
-- 		else if lockParam == #fstop then (
-- 			if (iso >= spnISO.range[1]) and (iso <= spnISO.range[2]) then (return #iso)
-- 			return #shutter
-- 		)
-- 		else if lockParam == #iso then (
-- 			if (shutter >= spnShutter.range[1]) and (shutter <= spnShutter.range[2]) then (return #shutter)
-- 			return #fstop
-- 		)
-- 	)
	
	function changeShutter val =
	(
		--change one of the other parameters and make sure that will be within range
		if btnExposureLock.checked then (
			ev = calcEV emCamPlus.curCam.shutterSpeed emCamPlus.curCam.fstop emCamPlus.curCam.filmISO
			--get change parameter based on the potential new value
			newISO = calcExposure #iso ev val emCamPlus.curCam.fstop emCamPlus.curCam.filmISO
			newFstop = calcExposure #fstop ev val emCamPlus.curCam.fstop emCamPlus.curCam.filmISO
			
			--this is the old behavior where it would guess which parameter should be changed, removed 9/26/2012 in favor of user chosen checkboxes
			--changeParam = getBestExposureChoice #shutter val newFstop newISO
			if chkLockFstop.checked then (changeParam = #iso)
			else if chkLockISO.checked then (changeParam = #fstop)
					
			if changeParam == #fstop then (
				if (newFstop < spnFstop.range[1]) or (newFstop > spnFstop.range[2]) then (goAhead = false)
				else (goAhead = true)
			)
			else if changeParam == #iso then (
				goAhead = true
				if (newISO < spnISO.range[1]) or (newISO > spnISO.range[2]) then (
					goAhead = false
				)
				else (
					--round off the iso value and recalculate the shutter value with this new iso
					newISO = roundTo newISO 0
					val = calcExposure #shutter ev val emCamPlus.curCam.fstop newISO
				)
			)
		)
		else (goAhead = true)
		if goAhead then (			
			--update the shutter slider
			tmp = linToLog val spnShutter.range[1] spnShutter.range[2] 0.0 100.0
			sldShutter.value = tmp
			--update the spinner
			spnShutter.value = val
			--update the camera
			emCamPlus.curCam.shutterSpeed = spnShutter.value
			
			--update the other parameter
			if changeParam == #fstop then (
				tmp = linToLog newFstop spnFstop.range[1] spnFstop.range[2] 0.0 100.0
				sldFStop.value = tmp
				spnFStop.value = newFstop
				emCamPlus.curCam.fstop = newFstop
			)
			else if changeParam == #iso then (
				tmp = linToLog newISO spnISO.range[1] spnISO.range[2] 0.0 100.0
				sldISO.value = tmp
				spnISO.value = newISO
				emCamPlus.curCam.filmISO = newISO
			)
		)
		--can't update the value, so reset the spinner + slider to the old value
		else (
			tmp = linToLog emCamPlus.curCam.shutterSpeed spnShutter.range[1] spnShutter.range[2] 0.0 100.0
			spnShutter.value = emCamPlus.curCam.shutterSpeed
			sldShutter.value = tmp
		)
	)
	
	function changeFstop val =
	(
		--change one of the other parameters and make sure that will be within range
		if btnExposureLock.checked then (
			ev = calcEV emCamPlus.curCam.shutterSpeed emCamPlus.curCam.fstop emCamPlus.curCam.filmISO
			--get change parameter based on the potential new value
			newShutter = calcExposure #shutter ev emCamPlus.curCam.shutterSpeed val emCamPlus.curCam.filmISO
			newISO = calcExposure #iso ev emCamPlus.curCam.shutterSpeed val emCamPlus.curCam.filmISO
			
			--this is the old behavior where it would guess which parameter should be changed, removed 9/26/2012 in favor of user chosen checkboxes
			--changeParam = getBestExposureChoice #fstop newShutter val newISO
			if chkLockShutter.checked then (changeParam = #iso)
			else if chkLockISO.checked then (changeParam = #shutter)
			
			if changeParam == #shutter then (
				if (newShutter < spnShutter.range[1]) or (newShutter > spnShutter.range[2]) then (goAhead = false)
				else (goAhead = true)
			)
			else if changeParam == #iso then (
				goAhead = true
				if (newISO < spnISO.range[1]) or (newISO > spnISO.range[2]) then (
					goAhead = false
				)
				else (
					--round off the iso value and recalculate the shutter value with this new iso
					newISO = roundTo newISO 0
					val = calcExposure #fstop ev emCamPlus.curCam.shutterSpeed val newISO
				)
				if (newShutter < spnShutter.range[1]) or (newShutter > spnShutter.range[2]) then (goAhead = false)
			)
		)
		else (goAhead = true)
		if goAhead then (
			--update the shutter slider
			tmp = linToLog val spnFStop.range[1] spnFstop.range[2] 0.0 100.0
			sldFStop.value = tmp
			--update the spinner
			spnFStop.value = val
			--update the camera
			emCamPlus.curCam.fstop = val
			
			--update the other parameter
			if changeParam == #shutter then (
				tmp = linToLog newShutter spnShutter.range[1] spnShutter.range[2] 0.0 100.0
				sldShutter.value = tmp
				spnShutter.value = newShutter
				emCamPlus.curCam.shutterSpeed = newShutter
			)
			else if changeParam == #iso then (
				tmp = linToLog newISO spnISO.range[1] spnISO.range[2] 0.0 100.0
				sldISO.value = tmp
				spnISO.value = newISO
				emCamPlus.curCam.filmISO = newISO
			)
		)
		--can't update the value, so reset the spinner + slider to the old value
		else (
			tmp = linToLog emCamPlus.curCam.fStop spnFStop.range[1] spnFStop.range[2] 0.0 100.0
			spnFStop.value = emCamPlus.curCam.FStop
			sldFStop.value = tmp
		)
	)
	
	function changeISO val =
	(
		val = roundTo val 0	--round the ISO value right at the start
		--change one of the other parameters and make sure that will be within range
		if btnExposureLock.checked then (
			ev = calcEV emCamPlus.curCam.shutterSpeed emCamPlus.curCam.fstop emCamPlus.curCam.filmISO
			--get change parameter based on the potential new value
			newShutter = calcExposure #shutter ev emCamPlus.curCam.shutterSpeed emCamPlus.curCam.fStop val
			newFstop = calcExposure #fstop ev emCamPlus.curCam.shutterSpeed emCamPlus.curCam.fstop val
			
			--this is the old behavior where it would guess which parameter should be changed, removed 9/26/2012 in favor of user chosen checkboxes
			--changeParam = getBestExposureChoice #iso newShutter newFstop val
			if chkLockFstop.checked then (changeParam = #shutter)
			else if chkLockShutter.checked then (changeParam = #fstop)
					
			if changeParam == #fstop then (
				if (newFstop < spnFstop.range[1]) or (newFstop > spnFstop.range[2]) then (goAhead = false)
				else (goAhead = true)
			)
			if changeParam == #shutter then (
				if (newShutter < spnShutter.range[1]) or (newShutter > spnShutter.range[2]) then (goAhead = false)
				else (goAhead = true)
			)
		)
		else (goAhead = true)
		if goAhead then (
			--update the shutter slider
			tmp = linToLog val spnISO.range[1] spnISO.range[2] 0.0 100.0
			sldISO.value = tmp
			--update the spinner
			spnISO.value = val
			--update the camera
			emCamPlus.curCam.filmISO = val
			
			--update the other parameter
			if changeParam == #fstop then (
				tmp = linToLog newFstop spnFstop.range[1] spnFstop.range[2] 0.0 100.0
				sldFStop.value = tmp
				spnFStop.value = newFstop
				emCamPlus.curCam.fstop = newFstop
			)
			if changeParam == #shutter then (
				tmp = linToLog newShutter spnShutter.range[1] spnShutter.range[2] 0.0 100.0
				sldShutter.value = tmp
				spnShutter.value = newShutter
				emCamPlus.curCam.shutterSpeed = newShutter
			)
		)
		--can't update the value, so reset the spinner + slider to the old value
		else (
			tmp = linToLog emCamPlus.curCam.filmISO spnISO.range[1] spnShutter.range[2] 0.0 100.0
			spnISO.value = emCamPlus.curCam.filmISO
			sldISO.value = tmp
		)
	)
	
	----------------------------------------------------------------------------------------------------------------------------
	--EXPOSURE CALLBACKS
	----------------------------------------------------------------------------------------------------------------------------	
	on emCamExposure open do
	(
		emCamPlus.isExposureOpen = true
		dockState = getINISetting emCamPlus.iniFileName "ExposureDialog" "dockState"
		
		--move the dialog to the old position if it's a floater
		xp = getINISetting emCamPlus.iniFileName "ExposureDialog" "xpos"
		yp = getINISetting emCamPlus.iniFileName "ExposureDialog" "ypos"
		lockVal = (getINISetting emCamPlus.iniFileName "ExposureDialog" "lock") as name
		case lockVal of (
			#shutter: chkLockShutter.checked = true
			#fstop: chkLockFstop.checked = true
			#iso: chkLockISO.checked = true
			default: chkLockFstop.checked = true
		)
		if xp != "" and yp != "" then (
			p2 = point2 (xp as float) (yp as float)
			setDialogPos emCamExposure p2
		)
		--cui.RegisterDialogBar emCamExposure minSize:[366, 144] maxSize:[366, 144] style:#(#cui_dock_all, #cui_floatable)
		--if dockState!="" and dockState != "floating" then (
			--cui.DockDialogBar emCamExposure (dockState as name)
		--)
		
		updateUI()
	)
	
	on emCamExposure close do
	(
		emCamPlus.isExposureOpen = false
		--record dialog state
		if emCamExposure.dialogBar then (
			dockState = (cui.getdockState emCamExposure)
		) 
		else (dockState = "floating")
		setINISetting emCamPlus.iniFileName "ExposureDialog" "dockState" dockState
		pos = getDialogPos emCamExposure
		setINISetting emCamPlus.iniFileName "ExposureDialog" "xpos" (pos.x as string)
		setINISetting emCamPlus.iniFileName "ExposureDialog" "ypos" (pos.y as string)
		lockVal = #none
		if chkLockShutter.checked then (lockVal = #shutter)
		if chkLockFstop.checked then (lockVal = #fstop)
		if chkLockISO.checked then (lockVal = #iso)
		setINISetting emCamPlus.iniFileName "ExposureDialog" "lock" (lockVal as string)
	)
	
	on sldShutter changed val do
	(
		val = logToLin val spnShutter.range[1] spnShutter.range[2] 0.0 100.0
		val = snapVal val 1
		changeShutter val
	)
	on sldFstop changed val do
	(
		val =  logToLin val spnFstop.range[1] spnFstop.range[2] 0.0 100.0
		val = snapVal val 1
		changeFstop val
	)
	on sldISO changed val do
	(
		val =  logToLin val spnISO.range[1] spnISO.range[2] 0.0 100.0
		val = snapVal val 1
		changeISO val
	)
	on spnShutter changed val do
	(
		val = snapVal val 1
		changeShutter val
	)
	on spnFstop changed val do
	(
		val = snapVal val 1
		changeFstop val
	)
	on spnISO changed val do
	(
		val = snapVal val 1
		changeISO val
	)
	on chkLockShutter changed state do
	(
		if state == false then (chkLockShutter.checked = true)	--don't allow turning it off, that can only be done by choosing a different button
		else (
			chkLockFStop.checked = false
			chkLockISO.checked = false
		)
		updateUI()
	)
	on chkLockFstop changed state do
	(
		if state == false then (chkLockFstop.checked = true)	--don't allow turning it off, that can only be done by choosing a different button
		else (
			chkLockShutter.checked = false
			chkLockISO.checked = false
		)
		updateUI()
	)
	on chkLockISO changed state do
	(
		if state == false then (chkLockISO.checked = true)	--don't allow turning it off, that can only be done by choosing a different button
		else (
			chkLockFStop.checked = false
			chkLockShutter.checked = false
		)
		updateUI()
	)
	on btnExposureLock changed state do
	(
		updateUI()
	)
)
emCamPlus.exposureRollout = emCamExposure

rollout camRollout "Camera+ v2.0" width:366 height:32
(
	dropdownList ddlCamList "" pos:[8,5] width:230 height:21
	checkbutton btnApplyOffset "S" pos:[246,4] width:22 height:22 toolTip:"Apply Maxwell Camera Offset"
	button btnExposureRollout "E" pos:[306,4] width:22 height:22 toolTip:"Exposure Settings"
	checkbutton btnLockCamera "L" pos:[336,4] width:22 height:22 toolTip:"Lock Camera Position"
	button btnOffsetRollout "O" pos:[276,4] width:22 height:22 toolTip:"Offset Settings"
	
	----------------------------------------------------------------------------------------------------------------------------
	--LOCAL VARIABLES
	----------------------------------------------------------------------------------------------------------------------------
	local yPlane
	local xPlane
	local oldFov
	local newFov
	local oldWidth
	local newWidth
	local oldHeight
	local newHeight
	local planeDist
	local focalDist
	local originalRegion
	local originalBlowup
	
	----------------------------------------------------------------------------------------------------------------------------
	--FUNCTIONS
	----------------------------------------------------------------------------------------------------------------------------
	fn applyOffset =
	(
		if superclassof emCamPlus.curCam != camera then (return 0)
		if classof renderers.current != MaxwellRenderer then (return 0)
		
		--create a layer for the plane objects so it is guaranteed to be visible
		lyr = LayerManager.getLayerFromName "***camOffset***"
		if lyr == undefined then (
			lyr = LayerManager.newLayerFromName "***camOffset***"
		)
		lyr.isHidden = false		
		
		--create the masking planes
		yPlane = plane()
		yPlane.lengthSegs = 1
		yPlane.widthSegs = 1
		yPlane.wirecolor = color 0 0 0
		planeDist = 2.0
		--yPlane.xray = true
		yPlane.isFrozen = true
		
		xPlane = plane()
		xPlane.lengthSegs = 1
		xPlane.widthSegs = 1
		xPlane.wirecolor = color 0 0 0
		--xPlane.xray = true
		xPlane.isFrozen = true
		
		lyr.addNode yPlane
		lyr.addNode xPlane


		--keep track of the current field of view
		oldFov = emCamPlus.curCam.fov
		
		if debug then (print ("oldfov=" + (oldFov as string)))
			
		newFov = oldFov
		focalDist = ((renderwidth as float) / 2.0) / (tan (oldFov / 2.0))
		newWidth = renderWidth
		newHeight = renderHeight
			
		--save the unoffset region / blowup and normalize relative to the viewport dimensions
		originalRegion = viewport.getRegionRect (viewport.activeViewport)
		originalBlowup = viewport.getBlowupRect (viewport.activeViewport)
			
		--setup the callback that triggers when the camera parameters change (which will include sl_yoffset / sl_xoffset)
		when parameters emCamPlus.curCam changes id:#offsetCallback do (emCamPlus.updateCamera())
		
		emCamPlus.updateOffsetRegion()
	)
	
	--reset everything and delete the masking planes
	fn removeOffset = 
	(
		if superclassof emCamPlus.curCam != camera then (return 0)
		if classof renderers.current != MaxwellRenderer then (return 0)
		
		--remove the parameter callback
		deleteAllChangeHandlers id:#offsetCallback
		
		--back transform the render region in case the user made any changes to it while the offset was on
		--now adjust the viewport region if needed
		renderType = getRenderType()
		if rendertype == #region or renderType == #blowup or renderType == #regionCrop then (
			--the original, unoffset region is stored in the originalRegion variable when the offset goes into effect
			--take that region and scale and move it as needed to fit the new, offset render dimensions
			struct box2f (x, y, w, h)
			nrmRegion = box2f()
			nrmBlowup = box2f()
			vpWidth = newWidth as float
			vpHeight = newHeight as float
			originalRegion = viewport.getRegionRect (viewport.activeViewport)
			originalBlowup = viewport.getBlowupRect (viewport.activeViewport)
			
			yoff_norm = emCamPlus.curCam.sl_yoffset / 100.0
			xoff_norm = emCamPlus.curCam.sl_xoffset / 100.0
			ymult = 1.0
			if yoff_norm < 0 then (ymult = -1)
			xmult = -1.0
			if xoff_norm < 0 then (xmult = 1.0)
			
			nrmRegion.x = (originalRegion.x as float) / renderWidth
			nrmRegion.w = (originalRegion.w as float) / renderWidth
			nrmRegion.y = (originalRegion.y as float) / renderHeight
			nrmRegion.h = (originalRegion.h as float) / renderHeight
			nrmBlowup.x = (originalBlowup.x as float) / renderWidth
			nrmBlowup.w = (originalBlowup.w as float) / renderWidth
			nrmBlowup.y = (originalBlowup.y as float) / renderHeight
			nrmBlowup.h = (originalBlowup.h as float) / renderHeight
			if debug then (print vpWidth)
			if debug then (print renderWidth)
			
			wScale = vpWidth / renderWidth
			hScale = vpHeight / renderHeight
			
			xTemp = 1 / wScale
			xRegionOffset = 0.0
			if xMult == -1 then (xRegionOffset = 1.0 - wScale)
			nrmRegion.x =  ((nrmRegion.x - xRegionOffset) / (1-((xTemp-1)/xTemp))) * newWidth
			nrmBlowup.x =  (xRegionOffset + (nrmBlowup.x - (((xTemp - 1) / xTemp) * nrmBlowup.x))) * renderWidth
			yTemp = 1 / hScale
			yRegionOffset = 0.0
			if yMult == 1 then (yRegionOffset = 1.0 - hScale)
			nrmRegion.y =  ((nrmRegion.y - yRegionOffset) / (1-((yTemp-1)/yTemp))) * newHeight
			nrmBlowup.y = (yRegionOffset + (nrmBlowup.y - (((yTemp - 1) / yTemp) * nrmBlowup.y))) * renderHeight
			nrmRegion.w = nrmRegion.w / wScale * newWidth
			nrmBlowup.w = nrmBlowup.w * wScale * renderWidth
			nrmRegion.h = nrmRegion.h / hScale * newHeight
			nrmBlowup.h = nrmBlowup.h * hScale * renderHeight
			
			if debug then (print ("yMult: " + (yMult as string)))
			if debug then (print ("original region: " + (emCamPlus.camPlusRollout.originalRegion as string)))
			if debug then (print ("vpHeight: " + (vpHeight as string) + "hScale: " + (hScale as string) + "offset region: " + (nrmRegion as string)))
		)
		
		--reset the render height / width
		renderHeight = newHeight
		renderWidth = newWidth
		if oldFov != undefined then (emCamPlus.curCam.fov = oldFov)	--this is only set if user has applied offset at least once
		renderSceneDialog.update()
		if isValidNode yPlane then (delete yPlane)
		if isValidNode xPlane then (delete xPlane)
		
		--need to wait until the old viewport setting have been restored before actually setting the new region
		if rendertype == #region or renderType == #blowup or renderType == #regionCrop then (
			nregion = box2 nrmRegion.x nrmRegion.y nrmRegion.w nrmRegion.h
			nblowup = box2 nrmBlowup.x nrmBlowup.y nrmBlowup.w nrmBlowup.h
			viewport.setRegionRect viewport.activeViewport nRegion
			viewport.setBlowupRect viewport.activeViewport nBlowup
		)
		
		LayerManager.deleteLayerByName "***camOffset***"
	)
	
	function updateCameraLayers camName =
	(
		lyrCount = LayerManager.count
		targetLayerName = "cameraSet" + "_" + camName
		for i=0 to lyrCount-1 do (
			lyr = LayerManager.getLayer i
			if lyr.name == targetLayerName and lyr.lock == false then (
				lyr.on = true
			)
			else (
				lyrTokens = filterString lyr.name "_"
				if lyrTokens[1] == "cameraSet" and lyr.lock == false then (
					lyr.on = false
				)
			)
		)
	)
	
	----------------------------------------------------------------------------------------------------------------------------
	--UI / MAX CALLBACK FUNCTIONS
	----------------------------------------------------------------------------------------------------------------------------
	
	function refreshCameraList dbox =
	(
		lst = for obj in objects where (superclassof obj) == camera collect obj.name
		sort lst		
		dbox.ddlCamList.items = lst
		if isValidNode emCamPlus.curCam == false then (
			if lst.count > 0 then (
				emCamPlus.curCam = getNodeByName ddlCamList.items[1]
				ddlCamList.selection = 1
			)
			else (emCamPlus.curCam = undefined)
		)
	)

	function cameraCreated newCam dbox =
	(
		if (superclassof newCam) != camera then (	--only need to worry about cameras
			return 0
		)
			
		emCamPlus.curCam = newCam
		
		--refresh the ui
		refreshCameraList dbox
		
		emCamPlus.camPlusRollout.ddlCamList.selection = (findItem dbox.ddlCamList.items newCam.name)
		
		emCamPlus.camPlusRollout.updateUI()
	)	
	
	function eventRenamed dbox =
	(
		nameSet = callbacks.NotificationParam()
		if ($selection.count ==1) then (
			n = getNodeByName nameSet[2]
			if (superclassof n) ==camera then (
				emCamPlus.camPlusRollout.ddlCamList.selected = nameSet[2]
			)
		)
	)
	
	function eventSelection dbox =
	(
		if debug then (print "event selection")
		
		if $selection.count > 0 then (
			for obj in $selection do (
				if (superclassof obj) == camera then (
					emCamPlus.camPlusRollout.ddlCamList.selection = (findItem dbox.ddlCamList.items obj.name)
					if btnApplyOffset.checked then (removeOffset())
					emCamPlus.curCam = obj
					if btnApplyOffset.checked then (applyOffset())
					emCamPlus.camPlusRollout.updateUI()
				)
			)
		)
	)
	
	function viewportChanged dbox =
	(
		newCam = viewport.getCamera()
		if newCam != undefined and newCam != emCamPlus.curCam then (	--a value of undefined means it's not a camera viewport
			emCamPlus.camPlusRollout.ddlCamList.selection = (findItem emCamPlus.camPlusRollout.ddlCamList.items newCam.name)
			if btnApplyOffset.checked then (removeOffset())
			emCamPlus.curCam = newCam
			if btnApplyOffset.checked then (applyOffset())
			emCamPlus.camPlusRollout.updateUI()
			emCamPlus.camPlusRollout.updateCameraLayers(emCamPlus.curCam.name)
		)
	)
	
	function updateUI =
	(
		if superclassof emCamPlus.curCam != camera then (return 0)
		
		flags = getTransformLockFlags emCamPlus.curCam
		if flags[1] and flags[2] and flags[3] then (
			btnLockCamera.checked = true
		)
		else (btnLockCamera.checked = false)
		
		--update ui for all sub-dialog boxes
		if emCamPlus.isOffsetOpen then (emCamPlus.offsetRollout.updateUI())
		if emCamPlus.isExposureOpen then (emCamPlus.exposureRollout.updateUI())
	)
	
	function eventRendererChanged =
	(
		if classof renderers.current == MaxwellRenderer then (
			btnApplyOffset.enabled = true
			btnExposureRollout.enabled = true
			btnOffsetRollout.enabled = true
		)
		else (
			btnApplyOffset.enabled = false
			btnExposureRollout.enabled = false
			btnOffsetRollout.enabled = false
		)
	)
	
	----------------------------------------------------------------------------------------------------------------------------
	--EVENT HANDLERS
	----------------------------------------------------------------------------------------------------------------------------
	
	on camRollout open do 
	(
		--add icons to the buttons
		btnApplyOffset.images = #("cameras_16i.bmp","cameras_16a.bmp",3, 1, 1, 1, 1, false, true)
		btnExposureRollout.images = #("exposure_16i.bmp","exposure_16a.bmp",1, 1, 1, 1, 1, false, true)
		btnLockCamera.images = #("StatusPanel_16i.bmp","StatusPanel_16a.bmp",35, 1, 3, 2, 4, false, true)
		btnOffsetRollout.images = #("bip_moflow_i.bmp","bip_moflow_i.bmp",10, 9, 9, 9, 9, false, true)
				
		--setup the floating dialog / docking state based on saved ini values
		emCamPlus.iniFileName = ((pathConfig.getDir #plugcfg) + "\camera+.ini")
		dockState = getINISetting emCamPlus.iniFileName "Dialog" "dockState"
		
		--move the dialog to the old position if it's a floater
		xp = getINISetting emCamPlus.iniFileName "Dialog" "xpos"
		yp = getINISetting emCamPlus.iniFileName "Dialog" "ypos"
		if xp != "" and yp != "" then (
			p2 = point2 (xp as float) (yp as float)
			setDialogPos camRollout p2
		)
		
		--Autodesk fucked up the dialog bars in the latest product update (2014 pu2) so this doesn't work for now
		cui.RegisterDialogBar camRollout minSize:[366, 32] maxSize:[366,32] style:#(#cui_dock_all, #cui_floatable)
		if dockState != "" and dockState != "floating" then (
			cui.DockDialogBar camRollout (dockState as name)
		)
		
		--update list of cameras
		refreshCameraList camRollout
		
		if ddlCamList.items.count > 0 then (
			newCam = getNodeByName ddlCamList.selected
			if (superclassof newCam) == camera then (
				emCamPlus.curCam = newCam
				updateUI()
			)
		)
		
		--set width and height variables
		oldWidth = renderWidth
		oldHeight = renderHeight
		newWidth = renderWidth
		newHeight = renderHeight
		
		planeDist = 2.0
		
		--install event callbacks
		callbacks.addScript #sceneNodeAdded "try(camRollout.cameraCreated (callbacks.notificationParam()) (camRollout)) catch(messageBox (getCurrentException()))" id:#camplus
		callbacks.addScript #nodePostDelete "try(camRollout.refreshCameraList camRollout) catch(messageBox (getCurrentException()))" id:#camplus
		callbacks.addScript #systemPostReset "try(camRollout.refreshCameraList camRollout) catch(messageBox (getCurrentException()))" id:#camplus
		callbacks.addScript #filePostOpen "try(camRollout.refreshCameraList camRollout
			camRollout.eventRendererChanged()) catch(messageBox (getCurrentException()))" id:#camplus
		callbacks.addScript #nodeRenamed "try(camRollout.eventRenamed camRollout) catch(messageBox (getCurrentException()))" id:#camplus
		--selectionsetChanged is an optional callback - it causes some UI confusion because viewport offsets may not be in sync
		--with the selected camera
		--callbacks.addScript #selectionSetChanged "try(camRollout.eventSelection camRollout) catch(messageBox (getCurrentException()))" id:#camplus
		callbacks.addScript #viewportChange "try(camRollout.viewportChanged (camRollout.ddlCamList)) catch(messageBox (getCurrentException()))" id:#camplus
		callbacks.addScript #postRendererChange "try(camRollout.eventRendererChanged()) catch(messageBox (getCurrentException()))" id:#camplus
		
		eventRendererChanged()
	)
	
	on camRollout close do
	(
		removeOffset()
		
		--record dialog state
		if camRollout.dialogBar then (dockState = (cui.getdockState camRollout)) 
		else (dockState = "floating")
		setINISetting emCamPlus.iniFileName "Dialog" "dockState" dockState
		pos = getDialogPos emCamPlus.camPlusRollout
		setINISetting emCamPlus.iniFileName "Dialog" "xpos" (pos.x as string)
		setINISetting emCamPlus.iniFileName "Dialog" "ypos" (pos.y as string)
		
		--remove event callbacks
		callbacks.removeScripts id:#camplus
	)
	
	on btnLockCamera changed val do 
	(
		if superclassof emCamPlus.curCam != camera then (return 0)
		
		if val then (
			setTransformLockFlags emCamPlus.curCam #all
		)
		else (
			setTransformLockFlags emCamPlus.curCam #none
		)
	)
	
	on ddlCamList selected val do (
		newCam = getNodeByName ddlCamList.items[val]	
		if (superclassof newCam) == camera then (
			select newCam
			if btnApplyOffset.checked then (removeOffset())
			emCamPlus.curCam = newCam
			if btnApplyOffset.checked then (applyOffset())
			updateUI()
			viewport.setCamera emCamPlus.curCam
			updateCameraLayers(emCamPlus.curCam.name)
		)
	)
	on btnSetView pressed do
	(
		newCam = getNodeByName ddlCamList.selected
		if (superclassof newCam) == camera then (
			viewport.setCamera newCam
		)
	)
	on btnApplyOffset changed val do
	(
		if val then (
			applyOffset()
		)
		else (
			removeOffset()
		)
	)
	on btnOffsetRollout pressed do 
	(
		createDialog emCamPlus.offsetRollout
	)
	
	on btnExposureRollout pressed do 
	(
		createDialog emCamPlus.exposureRollout
	)
)

emCamPlus.camPlusRollout = camRollout
createDialog emCamPlus.camPlusRollout style:#(#style_titlebar, #style_border, #style_sysmenu, #style_resizing)
