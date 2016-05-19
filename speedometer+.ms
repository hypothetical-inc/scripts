--Copyright 2012 Eric Mehl (eric@thinkhypothetical.com)
--Version: 1.0 
--History:
--2012-08-06 | v1 | initial release | Eric Mehl

--Warning: Use at your own risk!  I try hard to make the scripts as bug free as possible, but I can't be held responsible for
--any problems resulting from their use.  
--Use special caution with mixing alpha/beta/release candidate scripts with production environments.

macroScript speedometerPlus category:"EM Tools" tooltip:"Speedometer+" icon:#("MainToolbar",83) (
struct emSpeedPlusStruct (speedometerRollout,eventSelection,eventMove,unitType,obj,measureSpeed)

debug = false

global emSpeedPlus
	
if debug==true or emSpeedPlus == undefined then (
	emSpeedPlus = emSpeedPlusStruct()
)

function measureSpeed =
(
	if emSpeedPlus.obj == undefined then (return 0)
	
	unitString = case emSpeedPlus.unitType of (
		#mph:"mph"
		#kmh:"kmh"
		#fts:"ft/s"
		#ms:"m/s"
		#knots:"knots"
	)
	
	--1) speed is initially in units / tick
	--2) convert that to inches / sec
	--3) then convert that to the desired display units
	speedRatio = case emSpeedPlus.unitType of (
		#mph:0.056818
		#kmh:0.09144
		#fts:0.08333
		#ms:0.0254
		#knots:0.04937
	)
	inchesPer = case units.systemType of (
		#inches:1.0
		#feet:12.0
		#miles:12.0 * 5280
		#millimeters:1.0 / 25.4
		#centimeters:1.0/2.54
		#meters:1.0 / .0254
		#kilometers:1.0 / .0000254
	)
	
	--calculate the speed
	--based on code from scriptspot, author = ?
	prePos = at time (currentTime - 1t) emSpeedPlus.obj.pos
	nextPos = at time (currentTime +1t) emSpeedPlus.obj.pos
	d = distance prePos nextPos
	if debug then (print ("d=" + (d as string) + " --- inchesPer=" + (inchesPer as string) + " --- speedRatio=" + (speedRatio as string)))
	v = d * inchesPer * 2400.0 --2400 inches / sec = 4800 ticks / 1 sec * (1 inch / x userUnits) / 2 (to average between 2 time measurements)
	v = v * speedRatio
	
	--round it off
	n = 1
	local mult = 10.0 ^ n
	v = (floor ((v * mult) + 0.5)) / mult		
		
	txt = emSpeedPlus.obj.name + ": " + (v as string) + " " + unitString
	emSpeedPlus.speedometerRollout.lblSpeed.text = txt
)
emSpeedPlus.measureSpeed = measureSpeed

function eventSelection =
(
	deleteAllChangeHandlers id:#speedometerCallback
	if emSpeedPlus.speedometerRollout.ckbRetain.checked == false then (
		if $selection.count == 0 then (emSpeedPlus.speedometerRollout.lblSpeed.text = "No Object Selected")
		if $selection.count > 1 then (emSpeedPlus.speedometerRollout.lblSpeed.text = "I Can Only Measure Speed for One Object at a Time")
		if $selection.count == 1 then (
			emSpeedPlus.obj = $selection[1]
			when parameters emSpeedPlus.obj changes id:#speedometerCallback do (emSpeedPlus.measureSpeed())
			emSpeedPlus.measureSpeed()
		)
	)
)

emSpeedPlus.eventSelection = eventSelection

function eventMove =
(
	messageBox "move"
)
emSpeedPlus.eventMove = eventMove

rollout speedometer "Speedometer+" width:248 height:136
(
	checkButton ckbMph "mph" pos:[16,16] width:32 height:24 checked:true
	checkButton ckbKmh "kmh" pos:[56,16] width:32 height:24
	checkButton ckbFts "ft/s" pos:[104,16] width:32 height:24
	checkButton ckbMs "m/s" pos:[152,16] width:32 height:24
	checkButton ckbknots "knots" pos:[200,16] width:32 height:24
	checkbutton ckbRetain "Hold Selection" pos:[16,96] width:216 height:24
	label lblSpeed "Speed: " pos:[16,56] width:168 height:16
	
	function updateButtons =
	(
		ckbMph.checked = false
		ckbKmh.checked = false
		ckbFts.checked = false
		ckbMs.checked = false
		ckbKnots.checked = false
		case emSpeedPlus.unitType of (
			#mph:ckbMph.checked = true
			#kmh:ckbKmh.checked = true
			#fts:ckbFts.checked = true
			#ms:ckbMs.checked = true
			#knots:ckbKnots.checked = true
		)
	)
	
	on speedometer open do 
	(
		emSpeedPlus.unitType = #mph
		
		if $selection.count == 0 then (emSpeedPlus.speedometerRollout.lblSpeed.text = "No Object Selected")
		if $selection.count > 1 then (emSpeedPlus.speedometerRollout.lblSpeed.text = "I Can Only Measure Speed for One Object at a Time")
		if $selection.count == 1 then (
			emSpeedPlus.obj = $selection[1]
			measureSpeed()
		)
		
		callbacks.addScript #selectionSetChanged "try(emSpeedPlus.eventSelection()) catch(messageBox (getCurrentException()))" id:#speedometerPlus
		registerTimeCallback emSpeedPlus.measureSpeed
	)
	
	on speedometer close do
	(
		--remove event callbacks
		callbacks.removeScripts id:#speedometerPlus
		unregisterTimeCallback emSpeedPlus.measureSpeed
	)
	
	on ckbMph changed state do
	(
		emSpeedPlus.unitType = #mph
		updateButtons()
		measureSpeed()
	)
	on ckbKmh changed state do
	(
		emSpeedPlus.unitType = #kmh
		updateButtons()
		measureSpeed()
	)
	on ckbFts changed state do 
	(
		emSpeedPlus.unitType = #fts
		updateButtons()
		measureSpeed()
	)
	on ckbMs changed state do
	(
		emSpeedPlus.unitType = #ms
		updateButtons()
		measureSpeed()
	)
	on ckbKnots changed state do
	(
		emSpeedPlus.unitType = #knots
		updateButtons()
		measureSpeed()
	)
)
emSpeedPlus.speedometerRollout = speedometer

createDialog speedometer
)