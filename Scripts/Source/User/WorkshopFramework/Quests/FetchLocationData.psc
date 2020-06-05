; ---------------------------------------------
; WorkshopFramework:Quests:FetchLocationData.psc - by kinggath
; ---------------------------------------------
; Reusage Rights ------------------------------
; You are free to use this script or portions of it in your own mods, provided you give me credit in your description and maintain this section of comments in any released source code (which includes the IMPORTED SCRIPT CREDIT section to give credit to anyone in the associated Import scripts below.
; 
; Warning !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
; Do not directly recompile this script for redistribution without first renaming it to avoid compatibility issues issues with the mod this came from.
; 
; IMPORTED SCRIPT CREDIT
; N/A
; ---------------------------------------------

Scriptname WorkshopFramework:Quests:FetchLocationData extends Quest

Group Aliases
	LocationAlias Property RequestedLocation Auto Const Mandatory
	ReferenceAlias Property MapMarker Auto Const Mandatory
EndGroup

int Property iReserveID = -1 Auto Hidden

Event OnStoryScript(Keyword akKeyword, Location akLocation, ObjectReference akRef1, ObjectReference akRef2, int aiValue1, int aiValue2)
	iReserveID = aiValue1
EndEvent