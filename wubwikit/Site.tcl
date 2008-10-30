#! /usr/bin/env tclsh

# env handling - remove the C-linked env
array set _env [array get ::env]; unset ::env
array set ::env [array get _env]; unset _env

namespace eval Site {
    # Site WikitWub-specific defaults
    # These may be overwritten by command line, or by vars.tcl
    variable home [file normalize [file dirname [info script]]]
    variable base "/tmp/wiki"		;# default place for wiki to live
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
    variable application WikitWub	;# what's our application package?
	
    variable overwrite 0		;# set both to overwrite
    variable reallyreallyoverwrite 0	;# set both to overwrite

    variable wikidb wikit.tkd		;# wikit's Metakit DB name
    variable history history		;# history directory
    variable readonly 0			;# the wiki is not readonly
    variable prime 0			;# we do not wish to prime the wikit
    variable utf8clean 0		;# we do not want utf8 cleansing
    variable upflag ""			;# no URL syncing

    variable multi 0			;# we're single-threaded
    variable globaldocroot 0		;# use the local docroot
    variable varnish {}			;# don't use varnish cache by default
    variable cache {maxsize 204800}	;# use in-RAM cache by default
}

lappend auto_path /usr/lib/ $Site::wubdir
package require Site	;# load main Site configuration

#### WikitWub-specific Configuration
# create data and document dirs, priming them from original
namespace eval Site {
    variable origin $docroot ;# the original copies for priming
    variable wikitroot [file join $base data]	;# where the wikit lives
    set docroot [file join $base docroot]	;# where ancillary docs live

    catch {file mkdir $wikitroot}

    if {![file exists $docroot]} {
	# copy the origin docroot to $base
	file copy $origin [file dirname $docroot]
	file copy [file join $home doc.sample $wikidb] $wikitroot
    } elseif {$reallyreallyoverwrite && $overwrite} {
	# destructively overwrite the $base with the origin
	file delete -force $docroot
	file copy -force $origin [file dirname $docroot]
	file copy -force [file join $home doc $wikidb] $wikitroot
    } else {
	#puts stderr "Not overwriting existing docroot '$docroot'"
    }
    
    # clean up any symlinks in docroot
    package require functional
    package require fileutil
    foreach file [::fileutil::find $docroot [lambda {file} {
	return [expr {[file type [file join [pwd] $file]] eq "link"}]
    }]] {
	set dfile [file join [pwd] $file]
	file copy [file join $drdir [K [file link $dfile] [file delete $dfile]]] $dfile
    }
    
    # create history directory
    if {![info exists ::env(WIKIT_HIST)]} {
	if {$history ne ""} {
	    if {[file pathtype $history] ne "absolute"} {
		set history [file join $wikitroot $history]
	    }
	    set ::env(WIKIT_HIST) $history
	    catch {file mkdir $history}
	}
    } else {
	catch {file mkdir $::env(WIKIT_HIST)}
    }
}

#### Wikit Db Initialization

# load Wikit packages
lappend auto_path ../wikit/ /usr/lib/tcl8.5/Mk4tcl/
package require Mk4tcl
package require Wikit::Format
namespace import Wikit::Format::*
package require Wikit::Db

namespace eval Site {
    # initialize wikit DB
    Wikit::WikiDatabase [file join $wikitroot $wikidb] wdb 1

    # prime wikit db if needed
    if {$prime && [mk::view size wdb.pages] == 0} {
	# copy first 10 pages of the default datafile 
	set fd [open [file join $home doc wikidoc.tkd]]
	mk::file load wdb $fd
	close $fd
	mk::view size wdb.pages 10
	mk::view size wdb.archive 0
	Wikit::FixPageRefs
    }

    proc cleanseUTF {} {
	set size [mk::view size wdb.pages]
	set bad 0
	set bogus 0
	set incr 1
	for {set i 0} {$i < $size} {incr i $incr} {
	    set incr 1
	    foreach f {name page} {
		set d [mk::get wdb.pages!$i $f]
		if {$d eq ""} continue
		set point [::utf8::findbad $d]
		if {$point < [string length $d] - 1} {
		    if {$point < 0} {
			puts stderr "$f $i bogus $point"
			mk::set wdb.pages!$i $f "bogus [incr bogus]"
		    } else {
			incr bad
			incr point
			#utf8::reportTrouble $i $data $point
			puts stderr "$f $i bad"
			::utf8::fixBadUtf8 $d
			if {0} {
			    set incr -1
			    puts stderr "$f $i bad at $point"
			    mk::set wdb.pages!$i $f [string replace $d $point $point " badutf "]
			}
		    }
		    mk::file commit wdb
		}
	    }
	}
	puts stderr "BAD: $bad / $size"
    }

    package require utf8
    variable utf8re [::utf8::makeUtf8Regexp]
    if {$utf8clean} {
	# cleanse bad utf8 characters if requested
	cleanseUTF
    }

    if {$upflag ne ""} {
	Wikit::DoSync $upflag	;# URL sync, if requested.
    }
}

#Site start
Site start listener {-port 38080} https {-port -1}
