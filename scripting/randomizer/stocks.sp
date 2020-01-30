stock void Client_AddHealth(int iClient, int iAdditionalHeal, int iMaxOverHeal=0)
{
	int iMaxHealth = SDK_GetMaxHealth(iClient);
	int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
	int iTrueMaxHealth = iMaxHealth+iMaxOverHeal;
	
	if (iHealth < iTrueMaxHealth)
	{
		iHealth += iAdditionalHeal;
		if (iHealth > iTrueMaxHealth) iHealth = iTrueMaxHealth;
		SetEntProp(iClient, Prop_Send, "m_iHealth", iHealth);
	}
}

stock int TF2_CreateAndEquipWeapon(int iClient, int iIndex, int iSlot = -1)
{
	char sClassname[256];
	TF2Econ_GetItemClassName(iIndex, sClassname, sizeof(sClassname));
	
	//We want to translate classname to correct classname AND slot wanted
	for (int iClass = CLASS_MIN; iClass <= CLASS_MAX; iClass++)
	{
		int iClassSlot = TF2_GetSlotFromIndex(iIndex, view_as<TFClassType>(iClass));
		if (iClassSlot > -1 && (iSlot == iClassSlot || iSlot == -1))
		{
			TF2Econ_TranslateWeaponEntForClass(sClassname, sizeof(sClassname), view_as<TFClassType>(iClass));
			break;
		}
	}
	
	PrintToChatAll("iIndex %d sClassname %s", iIndex, sClassname);
	int iWeapon = CreateEntityByName(sClassname);
	
	if (IsValidEntity(iWeapon))
	{
		SetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex", iIndex);
		SetEntProp(iWeapon, Prop_Send, "m_bInitialized", 1);
		
		// Allow quality / level override by updating through the offset.
		char sNetClass[64];
		GetEntityNetClass(iWeapon, sNetClass, sizeof(sNetClass));
		SetEntData(iWeapon, FindSendPropInfo(sNetClass, "m_iEntityQuality"), 6);
		SetEntData(iWeapon, FindSendPropInfo(sNetClass, "m_iEntityLevel"), 1);
			
		SetEntProp(iWeapon, Prop_Send, "m_iEntityQuality", 6);
		SetEntProp(iWeapon, Prop_Send, "m_iEntityLevel", 1);
		
		DispatchSpawn(iWeapon);
		SetEntProp(iWeapon, Prop_Send, "m_bValidatedAttachedEntity", true);
		
		if (StrContains(sClassname, "tf_weapon") == 0)
		{
			EquipPlayerWeapon(iClient, iWeapon);
			
			//Not sure if this even works
			int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
			if (iAmmoType > -1)
			{
				int iAmmo = SDK_GetMaxAmmo(iClient, iAmmoType);
				SetEntProp(iClient, Prop_Send, "m_iAmmo", iAmmo, _, iAmmoType);
			}
		}
		else if (StrContains(sClassname, "tf_wearable") == 0)
		{
			SDK_EquipWearable(iClient, iWeapon);
		}
		else
		{
			AcceptEntityInput(iWeapon, "Kill");
			return -1;
		}
	}
	else
	{
		PrintToChatAll("Unable to create weapon for client (%N), class (%d), classname (%s)", iClient, TF2_GetPlayerClass(iClient), sClassname);
		LogError("Unable to create weapon for client (%N), class (%d), classname (%s)", iClient, TF2_GetPlayerClass(iClient), sClassname);
	}
	
	return iWeapon;
}

stock bool TF2_WeaponFindAttribute(int iWeapon, int iAttrib, float &flVal)
{
	Address addAttrib = TF2Attrib_GetByDefIndex(iWeapon, iAttrib);
	if (addAttrib == Address_Null)
	{
		int iItemDefIndex = GetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex");
		int iAttributes[16];
		float flAttribValues[16];

		int iMaxAttrib = TF2Attrib_GetStaticAttribs(iItemDefIndex, iAttributes, flAttribValues);
		for (int i = 0; i < iMaxAttrib; i++)
		{
			if (iAttributes[i] == iAttrib)
			{
				flVal = flAttribValues[i];
				return true;
			}
		}
		return false;
	}
	flVal = TF2Attrib_GetValue(addAttrib);
	return true;
}

stock int TF2_GetItemInSlot(int iClient, int iSlot)
{
	int iWeapon = GetPlayerWeaponSlot(iClient, iSlot);
	
	//If weapon not found in slot, check if it a wearable
	if (!IsValidEdict(iWeapon))
		return TF2_GetWearableInSlot(iClient, iSlot);
	
	return iWeapon;
}

