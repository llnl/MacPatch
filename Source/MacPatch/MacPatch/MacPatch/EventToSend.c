//
//  EventToSend.c
/*
 Copyright (c) 2023, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Charles Heizer <heizer1 at llnl.gov>.
 LLNL-CODE-636469 All rights reserved.
 
 This file is part of MacPatch, a program for installing and patching
 software.
 
 MacPatch is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License (as published by the Free
 Software Foundation) version 2, dated June 1991.
 
 MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
 License for more details.
 
 You should have received a copy of the GNU General Public License along
 with MacPatch; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */

#include "EventToSend.h"

OSStatus SendAppleEventToSystemProcess(AEEventID EventToSend)
{
    AEAddressDesc targetDesc;
    static const ProcessSerialNumber kPSNOfSystemProcess = { 0, kSystemProcess };
    AppleEvent eventReply = {typeNull, NULL};
    AppleEvent appleEventToSend = {typeNull, NULL};
	
    OSStatus error = noErr;
	
    error = AECreateDesc(typeProcessSerialNumber, &kPSNOfSystemProcess, 
						 sizeof(kPSNOfSystemProcess), &targetDesc);
	
    if (error != noErr)
    {
        return(error);
    }
	
    error = AECreateAppleEvent(kCoreEventClass, EventToSend, &targetDesc, 
							   kAutoGenerateReturnID, kAnyTransactionID, &appleEventToSend);
	
    AEDisposeDesc(&targetDesc);
    if (error != noErr)
    {
        return(error);
    }
	
    //error = AESend(&appleEventToSend, &eventReply, kAENoReply, 
	//			   kAENormalPriority, kAEDefaultTimeout, NULL, NULL);
	error = AESend(&appleEventToSend, &eventReply, kAENoReply, 
				   kAEHighPriority, 20000, NULL, NULL);
	
	
    AEDisposeDesc(&appleEventToSend);
    if (error != noErr)
    {
        return(error);
    }
	
    AEDisposeDesc(&eventReply);
	
    return(error); 
}
