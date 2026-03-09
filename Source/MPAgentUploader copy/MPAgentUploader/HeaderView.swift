//
//  HeaderView.swift
//  MPAgentUploder
//
//  Created by Charles Heizer on 12/12/16.
//
/*
 Copyright (c) 2016, Lawrence Livermore National Security, LLC.
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

import Foundation

class HeaderView : NSView {
	
	var gradeTopColor: NSColor!
	var gradeBotColor: NSColor!
	
	override init(frame frameRect: NSRect) {
		super.init(frame:frameRect);
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)!
		gradeTopColor = NSColor.black
		gradeBotColor = NSColor.darkGray
	}
	
	//or customized constructor/ init
	init(frame frameRect: NSRect, otherInfo:Int) {
		super.init(frame:frameRect);
		// other code
	}
	
	@IBInspectable var topGradeColor: NSColor? {
		didSet {
			gradeTopColor = topGradeColor
		}
	}
	
	@IBInspectable var botGradeColor: NSColor? {
		didSet {
			gradeBotColor = botGradeColor
		}
	}
    
    override func draw(_ dirtyRect: NSRect) {
		// let blueColor: NSColor =
        let gradient = NSGradient.init(starting: gradeBotColor, ending: gradeTopColor)
        gradient?.draw(from: NSMakePoint(0,0), to: NSMakePoint(0,self.frame.size.height), options: NSGradient.DrawingOptions.drawsAfterEndingLocation)
    }
}