stock int TF2_GetWearableInSlot(int iClient, int iSlot)
{
	//SDK call for get wearable doesnt work if different class use different wearable
	//Still a problem with weapons useable with more than 1 slots... may be able to get away with it if checking GetPlayerWeaponSlot first
	
	int iWearable = MaxClients+1;
	while ((iWearable = FindEntityByClassname(iWearable, "tf_wearable*")) > MaxClients)
	{
		if (GetEntPropEnt(iWearable, Prop_Send, "m_hOwnerEntity") == iClient || GetEntPropEnt(iWearable, Prop_Send, "moveparent") == iClient)
		{
			int iIndex = GetEntProp(iWearable, Prop_Send, "m_iItemDefinitionIndex");
			
			for (int iClass = CLASS_MIN; iClass <= CLASS_MAX; iClass++)
			{
				int iWearableSlot = TF2Econ_GetItemSlot(iIndex, view_as<TFClassType>(iClass));
				if (iWearableSlot > -1 && iSlot == iWearableSlot)
					return iWearable;
			}
		}
	}
	
	return -1;
}

stock int TF2_GetSlotFromItem(int iClient, int iWeapon)
{
	for (int iSlot = 0; iSlot <= WeaponSlot_BuilderEngie; iSlot++)
		if (iWeapon == TF2_GetItemInSlot(iClient, iSlot))
			return iSlot;
	
	return -1;
}

stock int TF2_GetSlotFromIndex(int iIndex, TFClassType nClass = TFClass_Unknown)
{
	int iSlot = TF2Econ_GetItemSlot(iIndex, nClass);
	if (iSlot >= 0)
	{
		// Econ reports wrong slots for Engineer and Spy
		switch (nClass)
		{
			case TFClass_Engineer:
			{
				switch (iSlot)
				{
					case 4: iSlot = WeaponSlot_BuilderEngie; // Toolbox
					case 5: iSlot = WeaponSlot_PDABuild; // Construction PDA
					case 6: iSlot = WeaponSlot_PDADestroy; // Destruction PDA
				}
			}
			case TFClass_Spy:
			{
				switch (iSlot)
				{
					case 1: iSlot = WeaponSlot_Primary; // Revolver
					case 4: iSlot = WeaponSlot_Secondary; // Sapper
					case 5: iSlot = WeaponSlot_PDADisguise; // Disguise Kit
					case 6: iSlot = WeaponSlot_InvisWatch; // Invis Watch
				}
			}
		}
	}
	
	return iSlot;
}

stock TFClassType TF2_GetDefaultClassFromItem(int iClient, int iWeapon)
{
	int iIndex = GetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex");
	int iSlot = TF2_GetSlotFromItem(iClient, iWeapon);
	
	for (int iClass = CLASS_MIN; iClass <= CLASS_MAX; iClass++)
	{
		int iClassSlot = TF2_GetSlotFromIndex(iIndex, view_as<TFClassType>(iClass));
		if (iClassSlot == iSlot)
			return view_as<TFClassType>(iClass);
	}
	
	return TFClass_Unknown;
}

stock void TF2_RemoveItemInSlot(int iClient, int iSlot)
{
	TF2_RemoveWeaponSlot(iClient, iSlot);

	int iWearable = TF2_GetWearableInSlot(iClient, iSlot);
	if (iWearable > MaxClients)
	{
		SDK_RemoveWearable(iClient, iWearable);
		AcceptEntityInput(iWearable, "Kill");
	}
}

stock int TF2_GetCurrentAmmo(int iWeapon)
{
	if (!HasEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType")) return -1;

	int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
	if (iAmmoType == -1) return -1;
	
	int iClient = GetEntPropEnt(iWeapon, Prop_Send, "m_hOwnerEntity"); 
	return GetEntProp(iClient, Prop_Send, "m_iAmmo", _, iAmmoType);
}

stock void TF2_SetAmmo(int iWeapon, int iAmmo)
{
	if (!HasEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType")) return;

	int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
	if (iAmmoType == -1) return;
	
	int iClient = GetEntPropEnt(iWeapon, Prop_Send, "m_hOwnerEntity"); 
	SetEntProp(iClient, Prop_Send, "m_iAmmo", iAmmo, _, iAmmoType);
}

stock void TF2_SetMetal(int iClient, int iMetal)
{
	SetEntProp(iClient, Prop_Send, "m_iAmmo", iMetal, _, 3);
}

stock int TF2_GetItemFromAmmoType(int iClient, int iAmmoType)
{
	for (int iSlot = 0; iSlot <= WeaponSlot_BuilderEngie; iSlot++)
	{
		int iWeapon = TF2_GetItemInSlot(iClient, iSlot);
		if (iWeapon <= MaxClients)
			continue;
		
		if (GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType") == iAmmoType)
			return iWeapon;
	}
	
	return -1;
}

stock void StringToLower(char[] sString)
{
	int iLength = strlen(sString);
	for(int i = 0; i < iLength; i++)
		sString[i] = CharToLower(sString[i]);
}