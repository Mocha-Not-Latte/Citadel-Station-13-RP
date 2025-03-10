
var/list/global/tank_gauge_cache = list()

/**
 * # Gas Tank
 *
 * Handheld gas canisters
 * Can rupture explosively if overpressurized
 */
/obj/item/tank
	name = "tank"
	icon = 'icons/obj/tank.dmi'
	drop_sound = 'sound/items/drop/gascan.ogg'
	pickup_sound = 'sound/items/pickup/gascan.ogg'

	var/gauge_icon = "indicator_tank"
	var/last_gauge_pressure
	var/gauge_cap = 6

	slot_flags = SLOT_BACK
	w_class = ITEMSIZE_NORMAL

	damage_force = 5.0
	throw_force = 10.0
	throw_speed = 1
	throw_range = 4

	weight = ITEM_WEIGHT_GAS_TANK

	var/datum/gas_mixture/air_contents = null
	var/distribute_pressure = ONE_ATMOSPHERE
	integrity = 20
	integrity_max = 20
	var/valve_welded = 0
	var/obj/item/tankassemblyproxy/proxyassembly

	var/volume = 70
	var/manipulated_by = null		//Used by _onclick/hud/screen_objects.dm internals to determine if someone has messed with our tank or not.
						//If they have and we haven't scanned it with the PDA or gas analyzer then we might just breath whatever they put in it.

	var/failure_temp = 173 //173 deg C Borate seal (yes it should be 153 F, but that's annoying)
	var/leaking = 0
	var/wired = 0

	description_info = "These tanks are utilised to store any of the various types of gaseous substances. \
	They can be attached to various portable atmospheric devices to be filled or emptied. <br>\
	<br>\
	Each tank is fitted with an emergency relief valve. This relief valve will open if the tank is pressurised to over ~3000kPa or heated to over 173�C. \
	The valve itself will close after expending most or all of the contents into the air.<br>\
	<br>\
	Filling a tank such that experiences ~4000kPa of pressure will cause the tank to rupture, spilling out its contents and destroying the tank. \
	Tanks filled over ~5000kPa will rupture rather violently, exploding with significant force."

	description_antag = "Each tank may be incited to burn by attaching wires and an igniter assembly, though the igniter can only be used once and the mixture only burn if the igniter pushes a flammable gas mixture above the minimum burn temperature (126�C). \
	Wired and assembled tanks may be disarmed with a set of wirecutters. Any exploding or rupturing tank will generate shrapnel, assuming their relief valves have been welded beforehand. Even if not, they can be incited to expel hot gas on ignition if pushed above 173�C. \
	Relatively easy to make, the single tank bomb requries no tank transfer valve, and is still a fairly formidable weapon that can be manufactured from any tank."

/obj/item/tank/proc/init_proxy()
	var/obj/item/tankassemblyproxy/proxy = new /obj/item/tankassemblyproxy(src)
	proxy.tank = src
	src.proxyassembly = proxy


/obj/item/tank/Initialize(mapload)
	. = ..()
	START_PROCESSING(SSobj, src)

	src.init_proxy()
	src.air_contents = new /datum/gas_mixture()
	src.air_contents.volume = volume //liters
	src.air_contents.temperature = T20C
	update_gauge()

/obj/item/tank/Destroy()
	QDEL_NULL(air_contents)

	STOP_PROCESSING(SSobj, src)
	QDEL_NULL(src.proxyassembly)

	if(istype(loc, /obj/item/transfer_valve))
		var/obj/item/transfer_valve/TTV = loc
		TTV.remove_tank(src)
		qdel(TTV)

	. = ..()

/obj/item/tank/examine(mob/user, dist)
	. = ..()
	if(.)
		var/celsius_temperature = air_contents.temperature - T0C
		var/descriptive
		switch(celsius_temperature)
			if(300 to INFINITY)
				descriptive = "furiously hot"
			if(100 to 300)
				descriptive = "hot"
			if(80 to 100)
				descriptive = "warm"
			if(40 to 80)
				descriptive = "lukewarm"
			if(20 to 40)
				descriptive = "room temperature"
			if(-20 to 20)
				descriptive = "cold"
			else
				descriptive = "bitterly cold"
		. += "<span class='notice'>\The [src] feels [descriptive].</span>"

	if(src.proxyassembly.assembly || wired)
		. += "<span class='warning'>It seems to have [wired? "some wires ": ""][wired && src.proxyassembly.assembly? "and ":""][src.proxyassembly.assembly ? "some sort of assembly ":""]attached to it.</span>"
	if(src.valve_welded)
		. += "<span class='warning'>\The [src] emergency relief valve has been welded shut!</span>"


