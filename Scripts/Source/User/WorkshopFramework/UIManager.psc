; ---------------------------------------------
; WorkshopFramework:UIManager.psc - by kinggath
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

Scriptname WorkshopFramework:UIManager extends WorkshopFramework:Library:SlaveQuest
{ Handles various user interface related tasks }

import WorkshopFramework:Library:DataStructures
import WorkshopFramework:Library:UtilityFunctions


CustomEvent BarterSelectMenu_SelectionMade
CustomEvent Settlement_SelectionMade

; ---------------------------------------------
; Consts
; ---------------------------------------------

Float fBarterWaitLoopIncrement = 0.1 Const
Float fWaitForMenuAvailableLoopIncrement = 0.1 Const
int iMessageSelectorSource_Array = 0 Const
int iMessageSelectorSource_Formlist = 1 Const
int iMessageSelectorReturn_Failure = -1 Const
int iMessageSelectorReturn_Cancel = -2 Const

Group DoNotEdit
	int Property iAcceptStolen_None = 0 autoReadOnly
	int Property iAcceptStolen_Only = 1 autoReadOnly
	int Property iAcceptStolen_Either = 2 autoReadOnly
EndGroup

; ---------------------------------------------
; Editor Properties 
; ---------------------------------------------

Group Controllers
	WorkshopParentScript Property WorkshopParent Auto Const Mandatory
EndGroup

Group Aliases
	ReferenceAlias Property PhantomVendorAlias Auto Const Mandatory
	ReferenceAlias Property PhantomVendorContainerAlias Auto Const Mandatory
	ReferenceAlias Property SelectCache_Settlements Auto Const Mandatory
	ReferenceAlias Property SafeSpawnPoint Auto Const Mandatory
EndGroup

Group Assets
	Formlist Property PhantomVendorBuySellList Auto Const Mandatory
	
	Faction Property PhantomVendorFaction_Either Auto Const Mandatory
	Faction Property PhantomVendorFaction_StolenOnly Auto Const Mandatory
	Faction Property PhantomVendorFaction_NonStolenOnly Auto Const Mandatory
	
	Faction Property PhantomVendorFaction_Either_Unfiltered Auto Const Mandatory
	Faction Property PhantomVendorFaction_StolenOnly_Unfiltered Auto Const Mandatory
	Faction Property PhantomVendorFaction_NonStolenOnly_Unfiltered Auto Const Mandatory
EndGroup

Group MessageSelectorSystem
	Message Property MessageSelector_Default Auto Const Mandatory
	Message Property MessageSelector_NoOptions Auto Const Mandatory
	Form Property NameHolderForm_SelectAnOption Auto Const Mandatory
	GlobalVariable Property MenuControl_MessageSelector_MoreInfo Auto Const Mandatory
	
	ReferenceAlias Property MessageSelectorTitleAlias Auto Const Mandatory
	ReferenceAlias[] Property MessageSelectorItemLineAliases Auto Const Mandatory
	{ REMINDER: You must set up different Message forms to handle more aliases, our default (MessageSelector_Default) only displays one for the title of the selection type and another for the current option. }
EndGroup

Group SettlementSelect
	Form[] Property Selectables_Settlements Auto Const Mandatory
	ReferenceAlias[] Property ApplyNames_Settlements Auto Const Mandatory
	LocationAlias[] Property StoreNames_Settlements Auto Const Mandatory
	Keyword Property SelectableSettlementKeyword Auto Const Mandatory
	Form Property VendorName_Settlements Auto Const Mandatory
EndGroup

; ---------------------------------------------
; Vars
; ---------------------------------------------

bool bPhantomVendorInUse = false
ObjectReference kCurrentCacheRef ; Stores latest cache ref so we can return the items to it
WorkshopScript[] kLastSelectedSettlements
Int iBarterSelectCallbackID = -1

bool bMessageSelectorInUse = false
Int iMessageSelector_SelectedOption = -1
Form[] MessageSelectorFormArray
Formlist MessageSelectorFormlist

Form[] SelectionPool01
Form[] SelectionPool02
Form[] SelectionPool03
Form[] SelectionPool04
Form[] SelectionPool05
Form[] SelectionPool06
Form[] SelectionPool07
Form[] SelectionPool08 ; Up to 1024 items

; Store barter modifiers sent from function call
Bool bVendorSideEqualsChoice = false
Bool bUsingReferences = false
Formlist SelectedResultsFormlist
Formlist StartBarterSelectedFormList

int iTotalSelected = 0
int iAwaitingSorting = 0

int Property iSplitFormlistIncrement = 30 Auto Hidden ; We might need to make this editable to avoid crashing when showing barter menu for a large formlist

; ---------------------------------------------
; Events 
; ---------------------------------------------

Event OnMenuOpenCloseEvent(string asMenuName, bool abOpening)
	if(asMenuName == "BarterMenu" && ! abOpening)
		UnregisterForMenuOpenCloseEvent("BarterMenu")
		RemoveAllInventoryEventFilters()
		
		; We should have already unregistered for this, but let's just make sure
		ObjectReference kPhantomVendorContainerRef = PhantomVendorContainerAlias.GetRef()
		UnregisterForRemoteEvent(kPhantomVendorContainerRef, "OnItemAdded")
		
		ProcessBarterSelection()
		
		; Unlock phantom vendor system
		bPhantomVendorInUse = false
	endif
EndEvent

