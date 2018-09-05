; ---------------------------------------------
; WorkshopFramework:ObjectRefs:Thread_PlaceObject.psc - by kinggath
; ---------------------------------------------
; Reusage Rights ------------------------------
; You are free to use this script or portions of it in your own mods, provided you give me credit in your description and maintain this section of comments in any released source code (which includes the IMPORTED SCRIPT CREDIT section to give credit to anyone in the associated Import scripts below).
; 
; Warning !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
; Do not directly recompile this script for redistribution without first renaming it to avoid compatibility issues with the mod this came from.
; 
; IMPORTED SCRIPT CREDITS
; N/A
; ---------------------------------------------

Scriptname WorkshopFramework:ObjectRefs:Thread_PlaceObject extends WorkshopFramework:Library:ObjectRefs:Thread

import WorkshopFramework:Library:DataStructures

; -
; Consts
; -


; - 
; Editor Properties
; -

Form Property PositionHelper Auto Const Mandatory
{ XMarker object for temporary positioning }
WorkshopParentScript Property WorkshopParent Auto Const Mandatory
ActorValue Property PowerRequired Auto Const Mandatory
{ Autofill }
ActorValue Property PowerGenerated Auto Const Mandatory
{ Autofill }
ActorValue Property WorkshopResourceObject Auto Const Mandatory
{ Autofill }
Keyword Property WorkshopCanBePowered Auto Const Mandatory
{ Autofill }
Keyword Property WorkshopItemKeyword Auto Const Mandatory
{ Autofill }
Keyword Property WorkshopRadioObject Auto Const Mandatory
{ Autofill }
Keyword Property WorkshopEventRadioBeacon Auto Const Mandatory
{ Found on WorkshopParent script property of same name }
Scene Property WorkshopRadioScene01 Auto Const Mandatory
{ Found on WorkshopParent script property of same name }
ObjectReference Property WorkshopRadioRef Auto Mandatory
{ Found on WorkshopParent script property of same name }

float Property workshopRadioInnerRadius = 9000.0 Auto Const
{ TODO: Tap into globals after rewriting WSScripts }
float Property workshopRadioOuterRadius = 20000.0 Auto Const
{ TODO: Tap into globals after rewriting WSScripts }


; -
; Properties
; -

WorkshopScript Property kWorkshopRef Auto Hidden
ObjectReference Property kSpawnAt Auto Hidden
Form Property SpawnMe Auto Hidden
Float Property fPosX = 0.0 Auto Hidden
Float Property fPosY = 0.0 Auto Hidden
Float Property fPosZ = 0.0 Auto Hidden 
Float Property fAngleX = 0.0 Auto Hidden 
Float Property fAngleY = 0.0 Auto Hidden 
Float Property fAngleZ = 0.0 Auto Hidden 
Float Property fScale = 0.0 Auto Hidden
Bool Property bFauxPowered = true Auto Hidden
ActorValueSet[] Property TagAVs Auto Hidden
Keyword[] Property TagKeywords Auto Hidden
LinkToMe[] Property LinkedRefs Auto Hidden

; -
; Events
; -

Event ObjectReference.OnLoad(ObjectReference akSenderRef)
	akSenderRef.SetAngle(fAngleX, fAngleY, fAngleZ)
	akSenderRef.SetPosition(fPosX, fPosY, fPosZ)
	
	if(fScale != 1.0 && fScale != 0)
		akSenderRef.SetScale(fScale)
	endif
	
	UnregisterForAllEvents()
	SelfDestruct()
EndEvent

; - 
; Functions 
; -

Function AddTagAVSet(ActorValue aAV, Float afValue)
	ActorValueSet newSet = new ActorValueSet
	
	newSet.AVForm = aAV
	newSet.fValue = afValue
	
	if( ! TagAVs)
		TagAVs = new ActorValueSet[0]
	endif
	
	TagAVs.Add(newSet)
EndFunction

Function AddTagKeyword(Keyword aKeyword)
	if( ! TagKeywords)
		TagKeywords = new Keyword[0]
	endif
	
	TagKeywords.Add(aKeyword)
EndFunction

Function AddLinkedRef(ObjectReference akLinkToMe, Keyword akLinkWithKeyword = None)
	LinkToMe newLink = new LinkToMe
	
	newLink.kLinkToMe = akLinkToMe
	newLink.LinkWith = akLinkWithKeyword
	
	if( ! LinkedRefs)
		LinkedRefs = new LinkToMe[0]
	endif
	
	LinkedRefs.Add(newLink)
EndFunction

	
Function ReleaseObjectReferences()
	kSpawnAt = None
	LinkedRefs = None
	kWorkshopRef = None
	WorkshopRadioRef = None
EndFunction


