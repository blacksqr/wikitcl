#! /usr/bin/env tclsh
lappend auto_path /usr/lib/

#### Configuration
# set some default configuration flags and values
foreach {name val} [subst {
    listener_port 8080
    scgi_port 8088
    base "/tmp/wiki"
    globaldocroot 0
    backends 5
    wubdir "../../Wub/"
    cmdport 8082
    overwrite 0

    host [info hostname]
    multi 0

    wikidb wikit.tkd
    history history
    readonly 0
    prime 0
    utf8 0
    upflag ""
}] {
    set $name $val
}

# load site configuration script (not under SVN control)
catch {source [file join [file dirname [info script]] vars.tcl]}

# load command-line configuration vars
foreach {name val} $argv {
    set $name $val	;# set global config vars
}

# env handling - remove the C-linked env
array set _env [array get ::env]; unset ::env
array set ::env [array get _env]; unset _env

#### Directory location and construction
# set up home directory relative to script
set home [file normalize [file dirname [info script]]]

if {[info exists starkit::topdir]} {
    # starkit startup
    set topdir $starkit::topdir
    set drdir [file join $topdir docroot]
} else {
    # unpacked startup
    lappend auto_path $home

    # find Wub stuff
    set topdir [file normalize $wubdir]
    foreach lib {Mime extensions Wub Domains Utilities stx} {
	lappend auto_path [file join $topdir $lib]
    }

    # find docroot
    if {$globaldocroot} {
	set drdir [file join $topdir docroot]
    } else {
	set drdir [file join $home docroot]
    }
    #puts stderr "drdir:$drdir topdir:$topdir home:$home"
}

#package require HttpdThread	;# choose multithreaded
package require HttpdSingle	;# choose singlethreaded
package require Http		;# Http support
package require Debug 2.0

# uncomment to turn off caching for testing
# package provide Cache 2.0 ; proc Cache args {return {}}
package require Cache; Cache init maxsize 204800

# Application Starts Here

#### Docroot construction and priming
# create data and sessionroot dirs
catch {file mkdir [set data [file join $base data]]}
catch {file mkdir [set wikitroot $data]}

# copy the local docroot to $base
set docroot [file join $base docroot]
if {![file exists $docroot]} {
    file copy $drdir [file dirname $docroot]
    file copy [file join $home doc $wikidb] $wikitroot
} elseif {$overwrite} {
    file delete -force $docroot
    file copy -force $drdir [file dirname $docroot]
    file copy -force [file join $home doc $wikidb] $wikitroot
} else {
    puts stderr "Not overwriting existing docroot '$docroot'"
}

# create history directory
if {![info exists ::env(WIKIT_HIST)]} {
    if {$history ne ""} {
	if {[file pathtype $history] ne "absolute"} {
	    set history [file join $data $history]
	}
	set ::env(WIKIT_HIST) $history
	catch {file mkdir $::env(WIKIT_HIST)}
    }
} else {
    catch {file mkdir $::env(WIKIT_HIST)}
}
#puts stderr "History: $::env(WIKIT_HIST)"

# clean up any symlinks in docroot
package require functional
package require fileutil
foreach file [::fileutil::find $docroot  [lambda {file} {
    return [expr {[file type [file join [pwd] $file]] eq "link"}]
}]] {
    set dfile [file join [pwd] $file]
    file copy [file join $drdir [K [file link $dfile] [file delete $dfile]]] $dfile
}

#### Mime init
package require Mime
Mime::Init -dsname [file join $data ext2mime.tie]

#### Console init
package require Stdin
if {$cmdport eq ""} {
    Stdin start	;# start a command shell on stdin
} else {
    Stdin start $cmdport ;# start a command shell on localhost,$cmdport
}

#### Debug init
Debug on error 100
Debug on log 10
Debug on block 10

Debug off socket 10
Debug off http 2
Debug off cache 10
Debug off cookies 10
Debug off dispatch 10
Debug off wikit 10

#### Wikit Initialization

# load Wikit packages
package require Mk4tcl
package require Wikit::Format
namespace import Wikit::Format::*
package require Wikit::Db

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

# cleanse bad utf8 characters if requested
package require utf8
if {$utf8} {
    set size [mk::view size wdb.pages]
    set bad 0
    set bogus 0
    set incr 1
    for {set i 0} {$i < $size} {incr i $incr} {
	set incr 1
	foreach f {name page} {
	    set data [mk::get wdb.pages!$i $f]
	    if {$data eq ""} continue
	    set point [utf8::findbad $data]
	    if {$point < [string length $data] - 1} {
		if {$point < 0} {
		    puts stderr "$f $i bogus $point"
		    mk::set wdb.pages!$i $f "bogus [incr bogus]"
		} else {
		    incr bad
		    incr point
		    #utf8::reportTrouble $i $data $point
		    puts stderr "$f $i bad"
		    utf8::fixBadUtf8 $data
		    if {0} {
			set incr -1
			puts stderr "$f $i bad at $point"
			mk::set wdb.pages!$i $f [string replace $data $point $point " badutf "]
		    }
		}
		mk::file commit wdb
	    }
	}
    }
    puts stderr "BAD: $bad / $size"
}

if {$upflag ne ""} {
    Wikit::DoSync $upflag
}

catch {
    # perform wikit specific processing
    mk::get wdb.pages!9 page
}

#### Backend initialization
if {$multi} {
    package require Backend
    Debug.log {STARTING BACKENDS [clock format [clock seconds]]}
    set mkmutex [thread::mutex create]
    set Backend::incr $backends	;# reduce the backend thread quantum for faster testing
    Backend configure scriptdir [file dirname [info script]]
    Backend configure scriptname WikitWub.tcl
    Backend configure docroot $docroot wikitroot $wikitroot dataroot $data
    Backend configure utf8re [::utf8::makeUtf8Regexp]
    Backend configure mkmutex $mkmutex wikidb $wikidb wubdir $topdir
    Httpd configure dispatch Backend	;# script for each request
} else {
    foreach {n v} [subst {
	scriptdir [file dirname [info script]]
	scriptname WikitWub.tcl
	docroot $docroot
	wikitroot $wikitroot
	dataroot $data
	utf8re [::utf8::makeUtf8Regexp]
	wikidb $wikidb
	wubdir $topdir
    }] {
	set ::config($n) $v
    }

    #lappend auto_path $home
    package require WikitWub
    Httpd configure dispatch ""	;# script for each request
    proc Send {r} {
	if {[dict exists $r -send]} {
	    {*}[dict get $r -send] $r
	} else {
	    HttpdWorker Send $r
	}
    }
}

#### start Httpd protocol
Httpd configure server_id "Wub [package present Httpd]"
Httpd configure max 1 incr 1 over 40
if {[info exists server_port]} {
    # the listener and server ports differ
    Httpd configure server_port $server_port
}

#### start Listener
Listener listen -host $host -port $listener_port -httpd Httpd -dispatch Backend

#### start scgi Listener
if {[info exists scgi_port] && ($scgi_port > 0)} {
    package require scgi
    Debug on scgi 10
    Listener listen -host $host -port $scgi_port -httpd scgi -dispatch Incoming -send {::scgi Send}
}

#### Load local semantics from ./local.tcl
catch {source [file join [file dirname [info script]] local.tcl]} r eo
Debug.log {Site LOCAL: '$r' ($eo)}

set done 0
while {!$done} {
    vwait done
}

Debug.log {Shutdown top level}