Event ObjectReference.OnItemAdded(ObjectReference akAddedTo, Form akBaseItem, int aiItemCount, ObjectReference akItemReference, ObjectReference akSourceContainer)
    ObjectReference kPhantomVendorContainerRef = PhantomVendorContainerAlias.GetRef()
	Actor kPhantomVendorRef = PhantomVendorAlias.GetActorRef()
	
    if(akAddedTo == kPhantomVendorContainerRef)
		ModTrace("[UIManager] item " + akBaseItem + " added to " + akAddedTo + ", sorting. " + iAwaitingSorting + " items remaining.")
		
		Form SortMe = akBaseItem
		
		if(akItemReference == None)
			; Our barter system seems to only work correctly with references - likely a limitation of the dynamic updating of the vendor filter formlist. So we'll stash a reference copy in the vendor's "pockets" until we're done processing these events, then we'll move all of the items to the vendor container after we've unregistered for OnItemAdded (otherwise we'd have an infinite loop if we just dropped them into the vendor container). Failure to use refs causes the non-ref items to be removed when ShowBarterMenu is called.
			
			kPhantomVendorContainerRef.RemoveItem(akBaseItem)
			akItemReference = kPhantomVendorRef.PlaceAtMe(akBaseItem)
		endif
		
		if(bUsingReferences)
			SortMe = akItemReference
		endif
		
		if(SortItem(SortMe))
			if(StartBarterSelectedFormList != None && StartBarterSelectedFormList.HasForm(akItemReference))
				if(bVendorSideEqualsChoice)
					kPhantomVendorRef.AddItem(akItemReference)
				else
					PlayerRef.AddItem(akItemReference, abSilent = true)
				endif
			elseif(bVendorSideEqualsChoice)
				PlayerRef.AddItem(akItemReference, abSilent = true)
			else
				kPhantomVendorRef.AddItem(akItemReference)
			endif
		else
			kPhantomVendorContainerRef.RemoveItem(akItemReference) ; Get rid of this so player doesn't assume its a valid option
			ModTrace("[UIManager] Too many items to sort. Lost record of item " + akBaseItem)
		endif
		
		iAwaitingSorting -= 1
		if(iAwaitingSorting <= 0)
			Utility.Wait(1.0)
			; No longer need to monitor this event as we're only watching for items initially set up via the aAvailableOptionsFormlist
			UnregisterForRemoteEvent(kPhantomVendorContainerRef, "OnItemAdded")
			
			; Move any refs we created into the selection container now that we've unregistered for OnItemAdded
			PhantomVendorAlias.GetRef().RemoveAllItems(kPhantomVendorContainerRef)
			
			iAwaitingSorting = -999
			ModTrace("[UIManager] Completed sorting of barter items. Vendor container " + kPhantomVendorContainerRef + " has " + kPhantomVendorContainerRef.GetItemCount() + " items. The vendor has " + PhantomVendorAlias.GetRef().GetItemCount() + " items.")
		endif
    endif
EndEvent



; ---------------------------------------------
; Functions 
; ---------------------------------------------

Function HandlePlayerLoadedGame()
	bPhantomVendorInUse = false ; Make sure this never gets stuck
EndFunction

	; ---------------------------------------------
	; Barter Menu System 
	; ---------------------------------------------

Int Function ShowCachedBarterSelectMenu(Form afBarterDisplayNameForm, ObjectReference aAvailableOptionsCacheContainerReference, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2)
	return ShowCachedBarterSelectMenuV3(afBarterDisplayNameForm, aAvailableOptionsCacheContainerReference, aStoreResultsIn, aFilterKeywords, aiAcceptStolen)
EndFunction


Int Function ShowCachedBarterSelectMenuV2(Form afBarterDisplayNameForm, ObjectReference aAvailableOptionsCacheContainerReference, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false)
	return ShowCachedBarterSelectMenuV3(afBarterDisplayNameForm, aAvailableOptionsCacheContainerReference, aStoreResultsIn, aFilterKeywords, aiAcceptStolen, aStartBarterSelectedFormlist, abVendorSideEqualsChoice, abUsingReferences)
EndFunction

Int Function ShowCachedBarterSelectMenuV3(Form afBarterDisplayNameForm, ObjectReference aAvailableOptionsCacheContainerReference, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false, Float afMaxWaitForBarterSelect = 0.0)
	if(bPhantomVendorInUse)
		if(afMaxWaitForBarterSelect != 0.0)
			Float fWaitedTime = 0.0
			if(afMaxWaitForBarterSelect < 0)
				afMaxWaitForBarterSelect = 99999999
			endif
			
			while(bPhantomVendorInUse && fWaitedTime < afMaxWaitForBarterSelect)
				Utility.WaitMenuMode(fWaitForMenuAvailableLoopIncrement)
				fWaitedTime += fWaitForMenuAvailableLoopIncrement
			endWhile
		else
			return -1
		endif
	endif
	
	bPhantomVendorInUse = true
	
	ResetPhantomVendor()
	ModTrace("[UIManager] ShowCachedBarterSelectMenu called. aFilterKeywords = " + aFilterKeywords)
	PreparePhantomVendor(afBarterDisplayNameForm, aFilterKeywords, aiAcceptStolen)
	
	bVendorSideEqualsChoice = abVendorSideEqualsChoice
	bUsingReferences = abUsingReferences
	SelectedResultsFormlist = aStoreResultsIn 
	StartBarterSelectedFormList = aStartBarterSelectedFormlist
	
	; Add items to inventory and start barter
	Actor kPhantomVendorRef = PhantomVendorAlias.GetActorRef()
	ObjectReference kPhantomVendorContainerRef = PhantomVendorContainerAlias.GetRef()
		; Store cache ref so we can return the cache items
	kCurrentCacheRef = aAvailableOptionsCacheContainerReference
	iAwaitingSorting += kCurrentCacheRef.GetItemCount()
	
	if(iAwaitingSorting > 0)
		; Monitor for the items to be added from the selection pool	
		RegisterForRemoteEvent(kPhantomVendorContainerRef, "OnItemAdded")
		ModTrace("[UIManager] Moving all items from " + kCurrentCacheRef + " to " + kPhantomVendorContainerRef)
		kCurrentCacheRef.RemoveAllItems(kPhantomVendorContainerRef)
		
		; Wait for OnItemAdded events to complete
		int iWaitCount = 0
		int iMaxWaitCount = iAwaitingSorting
		while(iAwaitingSorting > 0 && iWaitCount < iMaxWaitCount)
			Utility.Wait(0.1)
			iWaitCount += 1
		endWhile
		
		iWaitCount = 0
		while(iAwaitingSorting <= 0 && iAwaitingSorting > -999 && iWaitCount < 20) ; -999 is used by our OnItemAdded event to tell us when it's safe to continue
			Utility.Wait(0.1) 
			iWaitCount += 1
		endWhile
	endif
	
	iBarterSelectCallbackID = Utility.RandomInt(1, 999999)
	
	ModTrace("[UIManager] Pause over, calling ShowBarterMenu on " + kPhantomVendorRef + ", iBarterSelectCallbackID = " + iBarterSelectCallbackID)
	
	kPhantomVendorRef.ShowBarterMenu()
	
	ModTrace("[UIManager] ShowBarterMenu called, returning iBarterSelectCallbackID = " + iBarterSelectCallbackID)
	
	return iBarterSelectCallbackID
EndFunction

; ------------------------------------
; ShowCachedBarterSelectMenuAndWait
;
; This is a simpler version of the ShowCachedBarterSelectMenu function that doesn't require monitoring for an event to know when to get the results. 
;
; Non-wait version above is still preferred if you're using it with something that shouldn't be blocked for long periods of time, as it doesn't hold your calling script the entire time that the player is selecting plus the time for processing the selection afterwards.
; ------------------------------------