/obj/item/tank/attackby(obj/item/W, mob/user)
	..()
	if (istype(loc, /obj/item/assembly))
		icon = loc

	if ((istype(W, /obj/item/atmos_analyzer)) && get_dist(user, src) <= 1)
		var/obj/item/atmos_analyzer/A = W
		A.analyze_gases(src, user)
	else if (istype(W,/obj/item/latexballon))
		var/obj/item/latexballon/LB = W
		LB.blow(src)
		add_fingerprint(user)

	if(istype(W, /obj/item/stack/cable_coil))
		var/obj/item/stack/cable_coil/C = W
		if(C.use(1))
			wired = 1
			to_chat(user, "<span class='notice'>You attach the wires to the tank.</span>")
			add_bomb_overlay()

	if(W.is_wirecutter())
		if(wired && proxyassembly.assembly)

			to_chat(user, "<span class='notice'>You carefully begin clipping the wires that attach to the tank.</span>")
			if(do_after(user, 100, src))
				wired = 0
				cut_overlay("bomb_assembly")
				to_chat(user, "<span class='notice'>You cut the wire and remove the device.</span>")

				var/obj/item/assembly_holder/assy = proxyassembly.assembly
				if(assy.a_left && assy.a_right)
					assy.dropInto(usr.loc)
					assy.master = null
					proxyassembly.assembly = null
				else
					if(!proxyassembly.assembly.a_left)
						assy.a_right.dropInto(usr.loc)
						assy.a_right.holder = null
						assy.a_right = null
						proxyassembly.assembly = null
						qdel(assy)
				cut_overlays()
				last_gauge_pressure = 0
				update_gauge()

			else
				to_chat(user, "<span class='danger'>You slip and bump the igniter!</span>")
				if(prob(85))
					proxyassembly.receive_signal()

		else if(wired)
			if(do_after(user, 10, src))
				to_chat(user, "<span class='notice'>You quickly clip the wire from the tank.</span>")
				wired = 0
				cut_overlay("bomb_assembly")

		else
			to_chat(user, "<span class='notice'>There are no wires to cut!</span>")



	if(istype(W, /obj/item/assembly_holder))
		if(wired)
			to_chat(user, "<span class='notice'>You begin attaching the assembly to \the [src].</span>")
			if(do_after(user, 50, src))
				to_chat(user, "<span class='notice'>You finish attaching the assembly to \the [src].</span>")
				bombers += "[key_name(user)] attached an assembly to a wired [src]. Temp: [air_contents.temperature-T0C]"
				message_admins("[key_name_admin(user)] attached an assembly to a wired [src]. Temp: [air_contents.temperature-T0C]")
				assemble_bomb(W,user)
			else
				to_chat(user, "<span class='notice'>You stop attaching the assembly.</span>")
		else
			to_chat(user, "<span class='notice'>You need to wire the device up first.</span>")


	if(istype(W, /obj/item/weldingtool/))
		var/obj/item/weldingtool/WT = W
		if(WT.remove_fuel(1,user))
			if(!valve_welded)
				to_chat(user, "<span class='notice'>You begin welding the \the [src] emergency pressure relief valve.</span>")
				if(do_after(user, 40,src))
					to_chat(user, "<span class='notice'>You carefully weld \the [src] emergency pressure relief valve shut.</span><span class='warning'> \The [src] may now rupture under pressure!</span>")
					valve_welded = 1
					leaking = 0
				else
					bombers += "[key_name(user)] attempted to weld a [src]. [air_contents.temperature-T0C]"
					message_admins("[key_name_admin(user)] attempted to weld a [src]. [air_contents.temperature-T0C]")
					if(WT.welding)
						to_chat(user, "<span class='danger'>You accidentally rake \the [W] across \the [src]!</span>")
						integrity_max -= rand(2,6)
						integrity = min(integrity,integrity_max)
						air_contents.adjust_thermal_energy(rand(2000,50000))
				WT.eyecheck(user)
			else
				to_chat(user, "<span class='notice'>The emergency pressure relief valve has already been welded.</span>")
		add_fingerprint(user)



