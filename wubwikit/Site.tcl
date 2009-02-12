#! /usr/bin/env tclsh

variable wubdir "../../Wub/"	;# relative path to Wub libraries
if {![file isdirectory $wubdir]} {
    if {[file isdirectory ../$wubdir]} {
	# running WubWikit from the svn trunk dir?
	set wubdir ../$wubdir
    } elseif {[file isdirectory ../../$wubdir]} {
	# running WubWikit from an svn branch dir?
	set wubdir ../../$wubdir
    }
}
lappend auto_path /usr/lib/ $wubdir
package require Site	;# load main Site configuration

Site init application WikitWub home [file normalize [file dirname [info script]]]

#### WikitWub-specific Configuration
# create data and document dirs, priming them from original
namespace eval Site {
}

#### Wikit Db Initialization

# load Wikit packages
lappend auto_path ../wikit/ /usr/lib/tcl8.5/Mk4tcl/
package require Mk4tcl

package require Wikit::Format
namespace import Wikit::Format::*
package require Wikit::Db

namespace eval Site {
}

if {[info exists Site::from_starkit] && $Site::from_starkit} {
    Site start listener [list -port $::port] https {-port -1} cmdport $::cmdport
} else {
    Site start
    #Site start listener {-port 38080} https {-port -1}
}