Int Function ShowCachedBarterSelectMenuAndWait(Form afBarterDisplayNameForm, ObjectReference aAvailableOptionsCacheContainerReference, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false, Float afMaxWaitTime = 60.0)
	return ShowCachedBarterSelectMenuAndWaitV2(afBarterDisplayNameForm, aAvailableOptionsCacheContainerReference, aStoreResultsIn, aFilterKeywords, aiAcceptStolen, aStartBarterSelectedFormlist, abVendorSideEqualsChoice, abUsingReferences, afMaxWaitTime)
EndFunction

Int Function ShowCachedBarterSelectMenuAndWaitV2(Form afBarterDisplayNameForm, ObjectReference aAvailableOptionsCacheContainerReference, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false, Float afMaxWaitTime = 60.0, Float afMaxWaitForBarterSelect = 0.0)
	if(bPhantomVendorInUse) 
		if(afMaxWaitForBarterSelect != 0.0)
			Float fWaitedTime = 0.0
			if(afMaxWaitForBarterSelect < 0)
				afMaxWaitForBarterSelect = 99999999
			endif
			
			while(bPhantomVendorInUse && fWaitedTime < afMaxWaitForBarterSelect)
				Utility.WaitMenuMode(fWaitForMenuAvailableLoopIncrement)
				fWaitedTime += fWaitForMenuAvailableLoopIncrement
			endWhile
		else
			return -1
		endif
	endif   ; REMINDER - do not set this to true after this, as the menu function will do so
	
	Int iResult = ShowCachedBarterSelectMenuV3(afBarterDisplayNameForm, aAvailableOptionsCacheContainerReference, aStoreResultsIn, aFilterKeywords, aiAcceptStolen, aStartBarterSelectedFormlist, abVendorSideEqualsChoice, abUsingReferences, afMaxWaitForBarterSelect)
	
	if(iResult > -1)
		; Callback ID received, let's begin our waiting loop
		Float fWaitedTime = 0.0
		while(bPhantomVendorInUse && fWaitedTime < afMaxWaitTime)
			Utility.WaitMenuMode(fBarterWaitLoopIncrement)
			fWaitedTime += fBarterWaitLoopIncrement
		endWhile
	endif
	
	return iResult
EndFunction

int Function ShowFormlistBarterSelectMenu(Form afBarterDisplayNameForm, Formlist aAvailableOptionsFormlist, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2)
	return ShowFormlistBarterSelectMenuV3(afBarterDisplayNameForm, aAvailableOptionsFormlist, aStoreResultsIn, aFilterKeywords, aiAcceptStolen)
EndFunction

int Function ShowFormlistBarterSelectMenuV2(Form afBarterDisplayNameForm, Formlist aAvailableOptionsFormlist, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false)
	return ShowFormlistBarterSelectMenuV3(afBarterDisplayNameForm, aAvailableOptionsFormlist, aStoreResultsIn, aFilterKeywords, aiAcceptStolen, aStartBarterSelectedFormlist, abVendorSideEqualsChoice, abUsingReferences)
EndFunction

int Function ShowFormlistBarterSelectMenuV3(Form afBarterDisplayNameForm, Formlist aAvailableOptionsFormlist, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false, Float afMaxWaitForBarterSelect = 0.0)
	if(bPhantomVendorInUse) 
		if(afMaxWaitForBarterSelect != 0.0)
			Float fWaitedTime = 0.0
			if(afMaxWaitForBarterSelect < 0)
				afMaxWaitForBarterSelect = 99999999
			endif
			
			while(bPhantomVendorInUse && fWaitedTime < afMaxWaitForBarterSelect)
				Utility.WaitMenuMode(fWaitForMenuAvailableLoopIncrement)
				fWaitedTime += fWaitForMenuAvailableLoopIncrement
			endWhile
		else
			return -1
		endif
	endif
	
	bPhantomVendorInUse = true
	
	ResetPhantomVendor()
	PreparePhantomVendor(afBarterDisplayNameForm, aFilterKeywords, aiAcceptStolen)
	
	SelectedResultsFormlist = aStoreResultsIn 
	bVendorSideEqualsChoice = abVendorSideEqualsChoice
	bUsingReferences = abUsingReferences
	StartBarterSelectedFormList = aStartBarterSelectedFormlist
	
	; Add items to vendor container and start barter
	Actor kPhantomVendorRef = PhantomVendorAlias.GetActorRef()
	ObjectReference kPhantomVendorContainerRef = PhantomVendorContainerAlias.GetRef()
	
	; Monitor for the items to be added from the selection pool	
	RegisterForRemoteEvent(kPhantomVendorContainerRef, "OnItemAdded")
	
	Int iListSize = aAvailableOptionsFormlist.GetSize()
	iAwaitingSorting = iListSize
	int i = 0
	int iLastAdded = 0
	while(i < iListSize)
		if(Mod((i + 1), iSplitFormlistIncrement) == 0)
			Var[] kArgs = new Var[4]
			kArgs[0] = aAvailableOptionsFormlist
			kArgs[1] = kPhantomVendorContainerRef
			kArgs[2] = i
			kArgs[3] = iSplitFormlistIncrement
			
			Utility.CallGlobalFunctionNoWait("WorkshopFramework:Library:UtilityFunctions", "AddFormlistItemsToContainer", kArgs)
			
			Utility.Wait(0.1) ; Pause to slow down OnItemAdded events and ensure all items are added before ShowBarterMenu is called below
			
			iLastAdded = i + iSplitFormlistIncrement - 1
		endif
		
		i += 1
	endWhile
	
	if(iLastAdded + 1 < iListSize)
		; Still entries remaining
		Var[] kArgs = new Var[3]
		kArgs[0] = aAvailableOptionsFormlist
		kArgs[1] = kPhantomVendorContainerRef
		kArgs[2] = iLastAdded
		kArgs[3] = iSplitFormlistIncrement
		
		Utility.CallGlobalFunctionNoWait("WorkshopFramework:Library:UtilityFunctions", "AddFormlistItemsToContainer", kArgs)
		
		Utility.Wait(0.1) ; Pause to slow down OnItemAdded events and ensure all items are added before ShowBarterMenu is called below
	endif
	
	iBarterSelectCallbackID = Utility.RandomInt(1, 999999)
	kPhantomVendorRef.ShowBarterMenu()
	
	return iBarterSelectCallbackID
EndFunction