/obj/item/tank/attack_self(mob/user)
	. = ..()
	if(.)
		return
	add_fingerprint(user)
	if (!(src.air_contents))
		return
	ui_interact(user)

// There's GOT to be a better way to do this
	if (src.proxyassembly.assembly)
		src.proxyassembly.assembly.attack_self(user)

/obj/item/weapon/tank/ui_state()
	return GLOB.deep_inventory_state

/obj/item/tank/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Tank", name)
		ui.open()

/obj/item/tank/ui_static_data(mob/user, datum/tgui/ui)
	. = list (
		"defaultReleasePressure" = round(TANK_DEFAULT_RELEASE_PRESSURE),
		"minReleasePressure" = round(TANK_MIN_RELEASE_PRESSURE),
		"maxReleasePressure" = round(TANK_MAX_RELEASE_PRESSURE),
		"leakPressure" = round(TANK_LEAK_PRESSURE),
		"fragmentPressure" = round(TANK_FRAGMENT_PRESSURE)
	)

/obj/item/tank/ui_data(mob/user, datum/tgui/ui)
	. = list(
		"tankPressure" = round(air_contents.return_pressure()),
		"releasePressure" = round(distribute_pressure)
	)

	var/mob/living/carbon/C = user
	if(!istype(C))
		C = loc.loc
	if(C.internal == src)
		.["connected"] = TRUE
	else
		.["connected"] = FALSE

	.["maskConnected"] = FALSE
	if(C.wear_mask && (C.wear_mask.clothing_flags & ALLOWINTERNALS))
		.["maskConnected"] = TRUE
	else if(ishuman(C))
		var/mob/living/carbon/human/H = C
		if(H.head && (H.head.clothing_flags & ALLOWINTERNALS))
			.["maskConnected"] = TRUE

	return .

/obj/item/tank/ui_act(action, list/params, datum/tgui/ui)
	if(..())
		return TRUE
	switch(action)
		if("pressure")
			var/pressure = params["pressure"]
			if(pressure == "reset")
				pressure = TANK_DEFAULT_RELEASE_PRESSURE
				. = TRUE
			else if(pressure == "min")
				pressure = TANK_MIN_RELEASE_PRESSURE
				. = TRUE
			else if(pressure == "max")
				pressure = TANK_MAX_RELEASE_PRESSURE
				. = TRUE
			else if(text2num(pressure) != null)
				pressure = text2num(pressure)
				. = TRUE
			if(.)
				distribute_pressure = clamp(round(pressure), TANK_MIN_RELEASE_PRESSURE, TANK_MAX_RELEASE_PRESSURE)
		if("toggle")
			toggle_valve(usr)
			. = TRUE

/obj/item/tank/proc/toggle_valve(var/mob/user)
	if(istype(loc,/mob/living/carbon))
		var/mob/living/carbon/location = loc
		if(location.internal == src)
			location.internal = null
			location.internals.icon_state = "internal0"
			to_chat(user, "<span class='notice'>You close the tank release valve.</span>")
			if (location.internals)
				location.internals.icon_state = "internal0"
		else
			var/can_open_valve
			if(location.wear_mask && (location.wear_mask.clothing_flags & ALLOWINTERNALS))
				can_open_valve = 1
			else if(istype(location,/mob/living/carbon/human))
				var/mob/living/carbon/human/H = location
				if(H.head && (H.head.clothing_flags & ALLOWINTERNALS))
					can_open_valve = 1

			if(can_open_valve)
				location.internal = src
				to_chat(user, "<span class='notice'>You open \the [src] valve.</span>")
				if (location.internals)
					location.internals.icon_state = "internal1"
			else
				to_chat(user, "<span class='warning'>You need something to connect to \the [src].</span>")

/obj/item/tank/proc/remove_air_by_flag(flag, amount)
	. = air_contents.remove_by_flag(flag, amount)
	START_PROCESSING(SSobj, src)

/obj/item/tank/return_air()
	return air_contents