Function RunCode()
	ObjectReference kResult = None
	; Place temporary object at player
	ObjectReference kTempPositionHelper = kSpawnAt.PlaceAtMe(PositionHelper, abInitiallyDisabled = true)
	
	if(kTempPositionHelper)
		; Rotation can only occur in the loaded area, so handle that immediately
		kTempPositionHelper.SetAngle(fAngleX, fAngleY, fAngleZ)
		kTempPositionHelper.SetPosition(fPosX, fPosY, fPosZ)
		
		; Place Object at temp object
		kResult = kTempPositionHelper.PlaceAtMe(SpawnMe, 1, abInitiallyDisabled = false, abDeleteWhenAble = false)
				
		if(kResult)
			if(kResult as Actor)
				; Actors must be enabled before they can be manipulated
				kResult.Enable(false)
				
				if(kResult.Is3dLoaded())
					; Can't rotate/scale actors until their 3d is loaded
					kResult.SetAngle(fAngleX, fAngleY, fAngleZ)
					kResult.SetPosition(fPosX, fPosY, fPosZ)
					
					if(fScale != 1)
						kResult.SetScale(fScale)
					endif
				else
					bAutoDestroy = false
					RegisterForRemoteEvent(kResult, "OnLoad")
				endif
			endif
			
			if(fScale != 1)
				kResult.SetScale(fScale)
			endif
			
			if(kWorkshopRef)
				kResult.SetLinkedRef(kWorkshopRef, WorkshopItemKeyword)
				
				if(bFauxPowered && kResult.HasKeyword(WorkshopCanBePowered))
					FauxPowered(kResult)
				endif
					
				WorkshopObjectScript asWorkshopObject = kResult as WorkshopObjectScript
				if(asWorkshopObject)
					asWorkshopObject.workshopID = kWorkshopRef.GetWorkshopID()
					
					kWorkshopRef.RecalculateWorkshopResources()
					
					if(asWorkshopObject.HasKeyword(WorkshopRadioObject))
						ConfigureRadio(asWorkshopObject, kWorkshopRef)				
					endif
					
					asWorkshopObject.HandleCreation(true)
				endif
			endif
			
			if(TagAVs)
				int i = 0
				while(i < TagAVs.Length)
					kResult.SetValue(TagAVs[i].AVForm, TagAVs[i].fValue)
					
					i += 1
				endWhile
			endif
			
			if(TagKeywords)
				int i = 0
				while(i < TagKeywords.Length)
					kResult.AddKeyword(TagKeywords[i])
					
					i += 1
				endWhile
			endif
			
			if(LinkedRefs)
				int i = 0
				while(i < LinkedRefs.Length)
					kResult.SetLinkedRef(LinkedRefs[i].kLinkToMe, LinkedRefs[i].LinkWith)
					
					i += 1
				endWhile
			endif
		endif
	endif
EndFunction


Function ConfigureRadio(WorkshopObjectScript akWorkshopObject, WorkshopScript akWorkshopRef)
	; Copied from WorkshopParent.UpdateRadioObject
	
	if(akWorkshopObject.bRadioOn && akWorkshopObject.IsPowered())
		if(akWorkshopRef.WorkshopRadioRef)
			akWorkshopRef.WorkshopRadioRef.Enable() ; enable in case this is a unique station
			akWorkshopObject.MakeTransmitterRepeater(akWorkshopRef.WorkshopRadioRef, akWorkshopRef.workshopRadioInnerRadius, akWorkshopRef.workshopRadioOuterRadius)
			if(akWorkshopRef.WorkshopRadioScene.IsPlaying() == false)
				akWorkshopRef.WorkshopRadioScene.Start()
			endif
		else 
			akWorkshopObject.MakeTransmitterRepeater(WorkshopRadioRef, workshopRadioInnerRadius, workshopRadioOuterRadius)
			if(WorkshopRadioScene01.IsPlaying() == false)
				WorkshopRadioScene01.Start()
			endif
		endif
		
		if(akWorkshopRef.RadioBeaconFirstRecruit == false)
			WorkshopEventRadioBeacon.SendStoryEvent(akRef1 = akWorkshopRef)
		endif
	else
		akWorkshopObject.MakeTransmitterRepeater(NONE, 0, 0)
		
		; if unique radio, turn it off completely
		if(akWorkshopRef.WorkshopRadioRef && akWorkshopRef.bWorkshopRadioRefIsUnique)
			akWorkshopRef.WorkshopRadioRef.Disable()
			; stop custom scene if unique
			akWorkshopRef.WorkshopRadioScene.Stop()
		endif
	endif
	
	; send power change event so quests can react to this
	WorkshopParent.SendPowerStateChangedEvent(akWorkshopObject, akWorkshopRef)	
EndFunction


Function FauxPowered(ObjectReference akRef)
	float fPowerReq = akRef.GetValue(PowerRequired)
	if(fPowerReq > 0)
		akRef.ModValue(PowerRequired, fPowerReq * -1)
	endif
	
	akRef.SetValue(PowerGenerated, 0.1)
	akRef.SetValue(WorkshopResourceObject, 1.0)
EndFunction