; ------------------------------------
; ShowFormlistBarterSelectMenuAndWait
;
; This is a simpler version of the ShowFormlistBarterSelectMenu function that doesn't require monitoring for an event to know when to get the results. 
;
; Non-wait version above is still preferred if you're using it with something that shouldn't be blocked for long periods of time, as it doesn't hold your calling script the entire time that the player is selecting plus the time for processing the selection afterwards.
; ------------------------------------

Int Function ShowFormlistBarterSelectMenuAndWait(Form afBarterDisplayNameForm, Formlist aAvailableOptionsFormlist, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false, Float afMaxWaitTime = 60.0)
	return ShowFormlistBarterSelectMenuAndWaitV2(afBarterDisplayNameForm, aAvailableOptionsFormlist, aStoreResultsIn, aFilterKeywords, aiAcceptStolen, aStartBarterSelectedFormlist, abVendorSideEqualsChoice, abUsingReferences, afMaxWaitTime)
EndFunction

Int Function ShowFormlistBarterSelectMenuAndWaitV2(Form afBarterDisplayNameForm, Formlist aAvailableOptionsFormlist, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false, Float afMaxWaitTime = 60.0, Float afMaxWaitForBarterSelect = 0.0)
	if(bPhantomVendorInUse) 
		if(afMaxWaitForBarterSelect != 0.0)
			Float fWaitedTime = 0.0
			if(afMaxWaitForBarterSelect < 0)
				afMaxWaitForBarterSelect = 99999999
			endif
			
			while(bPhantomVendorInUse && fWaitedTime < afMaxWaitForBarterSelect)
				Utility.WaitMenuMode(fWaitForMenuAvailableLoopIncrement)
				fWaitedTime += fWaitForMenuAvailableLoopIncrement
			endWhile
		else
			return -1
		endif
	endif   ; REMINDER - do not set this to true after this, as the menu function will do so
	
	Int iResult = ShowFormlistBarterSelectMenuV3(afBarterDisplayNameForm, aAvailableOptionsFormlist, aStoreResultsIn, aFilterKeywords, aiAcceptStolen, aStartBarterSelectedFormlist, abVendorSideEqualsChoice, abUsingReferences, afMaxWaitForBarterSelect)
	
	if(iResult > -1)
		; Callback ID received, let's begin our waiting loop
		Float fWaitedTime = 0.0
		while(bPhantomVendorInUse && fWaitedTime < afMaxWaitTime)
			Utility.WaitMenuMode(fBarterWaitLoopIncrement)
			fWaitedTime += fBarterWaitLoopIncrement
		endWhile
	endif
	
	return iResult
EndFunction



int Function ShowBarterSelectMenu(Form afBarterDisplayNameForm, Form[] aAvailableOptions, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2)
	return ShowBarterSelectMenuV3(afBarterDisplayNameForm, aAvailableOptions, aStoreResultsIn, aFilterKeywords, aiAcceptStolen)
EndFunction

int Function ShowBarterSelectMenuV2(Form afBarterDisplayNameForm, Form[] aAvailableOptions, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false)	
	return ShowBarterSelectMenuV3(afBarterDisplayNameForm, aAvailableOptions, aStoreResultsIn, aFilterKeywords, aiAcceptStolen, aStartBarterSelectedFormlist, abVendorSideEqualsChoice, abUsingReferences)
EndFunction

int Function ShowBarterSelectMenuV3(Form afBarterDisplayNameForm, Form[] aAvailableOptions, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false, Float afMaxWaitForBarterSelect = 0.0)
	if(bPhantomVendorInUse)
		if(afMaxWaitForBarterSelect != 0.0)
			Float fWaitedTime = 0.0
			if(afMaxWaitForBarterSelect < 0)
				afMaxWaitForBarterSelect = 99999999
			endif
			
			while(bPhantomVendorInUse && fWaitedTime < afMaxWaitForBarterSelect)
				Utility.WaitMenuMode(fWaitForMenuAvailableLoopIncrement)
				fWaitedTime += fWaitForMenuAvailableLoopIncrement
			endWhile
		else
			return -1
		endif
	endif
	
	bPhantomVendorInUse = true
	
	ResetPhantomVendor()
	PreparePhantomVendor(afBarterDisplayNameForm, aFilterKeywords, aiAcceptStolen)
	
	SelectedResultsFormlist = aStoreResultsIn
	StartBarterSelectedFormList = aStartBarterSelectedFormlist
	bVendorSideEqualsChoice = abVendorSideEqualsChoice
	bUsingReferences = abUsingReferences	
	
	; Add items to vendor container and start barter
	Actor kPhantomVendorRef = PhantomVendorAlias.GetActorRef()
	ObjectReference kPhantomVendorContainerRef = PhantomVendorContainerAlias.GetRef()
	
	Int iCount = aAvailableOptions.Length
	int i = 0
	while(i < iCount)
		Form FormToAdd = aAvailableOptions[i]
		
		if(FormToAdd != None)
			if(SortItem(FormToAdd))
				kPhantomVendorContainerRef.AddItem(FormToAdd)
			endif
		endif
		
		i += 1
	endWhile
		
	iBarterSelectCallbackID = Utility.RandomInt(1, 999999)
	kPhantomVendorRef.ShowBarterMenu()
	
	return iBarterSelectCallbackID
EndFunction

; ------------------------------------
; ShowBarterSelectMenuAndWait
;
; This is a simpler version of the ShowBarterSelectMenu function that doesn't require monitoring for an event to know when to get the results. 
;
; Non-wait version above is still preferred if you're using it with something that shouldn't be blocked for long periods of time, as it doesn't hold your calling script the entire time that the player is selecting plus the time for processing the selection afterwards.
; ------------------------------------
Int Function ShowBarterSelectMenuAndWait(Form afBarterDisplayNameForm, Form[] aAvailableOptions, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false, Float afMaxWaitTime = 60.0)
	return ShowBarterSelectMenuAndWaitV2(afBarterDisplayNameForm, aAvailableOptions, aStoreResultsIn, aFilterKeywords, aiAcceptStolen, aStartBarterSelectedFormlist, abVendorSideEqualsChoice, abUsingReferences, afMaxWaitTime)
EndFunction