/obj/item/tank/assume_air(datum/gas_mixture/giver)
	. = ..()
	START_PROCESSING(SSobj, src)

/obj/item/tank/assume_gas(gasid, moles, temp)
	. = ..()
	START_PROCESSING(SSobj, src)

/obj/item/tank/adjust_thermal_energy(joules)
	. = ..()
	START_PROCESSING(SSobj, src)

/obj/item/tank/remove_moles(moles)
	. = ..()
	START_PROCESSING(SSobj, src)

/obj/item/tank/remove_volume(liters)
	. = ..()
	START_PROCESSING(SSobj, src)

/obj/item/tank/proc/remove_air_volume(volume_to_return)
	if(!air_contents)
		return null

	var/tank_pressure = air_contents.return_pressure()
	if(tank_pressure < distribute_pressure)
		distribute_pressure = tank_pressure

	var/moles_needed = distribute_pressure*volume_to_return/(R_IDEAL_GAS_EQUATION*air_contents.temperature)

	return remove_moles(moles_needed)

/obj/item/tank/process(delta_time)
	//Allow for reactions
	air_contents.react() //cooking up air tanks - add phoron and oxygen, then heat above PHORON_MINIMUM_BURN_TEMPERATURE
	if(gauge_icon)
		update_gauge()
	check_status()

/**
 * Encodes data for AtmosTank in tgui/interfaces/common/Atmos.tsx
 */
/obj/item/tank/proc/tgui_tank_data()
	return list(
		"name" = name,
		"pressure" = air_contents?.return_pressure(),
		"volume" = air_contents.volume,
		"pressureLimit" = TANK_IDEAL_PRESSURE,
	)

/obj/item/tank/proc/add_bomb_overlay()
	cut_overlays()
	var/list/overlays_to_add = list()
	if(wired)
		overlays_to_add += "bomb_assembly"
		if(proxyassembly.assembly)
			var/icon/test = get_flat_icon(proxyassembly.assembly)
			test.Shift(SOUTH,1)
			test.Shift(WEST,3)
			overlays_to_add += test
	add_overlay(overlays_to_add)

/obj/item/tank/proc/update_gauge()
	var/gauge_pressure = 0
	if(air_contents)
		gauge_pressure = air_contents.return_pressure()
		if(gauge_pressure > TANK_IDEAL_PRESSURE)
			gauge_pressure = -1
		else
			gauge_pressure = round((gauge_pressure/TANK_IDEAL_PRESSURE)*gauge_cap)

	if(gauge_pressure == last_gauge_pressure)
		return

	last_gauge_pressure = gauge_pressure
	add_bomb_overlay()
	var/indicator = "[gauge_icon][(gauge_pressure == -1) ? "overload" : gauge_pressure]"
	if(!tank_gauge_cache[indicator])
		tank_gauge_cache[indicator] = image(icon, indicator)
	add_overlay(tank_gauge_cache[indicator])

/obj/item/tank/proc/check_status()
	//Handle exploding, leaking, and rupturing of the tank

	if(!air_contents)
		return 0

	var/pressure = air_contents.return_pressure()
	if(pressure > TANK_FRAGMENT_PRESSURE)
		if(integrity <= 7)
			if(!istype(src.loc,/obj/item/transfer_valve))
				message_admins("Explosive tank rupture! last key to touch the tank was [src.fingerprintslast].")
				log_game("Explosive tank rupture! last key to touch the tank was [src.fingerprintslast].")

			//Give the gas a chance to build up more pressure through reacting
			air_contents.react()
			air_contents.react()
			air_contents.react()

			pressure = air_contents.return_pressure()
			var/strength = ((pressure-TANK_FRAGMENT_PRESSURE)/TANK_FRAGMENT_SCALE)

			var/mult = ((src.air_contents.volume/140)**(1/2)) * (air_contents.total_moles**2/3)/((29*0.64) **2/3) //tanks appear to be experiencing a reduction on scale of about 0.64 total moles
			//tanks appear to be experiencing a reduction on scale of about 0.64 total moles



			var/turf/simulated/T = get_turf(src)
			T.hotspot_expose(src.air_contents.temperature, 70, 1)
			if(!T)
				return

			T.assume_air(air_contents)
			explosion(
				get_turf(loc),
				round(min(BOMBCAP_DVSTN_RADIUS, ((mult)*strength)*0.15)),
				round(min(BOMBCAP_HEAVY_RADIUS, ((mult)*strength)*0.35)),
				round(min(BOMBCAP_LIGHT_RADIUS, ((mult)*strength)*0.80)),
				round(min(BOMBCAP_FLASH_RADIUS, ((mult)*strength)*1.20)),
				)


			var/num_fragments = round(rand(8,10) * sqrt(strength * mult))
			src.fragmentate(T, num_fragments, rand(5) + 7, list(/obj/projectile/bullet/pellet/fragment/tank/small = 7,/obj/projectile/bullet/pellet/fragment/tank = 2,/obj/projectile/bullet/pellet/fragment/strong = 1))

			if(istype(loc, /obj/item/transfer_valve))
				var/obj/item/transfer_valve/TTV = loc
				TTV.remove_tank(src)
				qdel(TTV)
			if(src)
				qdel(src)
		else
			integrity -=7

	else if(pressure > TANK_RUPTURE_PRESSURE)
		#ifdef FIREDBG
		log_debug(SPAN_DEBUGWARNING("[x],[y] tank is rupturing: [pressure] kPa, integrity [integrity]"))
		#endif

		air_contents.react()

		if(integrity <= 0)
			var/turf/simulated/T = get_turf(src)
			if(!T)
				return
			T.assume_air(air_contents)
			playsound(get_turf(src), 'sound/weapons/Gunshot_shotgun.ogg', 20, 1)
			visible_message("[icon2html(thing = src, target = world)] <span class='danger'>\The [src] flies apart!</span>", "<span class='warning'>You hear a bang!</span>")
			T.hotspot_expose(air_contents.temperature, 70, 1)


			var/strength = 1+((pressure-TANK_LEAK_PRESSURE)/TANK_FRAGMENT_SCALE)

			var/mult = (air_contents.total_moles**2/3)/((29*0.64) **2/3) //tanks appear to be experiencing a reduction on scale of about 0.64 total moles

			var/num_fragments = round(rand(6,8) * sqrt(strength * mult)) //Less chunks, but bigger
			src.fragmentate(T, num_fragments, 7, list(/obj/projectile/bullet/pellet/fragment/tank/small = 1,/obj/projectile/bullet/pellet/fragment/tank = 5,/obj/projectile/bullet/pellet/fragment/strong = 4))

			if(istype(loc, /obj/item/transfer_valve))
				var/obj/item/transfer_valve/TTV = loc
				TTV.remove_tank(src)
			qdel(src)

		else
			if(!valve_welded)
				integrity-= 3
				src.leaking = 1
			else
				integrity-= 5

	else if(pressure > TANK_LEAK_PRESSURE || air_contents.temperature - T0C > failure_temp)

		if((integrity <= 17 || src.leaking) && !valve_welded)
			var/turf/simulated/T = get_turf(src)
			if(!T)
				return
			var/datum/gas_mixture/environment = loc.return_air()
			var/env_pressure = environment.return_pressure()
			var/tank_pressure = src.air_contents.return_pressure()

			var/release_ratio = 0.002
			if(tank_pressure)
				release_ratio = clamp(0.002, sqrt(max(tank_pressure-env_pressure,0)/tank_pressure),1)

			var/datum/gas_mixture/leaked_gas = air_contents.remove_ratio(release_ratio)
			//dynamic air release based on ambient pressure

			T.assume_air(leaked_gas)
			if(!leaking)
				visible_message("[icon2html(thing = src, target = world)] <span class='warning'>\The [src] relief valve flips open with a hiss!</span>", "You hear hissing.")
				playsound(src.loc, 'sound/effects/spray.ogg', 10, 1, -3)
				leaking = 1
				#ifdef FIREDBG
				log_debug(SPAN_DEBUG("<span class='warning'>[x],[y] tank is leaking: [pressure] kPa, integrity [integrity]</span>"))
				#endif
		else
			integrity-= 1
	else
		if(integrity < integrity_max)
			integrity++
			if(leaking)
				integrity++
			if(integrity == integrity_max)
				leaking = 0