Int Function ShowBarterSelectMenuAndWaitV2(Form afBarterDisplayNameForm, Form[] aAvailableOptions, Formlist aStoreResultsIn, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2, Formlist aStartBarterSelectedFormlist = None, Bool abVendorSideEqualsChoice = false, Bool abUsingReferences = false, Float afMaxWaitTime = 60.0, Float afMaxWaitForBarterSelect = 0.0)
	if(bPhantomVendorInUse)
		if(afMaxWaitForBarterSelect != 0.0)
			Float fWaitedTime = 0.0
			if(afMaxWaitForBarterSelect < 0)
				afMaxWaitForBarterSelect = 99999999
			endif
			
			while(bPhantomVendorInUse && fWaitedTime < afMaxWaitForBarterSelect)
				Utility.WaitMenuMode(fWaitForMenuAvailableLoopIncrement)
				fWaitedTime += fWaitForMenuAvailableLoopIncrement
			endWhile
		else
			return -1
		endif
	endif   ; REMINDER - do not set this to true after this, as the menu function will do so
	
	Int iResult = ShowBarterSelectMenuV3(afBarterDisplayNameForm, aAvailableOptions, aStoreResultsIn, aFilterKeywords, aiAcceptStolen, aStartBarterSelectedFormlist, abVendorSideEqualsChoice, abUsingReferences, afMaxWaitForBarterSelect)
	
	if(iResult > -1)
		; Callback ID received, let's begin our waiting loop
		Float fWaitedTime = 0.0
		while(bPhantomVendorInUse && fWaitedTime < afMaxWaitTime)
			Utility.WaitMenuMode(fBarterWaitLoopIncrement)
			fWaitedTime += fBarterWaitLoopIncrement
		endWhile
	endif
	
	return iResult
EndFunction


Function ProcessBarterSelection()
	;Debug.MessageBox("ProcessBarterSelection called, dumping selection pool")
	;ModTrace("SelectionPool01: " + SelectionPool01)
	ProcessItemPool(SelectionPool01)
	ProcessItemPool(SelectionPool02)
	ProcessItemPool(SelectionPool03)
	ProcessItemPool(SelectionPool04)
	ProcessItemPool(SelectionPool05)
	ProcessItemPool(SelectionPool06)
	ProcessItemPool(SelectionPool07)
	ProcessItemPool(SelectionPool08)
	
	; Return any remaining items to player as they were not part of our pool, player likely dropped them in to see what would happen
	ObjectReference kPhantomVendorContainerRef = PhantomVendorContainerAlias.GetRef()
	
	ModTrace("[UIManager] Moving remaining " + kPhantomVendorContainerRef.GetItemCount() + " items from phantom vendor container to player.")
	
	kPhantomVendorContainerRef.RemoveAllItems(PlayerRef)
	
	if(kCurrentCacheRef == SelectCache_Settlements.GetRef())
		Var[] kArgs = new Var[kLastSelectedSettlements.Length + 2]
		kArgs[0] = iBarterSelectCallbackID
		kArgs[1] = kLastSelectedSettlements.Length
		
		int i = 0		
		while(i < kLastSelectedSettlements.Length)
			int iNextArgsIndex = 2 + i
			kArgs[iNextArgsIndex] = kLastSelectedSettlements[i]
			
			i += 1
		endWhile
		
		; Send event
		SendCustomEvent("Settlement_SelectionMade", kArgs)		
	else
		; Send event
		Var[] kArgs = new Var[3]
		kArgs[0] = iBarterSelectCallbackID
		kArgs[1] = iTotalSelected
		kArgs[2] = SelectedResultsFormlist
		
		SendCustomEvent("BarterSelectMenu_SelectionMade", kArgs)
	endif
	
	; Clear our stored cache ref
	kCurrentCacheRef = None
	SelectCache_Settlements.GetRef().RemoveAllItems()
	
	; Clear out memory used by having phantom vendor set up
	ResetPhantomVendor()
EndFunction


Bool Function SortItem(Form aItemType)
	if(SelectionPool01 == None)
		SelectionPool01 = new Form[0]
	endif
	
	if( ! SortToPool(SelectionPool01, aItemType))
		if(SelectionPool02 == None)
			SelectionPool02 = new Form[0]
		endif
		
		if( ! SortToPool(SelectionPool02, aItemType))
			if(SelectionPool03 == None)
				SelectionPool03 = new Form[0]
			endif
	
			if( ! SortToPool(SelectionPool03, aItemType))
				if(SelectionPool04 == None)
					SelectionPool04 = new Form[0]
				endif
	
				if( ! SortToPool(SelectionPool04, aItemType))
					if(SelectionPool05 == None)
						SelectionPool05 = new Form[0]
					endif
	
					if( ! SortToPool(SelectionPool05, aItemType))    
						if(SelectionPool06 == None)
							SelectionPool06 = new Form[0]
						endif
	
						if( ! SortToPool(SelectionPool06, aItemType))
							if(SelectionPool07 == None)
								SelectionPool07 = new Form[0]
							endif
							
							if( ! SortToPool(SelectionPool07, aItemType))
								if(SelectionPool08 == None)
									SelectionPool08 = new Form[0]
								endif
								
								if( ! SortToPool(SelectionPool08, aItemType))
									ModTrace("[UIManager] Ran out of space to sort items.")
									return false
								endif
							endif
						endif
					endif
				endif
			endif
		endif
	endif
    
    return true
EndFunction


Bool Function SortToPool(Form[] aItemPool, Form aItemType)
    if(aItemPool.Find(aItemType) >= 0)
        return true
    elseif(aItemPool.Length < 128)
        aItemPool.Add(aItemType)
        return true
    endif
    
    return false
EndFunction