/obj/item/tank/proc/onetankbomb(fill = 1)
	var/phoron_amt = 4 + rand(4)
	var/oxygen_amt = 6 + rand(8)

	if(fill == 2)
		phoron_amt = 10
		oxygen_amt = 15
	else if (!fill)
		phoron_amt = 3
		oxygen_amt = 4.5


	air_contents.gas[GAS_ID_PHORON] = phoron_amt
	air_contents.gas[GAS_ID_OXYGEN] = oxygen_amt
	air_contents.update_values()
	valve_welded = 1
	air_contents.temperature = PHORON_MINIMUM_BURN_TEMPERATURE-1

	wired = 1

	var/obj/item/assembly_holder/H = new(src)
	proxyassembly.assembly = H
	H.master = proxyassembly

	H.update_icon()

	add_overlay("bomb_assembly")

/obj/item/tank/oxygen/welded
	valve_welded = TRUE

/obj/item/tank/phoron/welded
	valve_welded = TRUE

/obj/item/tank/phoron/onetankbomb/Initialize(mapload)
	. = ..()
	onetankbomb()

/obj/item/tank/oxygen/onetankbomb/Initialize(mapload)
	. = ..()
	onetankbomb()

/obj/item/tank/phoron/onetankbomb/full/Initialize(mapload)
	. = ..()
	onetankbomb(2)

/obj/item/tank/oxygen/onetankbomb/full/Initialize(mapload)
	. = ..()
	onetankbomb(2)

/obj/item/tank/phoron/onetankbomb/small/Initialize(mapload)
	. = ..()
	onetankbomb(0)

/obj/item/tank/oxygen/onetankbomb/small/Initialize(mapload)
	. = ..()
	onetankbomb(0)

/////////////////////////////////
///Pulled from rewritten bomb.dm
/////////////////////////////////

/obj/item/tankassemblyproxy
	name = "Tank assembly proxy"
	desc = "Used as a stand in to trigger single tank assemblies... but you shouldn't see this."
	var/obj/item/tank/tank = null
	var/obj/item/assembly_holder/assembly = null


/obj/item/tankassemblyproxy/receive_signal()	//This is mainly called by the sensor through sense() to the holder, and from the holder to here.
	tank.ignite()	//boom (or not boom if you made shijwtty mix)

/obj/item/tankassemblyproxy/Destroy()
	. = ..()
	tank = null
	assembly = null

/obj/item/tank/proc/assemble_bomb(W, user)	//Bomb assembly proc. This turns assembly+tank into a bomb
	var/obj/item/assembly_holder/S = W
	var/mob/M = user
	if(!S.secured)										//Check if the assembly is secured
		return
	if(isigniter(S.a_left) == isigniter(S.a_right))		//Check if either part of the assembly has an igniter, but if both parts are igniters, then fuck it
		return

	M.temporarily_remove_from_inventory(S, INV_OP_FORCE | INV_OP_SHOULD_NOT_INTERCEPT | INV_OP_SILENT)
	if(!M.put_in_active_hand(src))		//Equips the bomb if possible, or puts it on the floor.
		forceMove(M.drop_location())

	proxyassembly.assembly = S	//Tell the bomb about its assembly part
	S.master = proxyassembly		//Tell the assembly about its new owner
	S.forceMove(src)			//Move the assembly

	update_icon()


	add_bomb_overlay()

	return

///This happens when a bomb is told to explode
/obj/item/tank/proc/ignite()
	var/obj/item/assembly_holder/assy = proxyassembly.assembly
	var/ign = assy.a_right
	var/obj/item/other = assy.a_left

	if (isigniter(assy.a_left))
		ign = assy.a_left
		other = assy.a_right

	other.dropInto(get_turf(src))
	qdel(ign)
	assy.master = null
	proxyassembly.assembly = null
	qdel(assy)
	update_icon()
	update_gauge()

	air_contents.adjust_thermal_energy(15000)


/obj/item/tankassemblyproxy/update_icon()
	if(assembly)
		tank.update_icon()
		tank.add_overlay("bomb_assembly")
	else
		tank.update_icon()
		tank.cut_overlay("bomb_assembly")

/obj/item/tankassemblyproxy/HasProximity(atom/movable/AM)
	if(assembly)
		assembly.HasProximity(AM)