Function ProcessItemPool(Form[] aItemPool)
	ObjectReference kPhantomVendorContainerRef = PhantomVendorContainerAlias.GetRef()
	;ModTrace("ProcessItemPool called. ItemPool size = " + aItemPool.Length + ", bVendorSideEqualsChoice = " + bVendorSideEqualsChoice)
    While(aItemPool.Length > 0)
        Form thisForm = aItemPool[0]
        
		Bool bSelected = false
		if(bVendorSideEqualsChoice)
			if(bUsingReferences)
				bSelected = ((thisForm as ObjectReference).GetContainer() == kPhantomVendorContainerRef)
			else
				bSelected = (kPhantomVendorContainerRef.GetItemCount(thisForm) > 0)
			endif
			
			;ModTrace("[ProcessItemPool] Checking for " + thisForm + " in " + kPhantomVendorContainerRef + " which currently has " + kPhantomVendorContainerRef.GetItemCount() + " items, found? :" + bSelected + " also checking phantom vendor " + PhantomVendorAlias.GetRef() + ", found there? : " + PhantomVendorAlias.GetRef().GetItemCount(thisForm))
		else
			int iPlayerItemCount = 0
			if(bUsingReferences)
				bSelected = ((thisForm as ObjectReference).GetContainer() == PlayerRef)
				if(bSelected)
					iPlayerItemCount = 1
				endif
			else
				iPlayerItemCount = PlayerRef.GetItemCount(thisForm)
				bSelected = (iPlayerItemCount > 0)
			endif
			
			;ModTrace("[ProcessItemPool] Checking for " + thisForm + " in " + PlayerRef + ", found :" + iPlayerItemCount)
		endif
		
		if(bSelected)
			;ModTrace("ProcessItemPool form was selected: " + thisForm)
		
			iTotalSelected += 1
			
			int iSettlementIndex = Selectables_Settlements.Find(thisForm)
			if(iSettlementIndex >= 0)
				if( ! kLastSelectedSettlements)
					kLastSelectedSettlements = new WorkshopScript[0]
				endif
				
				Location settlementLocation = StoreNames_Settlements[iSettlementIndex].GetLocation()
				
				if(settlementLocation != None)										
					kLastSelectedSettlements.Add(WorkshopParent.GetWorkshopFromLocation(settlementLocation))
				endif
			else
				if(bUsingReferences)
					; Since using references, we need to put these items somewhere or they will be destroyed when removed from inventory
					ObjectReference kDroppedRef = (thisForm as ObjectReference)
					kDroppedRef.Drop(true)
				
					kDroppedRef.MoveTo(SafeSpawnPoint.GetRef())
				
					SelectedResultsFormlist.AddForm(kDroppedRef)
					
					if(kCurrentCacheRef != None)
						kCurrentCacheRef.AddItem(kDroppedRef)
					endif
				else
					SelectedResultsFormlist.AddForm(thisForm)	
				endif
			endif
			
			if( ! bUsingReferences)
				; return to cache				
				if(bVendorSideEqualsChoice)
					kPhantomVendorContainerRef.RemoveItem(thisForm, 1, abSilent = true, akOtherContainer = kCurrentCacheRef)
				else	
					PlayerRef.RemoveItem(thisForm, 1, abSilent = true, akOtherContainer = kCurrentCacheRef)
				endif
			endif
		else
			;ModTrace("[UIManager] Removing item " + thisForm + " from phantom vendor container " + kPhantomVendorContainerRef + ", which currently has " + kPhantomVendorContainerRef.GetItemCount(thisForm) + ", sending to kCurrentCacheRef " + kCurrentCacheRef)
			
			; Item was left in select container, don't count as selected, but return to cache
			if(bVendorSideEqualsChoice)
				PlayerRef.RemoveItem(thisForm, 1, abSilent = true, akOtherContainer = kCurrentCacheRef)
			else
				;ModTrace("[UIManager] Removing item " + thisForm + " from phantom vendor container " + kPhantomVendorContainerRef + ", which currently has " + kPhantomVendorContainerRef.GetItemCount(thisForm) + ", sending to kCurrentCacheRef " + kCurrentCacheRef)
				
				kPhantomVendorContainerRef.RemoveItem(thisForm, 1, abSilent = true, akOtherContainer = kCurrentCacheRef)
			endif
        endif
        
        aItemPool.Remove(0)
    EndWhile
EndFunction


Function ResetPhantomVendor()
	ModTrace("[UIManager] ResetPhantomVendor called.")
	; Reset previous select data
	Actor kPhantomVendorRef = PhantomVendorAlias.GetReference() as Actor
	kPhantomVendorRef.RemoveFromFaction(PhantomVendorFaction_Either)
	kPhantomVendorRef.RemoveFromFaction(PhantomVendorFaction_StolenOnly)
	kPhantomVendorRef.RemoveFromFaction(PhantomVendorFaction_NonStolenOnly)
	
	ObjectReference kPhantomVendorContainerRef = PhantomVendorContainerAlias.GetReference()
	kPhantomVendorContainerRef.RemoveAllItems() ; Get rid of copies from previous
	ModTrace("[UIManager] ResetPhantomVendor: RemoveAllItems complete.")
	kPhantomVendorContainerRef.SetActorRefOwner(PlayerRef) ; Prevent player from getting in trouble for stealing
	
	bVendorSideEqualsChoice = false
	SelectedResultsFormlist = None
	StartBarterSelectedFormList = None
	
	; Clear out sorting pools
	iAwaitingSorting = 0
	iTotalSelected = 0
	
	SelectionPool01 = new Form[0]
	SelectionPool02 = new Form[0]
	SelectionPool03 = new Form[0]
	SelectionPool04 = new Form[0]
	SelectionPool05 = new Form[0]
	SelectionPool06 = new Form[0]
	SelectionPool07 = new Form[0]
	SelectionPool08 = new Form[0]
EndFunction


Function PreparePhantomVendor(Form afBarterDisplayNameForm, Keyword[] aFilterKeywords = None, Int aiAcceptStolen = 2)
	Actor kPhantomVendorRef = PhantomVendorAlias.GetReference() as Actor
	ObjectReference kPhantomVendorContainerRef = PhantomVendorContainerAlias.GetRef()
	
	; Remove items from the vendor's pockets - they shouldn't have anything, but just in case
	kPhantomVendorRef.RemoveAllItems()
	
	; Setup phantom vendor for this selection	
	if(aFilterKeywords == None || aFilterKeywords.Length == 0)
		if(aiAcceptStolen == iAcceptStolen_None)
			kPhantomVendorRef.AddToFaction(PhantomVendorFaction_NonStolenOnly_Unfiltered)
		elseif(aiAcceptStolen == iAcceptStolen_Only)
			kPhantomVendorRef.AddToFaction(PhantomVendorFaction_StolenOnly_Unfiltered)
		else
			kPhantomVendorRef.AddToFaction(PhantomVendorFaction_Either_Unfiltered)
		endif
		
		AddInventoryEventFilter(None)	
	else		
		int i = 0
		while(i < aFilterKeywords.Length)
			PhantomVendorBuySellList.AddForm(aFilterKeywords[i])
			
			i += 1
		endWhile
		
		if(aiAcceptStolen == iAcceptStolen_None)
			kPhantomVendorRef.AddToFaction(PhantomVendorFaction_NonStolenOnly)
		elseif(aiAcceptStolen == iAcceptStolen_Only)
			kPhantomVendorRef.AddToFaction(PhantomVendorFaction_StolenOnly)
		else
			kPhantomVendorRef.AddToFaction(PhantomVendorFaction_Either)
		endif
		
		AddInventoryEventFilter(PhantomVendorBuySellList)	
	endif
	
	RegisterForMenuOpenCloseEvent("BarterMenu")
	
	; Clear previous name by removing from alias
	PhantomVendorAlias.Clear()
	
	; Return to alias 
	PhantomVendorAlias.ForceRefTo(kPhantomVendorRef)
	
	; Stamp text replacement data the Message form expects
	kPhantomVendorRef.AddTextReplacementData("SelectionName", afBarterDisplayNameForm)
EndFunction


; 2.0.0 settlement select system
int Function ShowSettlementBarterSelectMenu(Form afBarterDisplayNameForm = None, WorkshopScript[] akExcludeSettlements = None)
	if(afBarterDisplayNameForm == None)
		afBarterDisplayNameForm = VendorName_Settlements
	endif
	
	kLastSelectedSettlements = new WorkshopScript[0]
	
	ObjectReference kSpawnPoint = SafeSpawnPoint.GetRef()
	ObjectReference kCacheRef_Settlements = SelectCache_Settlements.GetRef()
	kCacheRef_Settlements.RemoveAllItems() ; We can't actually cache since player can install/uninstall settlements
	
	Location[] WorkshopLocations = WorkshopParent.WorkshopLocations
	WorkshopScript[] Workshops = WorkshopParent.Workshops
	WorkshopScript NukaWorldDummyWorkshop = None
	if(Game.IsPluginInstalled("DLCNukaWorld.esm"))
		NukaWorldDummyWorkshop = Game.GetFormFromFile(0x00047DFB, "DLCNukaWorld.esm") as WorkshopScript
		
		if( ! akExcludeSettlements)
			akExcludeSettlements = new WorkshopScript[0]
		endif
		
		akExcludeSettlements.Add(NukaWorldDummyWorkshop)
	endif
	
	int i = 0
	while(i < WorkshopLocations.Length)
		if(akExcludeSettlements == None || akExcludeSettlements.Find(Workshops[i]) < 0)
			StoreNames_Settlements[i].ForceLocationTo(WorkshopLocations[i])
			ObjectReference kSelectorRef = kSpawnPoint.PlaceAtMe(Selectables_Settlements[i])
			ApplyNames_Settlements[i].ApplyToRef(kSelectorRef)
			
			kCacheRef_Settlements.AddItem(kSelectorRef)
		endif
		
		i += 1
	endWhile
	
	Keyword[] FilterKeywords = new Keyword[1]
	FilterKeywords[0] = SelectableSettlementKeyword
	
	return ShowCachedBarterSelectMenu(afBarterDisplayNameForm, aAvailableOptionsCacheContainerReference = kCacheRef_Settlements, aStoreResultsIn = None, aFilterKeywords = FilterKeywords)
EndFunction


Function TestBarterSystem(int iTestNameChange = 0)
	Formlist scavList = Game.GetFormFromFile(0x00007B04, "WorkshopFramework.esm") as Formlist
	
	Form nameForm = Game.GetFormFromFile(0x0024A00F, "Fallout4.esm")
	
	if(iTestNameChange == 1)
		nameForm = Game.GetFormFromFile(0x00249AEB, "Fallout4.esm")
	endif
	
	Formlist holdList = Game.GetFormFromFile(0x0001CAE7, "WorkshopFramework.esm") as Formlist
	
	if(ShowFormlistBarterSelectMenuAndWait(nameForm, scavList, holdList))
		Debug.MessageBox("Wait completed. holdList has " + holdList.GetSize() + " entries.")
	endif
EndFunction

Function TestSettlementBarterSystem()
	ShowSettlementBarterSelectMenu(None, None)
EndFunction

Function CheckBarterContainer()
	ObjectReference kVendorContainerRef = PhantomVendorContainerAlias.GetRef()
	if(kVendorContainerRef != None)
		Debug.MessageBox(kVendorContainerRef.GetItemCount())
	else
		Debug.MessageBox("Failed to fetch phantom vendor container ref")
	endif
EndFunction


	; ---------------------------------------------
	; Message Select System
	; 
	; Uses a message to display an infinitely long formlist or array of items, displaying them one at a time to the player with Next/Previous/Select/More Info/Cancel buttons. If the player chooses select, the index of the item in that formlist or array is returned
	;
	; Because the game has a stack limit of 100 calls deep, this will asyncronously start a new call if the stack gets too deep.
	;
	; Return Values: -1 = error, -2 = user canceled selection
	; ---------------------------------------------

Int Function ShowMessageSelectorMenuAndWait(Form[] aSelectFromOptions, Form aMessageTitleNameHolder = None, Message aNoOptionsWarningOverride = None)
	return ShowMessageSelectorMenuAndWaitV2(aSelectFromOptions, aMessageTitleNameHolder, aNoOptionsWarningOverride)
EndFunction

	
Int Function ShowMessageSelectorMenuAndWaitV2(Form[] aSelectFromOptions, Form aMessageTitleNameHolder = None, Message aNoOptionsWarningOverride = None, Float afMaxWaitForSelector = 0.0)
	if( ! aSelectFromOptions)
		return iMessageSelectorReturn_Failure
	endif
	
	int iCount = aSelectFromOptions.Length
	if(iCount == 0)
		if(aNoOptionsWarningOverride != None)
			aNoOptionsWarningOverride.Show()
		else
			MessageSelector_NoOptions.Show()
		endif
		
		return iMessageSelectorReturn_Failure
	EndIf
	
	if(bMessageSelectorInUse)
		if(afMaxWaitForSelector != 0.0)
			Float fWaitedTime = 0.0
			if(afMaxWaitForSelector < 0)
				afMaxWaitForSelector = 99999999
			endif
			
			while(bMessageSelectorInUse && fWaitedTime < afMaxWaitForSelector)
				Utility.WaitMenuMode(fWaitForMenuAvailableLoopIncrement)
				fWaitedTime += fWaitForMenuAvailableLoopIncrement
			endWhile
		else
			return iMessageSelectorReturn_Failure
		endif
	endif
	
	bMessageSelectorInUse = true
	iMessageSelector_SelectedOption = -1
	MessageSelectorFormArray = aSelectFromOptions
	
	; Setup text replacement for title
	Form TitleForm = NameHolderForm_SelectAnOption
	if(aMessageTitleNameHolder != None)
		TitleForm = aMessageTitleNameHolder
	endif
	
	ObjectReference kTitleRef
	
	if(TitleForm as ObjectReference)
		kTitleRef = TitleForm as ObjectReference
	else
		kTitleRef = SafeSpawnPoint.GetRef().PlaceAtMe(TitleForm)
	endif
	
	MessageSelectorTitleAlias.ForceRefTo(kTitleRef)
	
	; Start the selection loop
	ShowMessageSelectorMenuLoop_InternalOnly(aiIndexToDisplay = 0, aiSource = iMessageSelectorSource_Array)
	
	bMessageSelectorInUse = false
	MessageSelectorFormArray = new Form[0] ; Clear this array
	MessageSelectorFormlist = None
	
	return iMessageSelector_SelectedOption
EndFunction


Int Function ShowMessageSelectorMenuFormlistAndWait(Formlist aSelectFromOptionsList, Form aMessageTitleNameHolder = None, Message aNoOptionsWarningOverride = None)
	return ShowMessageSelectorMenuFormlistAndWaitV2(aSelectFromOptionsList, aMessageTitleNameHolder, aNoOptionsWarningOverride)
EndFunction


Int Function ShowMessageSelectorMenuFormlistAndWaitV2(Formlist aSelectFromOptionsList, Form aMessageTitleNameHolder = None, Message aNoOptionsWarningOverride = None, Float afMaxWaitForSelector = 0.0)
	if( ! aSelectFromOptionsList)
		return iMessageSelectorReturn_Failure
	endif
	
	int iCount = aSelectFromOptionsList.GetSize()
	if(iCount == 0)
		if(aNoOptionsWarningOverride != None)
			aNoOptionsWarningOverride.Show()
		else
			MessageSelector_NoOptions.Show()
		endif
		
		return iMessageSelectorReturn_Failure
	EndIf
	
	
	if(bMessageSelectorInUse)
		if(afMaxWaitForSelector != 0.0)
			Float fWaitedTime = 0.0
			if(afMaxWaitForSelector < 0)
				afMaxWaitForSelector = 99999999
			endif
			
			while(bMessageSelectorInUse && fWaitedTime < afMaxWaitForSelector)
				Utility.WaitMenuMode(fWaitForMenuAvailableLoopIncrement)
				fWaitedTime += fWaitForMenuAvailableLoopIncrement
			endWhile
		else
			return iMessageSelectorReturn_Failure
		endif
	endif
	
	bMessageSelectorInUse = true
	
	MessageSelectorFormArray = new Form[0]
	iMessageSelector_SelectedOption = -1
	int iSource = iMessageSelectorSource_Formlist
	if(iCount <= 128) ; Convert to array which will be faster
		int i = 0
		while(i < iCount)
			MessageSelectorFormArray.Add(aSelectFromOptionsList.GetAt(i))
			
			i += 1
		endWhile
		
		iSource = iMessageSelectorSource_Array
	else
		MessageSelectorFormlist = aSelectFromOptionsList
	endif
	
	; Setup text replacement for title
	Form TitleForm = NameHolderForm_SelectAnOption
	if(aMessageTitleNameHolder != None)
		TitleForm = aMessageTitleNameHolder
	endif
	
	ObjectReference kTitleRef
	
	if(TitleForm as ObjectReference)
		kTitleRef = TitleForm as ObjectReference
	else
		kTitleRef = SafeSpawnPoint.GetRef().PlaceAtMe(TitleForm)
	endif
	
	MessageSelectorTitleAlias.ForceRefTo(kTitleRef)
	
	; Start the selection loop
	ShowMessageSelectorMenuLoop_InternalOnly(aiIndexToDisplay = 0, aiSource = iSource)
	
	bMessageSelectorInUse = false
	MessageSelectorFormArray = new Form[0] ; Clear this array
	MessageSelectorFormlist = None
	
	return iMessageSelector_SelectedOption
EndFunction

Function ShowMessageSelectorMenuLoop_InternalOnly(Int aiIndexToDisplay = 0, Int aiSource = 0)
	ObjectReference kSafeSpawnPoint = SafeSpawnPoint.GetRef()
	int iOptionCount = 0
	if(aiSource == iMessageSelectorSource_Array)
		iOptionCount = MessageSelectorFormArray.Length
	elseif(aiSource == iMessageSelectorSource_Formlist)
		iOptionCount = MessageSelectorFormlist.GetSize()			
	endif
	
	if(iOptionCount <= 0)
		return
	endif
	
	; Wait for player to select an option or cancel
	while(true)
		Form CurrentForm
		if(aiSource == iMessageSelectorSource_Array)
			CurrentForm = MessageSelectorFormArray[aiIndexToDisplay]
		elseif(aiSource == iMessageSelectorSource_Formlist)
			CurrentForm = MessageSelectorFormlist.GetAt(aiIndexToDisplay)			
		endif
		
		; Setup text replacement
		ObjectReference kNameRef = kSafeSpawnPoint.PlaceAtMe(CurrentForm)
		MessageSelectorItemLineAliases[0].ForceRefTo(kNameRef)
		
		; Should we show More Info option?
		MenuControl_MessageSelector_MoreInfo.SetValueInt(0)
		if(CurrentForm as WorkshopFramework:Forms:FormInformation && (CurrentForm as WorkshopFramework:Forms:FormInformation).InformationMessage != None)
			MenuControl_MessageSelector_MoreInfo.SetValueInt(1)
		endif
		
		; Display select menu
		int iSelectedOption = MessageSelector_Default.Show()
		
		; Handle selection
		if(iSelectedOption == 0) ; Next
			aiIndexToDisplay += 1
			
			if(aiIndexToDisplay >= iOptionCount)
				aiIndexToDisplay = 0
			endif
		elseif(iSelectedOption == 1) ; Previous
			aiIndexToDisplay -= 1
			
			if(aiIndexToDisplay < 0)
				aiIndexToDisplay = iOptionCount - 1
			endif
		elseif(iSelectedOption == 2) ; More Info
			(CurrentForm as WorkshopFramework:Forms:FormInformation).InformationMessage.Show()
		elseif(iSelectedOption == 3) ; Select
			iMessageSelector_SelectedOption = aiIndexToDisplay
			return
		else ; Cancel
			return
		endif
	endWhile
EndFunction



Function TestMessageSelectorSystem()
	Formlist scavList = Game.GetFormFromFile(0x00007B04, "WorkshopFramework.esm") as Formlist
	
	Form nameForm = Game.GetFormFromFile(0x00249AEB, "Fallout4.esm")
	
	int iSelection = ShowMessageSelectorMenuFormlistAndWait(scavList, aMessageTitleNameHolder = nameForm)
	
	Debug.MessageBox("Player selected option " + iSelection)
EndFunction
